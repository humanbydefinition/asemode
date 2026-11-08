local Metrics = require("src.core.metrics")
local Theme = require("src.ui.theme")
local M = {}
M.WIDTH, M.HEIGHT = 180, 70
M.COLUMNS, M.ROWS = 4, 2

local SAMPLE_LIMIT = M.COLUMNS * M.ROWS
local PREFERRED = { "A", "g", "j", "p", "M", "W", "0", "8" }

-- Keep mask indices, including when the font contains fallback characters.
---Choose visible glyph masks for the font preview, prioritizing clipping.
---@param job AsemodeFontJob Prepared font and masks.
---@return table[] sample Selected mask indices, keys, and clipping flags.
function M.sample(job)
  local selected, seen, byKey = {}, {}, {}
  for i, glyph in ipairs(job.glyphs) do
    byKey[glyph.glyphKey] = i
  end

  local function add(i, clipped)
    local glyph = i and job.glyphs[i]
    if #selected >= SAMPLE_LIMIT or not glyph or seen[i] or not job.masks[i] then
      return
    end
    if glyph.renderFallback or glyph.glyphKey == " " then
      return
    end
    if glyph.contours and #glyph.contours == 0 then
      return
    end
    selected[#selected + 1] = { index = i, key = glyph.glyphKey, clipped = clipped }
    seen[i] = true
  end
  for i, glyph in ipairs(job.glyphs) do
    if Metrics.isClipped(job.profile, glyph) then
      add(i, true)
    end
  end
  for _, key in ipairs(PREFERRED) do
    local i = byKey[key]
    if i then
      add(i, Metrics.isClipped(job.profile, job.glyphs[i]))
    end
  end
  for i, glyph in ipairs(job.glyphs) do
    add(i, Metrics.isClipped(job.profile, glyph))
    if #selected == SAMPLE_LIMIT then
      break
    end
  end
  return selected
end

---Calculate preview slots and scaled cell dimensions.
---@param width number Canvas width.
---@param height number Canvas height.
---@param profile AsemodeFontProfile Cell dimensions.
---@param count integer Number of glyphs to display.
---@return table layout Slot dimensions, scale, and placement.
function M.layout(width, height, profile, count)
  local cols = M.COLUMNS
  local rows = M.ROWS
  local slot = math.max(1, (width - 16) / cols)
  local availableHeight = math.max(1, (height - 20) / rows)
  local scale, w, h = Theme.fitScale(
    4,
    math.max(1, slot - 12),
    availableHeight,
    profile.cellWidth,
    profile.cellHeight
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
    reduced = scale < 1,
    leftGap = leftGap,
    gapX = gapX,
    topGap = topGap,
    gapY = gapY,
    columns = cols,
    rows = rows,
  }
end

---Paint selected glyph masks and baselines in a 4x2 grid.
---@param gc GraphicsContext Preview canvas.
---@param job AsemodeFontJob Font metrics and masks.
---@param sample table[] Selected preview glyphs.
function M.paint(gc, job, sample)
  Theme.previewSurface(gc)
  if #sample == 0 then
    gc.color = gc.theme.color.button_selected_text
    gc:fillText("No visible glyphs to preview", 10, 10)
    return
  end
  local p = job.profile
  local layout = M.layout(gc.width, gc.height, p, #sample)
  for n, item in ipairs(sample) do
    local col = (n - 1) % layout.columns
    local row = (n - 1) // layout.columns
    local x = layout.leftGap + col * (layout.width + layout.gapX)
    local y = layout.topGap + row * (layout.height + layout.gapY)
    gc:drawImage(
      job.masks[item.index],
      Rectangle(0, 0, p.cellWidth, p.cellHeight),
      Rectangle(x, y, layout.width, layout.height)
    )
    gc.color = gc.theme.color.selected
    gc:strokeRect(Rectangle(x - 1, y - 1, layout.width + 2, layout.height + 2))
    if p.baseline >= 0 and p.baseline <= p.cellHeight then
      local baselineY = y + math.floor(p.baseline / p.cellHeight * layout.height + 0.5)
      gc.color = gc.theme.color.button_selected_text
      gc:fillRect(Rectangle(x - 5, baselineY, 3, 1))
      gc:fillRect(Rectangle(x + layout.width + 2, baselineY, 3, 1))
    end
  end
end

return M
