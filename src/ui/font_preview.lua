local Metrics = require("src.core.metrics")
local Theme = require("src.ui.theme")
local Render = require("src.fonts.render")
local M = {}
M.WIDTH, M.HEIGHT = 180, 100
M.COMPACT_WIDTH, M.COMPACT_HEIGHT = 180, 70
M.COLUMNS, M.ROWS = 4, 2

local SAMPLE_LIMIT = M.COLUMNS * M.ROWS
local OVERFLOW_LIMIT = 128
local PREFERRED = { "A", "g", "j", "p", "M", "W", "0", "8" }

-- Keep mask indices, including when the font contains fallback characters.
---Choose visible glyph masks for the font preview, prioritizing clipping.
---@param job AsemodeFontJob Prepared font and masks.
---@return table[] sample Selected mask indices, keys, and clipped edges.
function M.sample(job)
  local selected, seen, byKey = {}, {}, {}
  for i, glyph in ipairs(job.glyphs) do
    byKey[glyph.glyphKey] = i
  end

  local function add(i)
    local glyph = i and job.glyphs[i]
    if #selected >= SAMPLE_LIMIT or not glyph or seen[i] or not job.masks[i] then
      return
    end
    if glyph.renderFallback or (glyph.glyphKey == " " and not glyph.contours) then
      return
    end
    if glyph.contours and #glyph.contours == 0 then
      return
    end
    local edges = Metrics.clippedEdges(job.profile, glyph)
    selected[#selected + 1] = {
      index = i,
      key = glyph.glyphKey,
      clipped = edges.left or edges.right or edges.top or edges.bottom,
      edges = edges,
    }
    seen[i] = true
  end
  for i, glyph in ipairs(job.glyphs) do
    if Metrics.isClipped(job.profile, glyph) then
      add(i)
      if #selected == SAMPLE_LIMIT then
        break
      end
    end
  end
  for _, key in ipairs(PREFERRED) do
    local i = byKey[key]
    if i then
      add(i)
    end
  end
  for i, glyph in ipairs(job.glyphs) do
    add(i)
    if #selected == SAMPLE_LIMIT then
      break
    end
  end
  return selected
end

---Prepare bounded overflow masks for the selected TrueType glyphs.
---@param job AsemodeFontJob Prepared font and masks.
---@param sample table[] Selected glyphs.
---@return table extent Maximum overflow on each edge and truncation flag.
function M.prepare(job, sample)
  local p = job.profile
  local extent = { left = 0, right = 0, top = 0, bottom = 0, truncated = false }
  local pc = app.pixelColor
  for _, item in ipairs(sample) do
    local glyph = job.glyphs[item.index]
    if item.clipped and glyph.contours and #glyph.contours > 0 then
      local x = p.originX + (glyph.offsetX or 0)
      local raw = {
        left = math.max(0, math.ceil(-(x + glyph.xMin * p.scale))),
        right = math.max(0, math.ceil(x + glyph.xMax * p.scale - p.cellWidth)),
        top = math.max(0, math.ceil(glyph.yMax * p.scale - p.baseline)),
        bottom = math.max(0, math.ceil(p.baseline - glyph.yMin * p.scale - p.cellHeight)),
      }
      local padding = {}
      for _, edge in ipairs({ "left", "right", "top", "bottom" }) do
        padding[edge] = math.min(OVERFLOW_LIMIT, raw[edge])
        extent[edge] = math.max(extent[edge], padding[edge])
        extent.truncated = extent.truncated or raw[edge] > OVERFLOW_LIMIT
      end
      local width = p.cellWidth + padding.left + padding.right
      local height = p.cellHeight + padding.top + padding.bottom
      local raster = Render.mask(glyph, {
        cellWidth = width,
        cellHeight = height,
        originX = p.originX + padding.left,
        baseline = p.baseline + padding.top,
        scale = p.scale,
        antialias = p.antialias,
      })
      local overflow = Image(width, height, ColorMode.RGB)
      for y = 0, height - 1 do
        for xPixel = 0, width - 1 do
          if
            xPixel < padding.left
            or xPixel >= padding.left + p.cellWidth
            or y < padding.top
            or y >= padding.top + p.cellHeight
          then
            local alpha = pc.rgbaA(raster:getPixel(xPixel, y))
            if alpha > 0 then
              overflow:drawPixel(xPixel, y, pc.rgba(255, 193, 72, alpha))
            end
          end
        end
      end
      item.overflow = overflow
      item.padding = padding
    end
  end
  return extent
end

---Calculate preview slots and scaled cell dimensions.
---@param width number Canvas width.
---@param height number Canvas height.
---@param profile AsemodeFontProfile Cell dimensions.
---@param count integer Number of glyphs to display.
---@param extent table? Maximum overflow around the cell.
---@param compact boolean? Whether to use the original cell-only layout.
---@return table layout Slot dimensions, scale, and placement.
function M.layout(width, height, profile, count, extent, compact)
  extent = extent or { left = 0, right = 0, top = 0, bottom = 0 }
  local cols = M.COLUMNS
  local rows = M.ROWS
  local slot = math.max(1, (width - (compact and 16 or 12)) / cols)
  local slotHeight = math.max(1, (height - (compact and 20 or 12)) / rows)
  local totalWidth = profile.cellWidth + extent.left + extent.right
  local totalHeight = profile.cellHeight + extent.top + extent.bottom
  local scale, w, h = Theme.fitScale(
    4,
    math.max(1, slot - (compact and 12 or 6)),
    math.max(1, slotHeight - (compact and 0 or 6)),
    totalWidth,
    totalHeight
  )

  local availX = math.max(0, width - cols * w)
  local gapX = math.floor(availX / (cols + 1))
  if (availX - (cols - 1) * gapX) % 2 ~= 0 then
    gapX = gapX + 1
  end
  local leftGap = math.floor((availX - (cols - 1) * gapX) / 2)

  local availY = math.max(0, height - rows * h)
  local gapY = math.floor(availY / (rows + 1))
  if (availY - (rows - 1) * gapY) % 2 ~= 0 then
    gapY = gapY + 1
  end
  local topGap = math.floor((availY - (rows - 1) * gapY) / 2)

  return {
    slot = slot,
    width = w,
    height = h,
    scale = scale,
    extent = extent,
    reduced = scale < 1,
    leftGap = leftGap,
    gapX = gapX,
    topGap = topGap,
    gapY = gapY,
    columns = cols,
    rows = rows,
  }
end

---Paint selected glyph masks and overflow in a 4x2 grid.
---@param gc GraphicsContext Preview canvas.
---@param job AsemodeFontJob Font metrics and masks.
---@param sample table[] Selected preview glyphs.
---@param extent table? Maximum overflow around the cell.
function M.paint(gc, job, sample, extent)
  Theme.previewSurface(gc)
  if #sample == 0 then
    gc.color = gc.theme.color.button_selected_text
    gc:fillText("No visible glyphs to preview", 10, 10)
    return
  end
  local p = job.profile
  local compact = p.clippedGlyphs == 0
  local layout = M.layout(gc.width, gc.height, p, #sample, extent, compact)
  for n, item in ipairs(sample) do
    local col = (n - 1) % layout.columns
    local row = (n - 1) // layout.columns
    local x = layout.leftGap
      + col * (layout.width + layout.gapX)
      + math.floor(layout.extent.left * layout.scale)
    local y = layout.topGap
      + row * (layout.height + layout.gapY)
      + math.floor(layout.extent.top * layout.scale)
    local function scaled(value)
      return math.floor(value * layout.scale + 0.5)
    end
    local cellWidth, cellHeight =
      math.max(1, scaled(p.cellWidth)), math.max(1, scaled(p.cellHeight))
    if not compact then
      gc.color = gc.theme.color.selected
      gc:strokeRect(Rectangle(x - 1, y - 1, cellWidth + 2, cellHeight + 2))
    end
    if item.overflow then
      local pad = item.padding
      local left, top = scaled(pad.left), scaled(pad.top)
      local right, bottom = scaled(pad.right), scaled(pad.bottom)
      gc:drawImage(
        item.overflow,
        Rectangle(0, 0, item.overflow.width, item.overflow.height),
        Rectangle(x - left, y - top, left + cellWidth + right, top + cellHeight + bottom)
      )
    end
    gc:drawImage(
      job.masks[item.index],
      Rectangle(0, 0, p.cellWidth, p.cellHeight),
      Rectangle(x, y, cellWidth, cellHeight)
    )
    if compact then
      gc.color = gc.theme.color.selected
      gc:strokeRect(Rectangle(x - 1, y - 1, cellWidth + 2, cellHeight + 2))
      if p.baseline >= 0 and p.baseline <= p.cellHeight then
        local baselineY = y + math.floor(p.baseline / p.cellHeight * cellHeight + 0.5)
        gc.color = gc.theme.color.button_selected_text
        gc:fillRect(Rectangle(x - 5, baselineY, 3, 1))
        gc:fillRect(Rectangle(x + cellWidth + 2, baselineY, 3, 1))
      end
    end
  end
end

return M
