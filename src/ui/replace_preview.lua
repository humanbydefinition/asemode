local Profile = require("src.document.profile")
local Transforms = require("src.document.transforms")
local Theme = require("src.ui.theme")
local M = {}
M.WIDTH, M.HEIGHT = 220, 92
M.MAX_COLUMNS, M.MAX_ROWS = 8, 6

local HEADER_HEIGHT = 18
local CENTER_GAP = 24
local WELL_PADDING = 8

---Draw a directional arrow between the before and after preview wells.
---@param gc GraphicsContext Canvas graphics context.
---@param beforeWell table Geometry { x, y, width, height } of the left well.
---@param afterWell table Geometry { x, y, width, height } of the right well.
local function drawArrow(gc, beforeWell, afterWell)
  local midX = beforeWell.x
    + beforeWell.width
    + (afterWell.x - (beforeWell.x + beforeWell.width)) // 2
  local midY = beforeWell.y + beforeWell.height // 2
  gc.color = gc.theme.color.button_selected_text
  gc:fillRect(Rectangle(midX - 5, midY, 6, 1))
  gc:fillRect(Rectangle(midX + 1, midY - 2, 1, 5))
  gc:fillRect(Rectangle(midX + 2, midY - 1, 1, 3))
  gc:fillRect(Rectangle(midX + 3, midY, 1, 1))
end

---Calculate the before and after wells and scaled grid layout.
---@param width number Canvas width.
---@param height number Canvas height.
---@param profile AsemodeFontProfile Cell dimensions.
---@param columns? integer Selection columns.
---@param rows? integer Selection rows.
---@return table layout Preview geometry and clipping flag.
function M.layout(width, height, profile, columns, rows)
  local wellWidth = math.max(24, (width - CENTER_GAP) // 2)
  local wellHeight = math.max(24, height - HEADER_HEIGHT)
  local beforeWell = { x = 0, y = HEADER_HEIGHT, width = wellWidth, height = wellHeight }
  local afterWell =
    { x = width - wellWidth, y = HEADER_HEIGHT, width = wellWidth, height = wellHeight }
  local cols = math.max(1, math.min(M.MAX_COLUMNS, columns or 1))
  local rowsCount = math.max(1, math.min(M.MAX_ROWS, rows or 1))
  local availableW = math.max(1, wellWidth - 2 * WELL_PADDING)
  local availableH = math.max(1, wellHeight - 2 * WELL_PADDING)
  local naturalW = math.max(1, cols * profile.cellWidth)
  local naturalH = math.max(1, rowsCount * profile.cellHeight)
  local scale = Theme.fitScale(6, availableW, availableH, naturalW, naturalH)
  local cellW = math.max(1, math.floor(profile.cellWidth * scale))
  local cellH = math.max(1, math.floor(profile.cellHeight * scale))
  return {
    beforeWell = beforeWell,
    afterWell = afterWell,
    columns = cols,
    rows = rowsCount,
    cellWidth = cellW,
    cellHeight = cellH,
    gridWidth = cols * cellW,
    gridHeight = rowsCount * cellH,
    scale = scale,
    clipped = (columns or 0) > cols or (rows or 0) > rowsCount,
  }
end

---Apply replacement choices to a cell without mutating it.
---@param cell table Original cell.
---@param spec table Replacement settings.
---@return table cell Preview cell with selected attributes replaced.
function M.resolveAfterCell(cell, spec)
  return {
    col = cell.col,
    row = cell.row,
    glyphKey = spec.replaceGlyph and spec.glyph or cell.glyphKey,
    foregroundRGBA = spec.replaceFg and spec.fg or cell.foregroundRGBA,
    backgroundRGBA = spec.replaceBg and spec.bg or cell.backgroundRGBA,
    flags = spec.replaceGlyph and (spec.flags or 0) or (cell.flags or 0),
    outline = cell.outline,
  }
end

---Create a cached renderer for preview cells.
---@param index table Font profile and indexed glyph masks.
---@return fun(cell: table): Image renderer Cached cell image renderer.
function M.createRenderer(index)
  local cache = {}
  return function(cell)
    local flags = cell.flags or 0
    local key = table.concat({
      cell.glyphKey or "",
      cell.foregroundRGBA or "",
      cell.backgroundRGBA or "",
      tostring(flags),
      cell.outline or "none",
    }, "\0")
    if cache[key] then
      return cache[key]
    end
    local source = index.glyphs and index.glyphs[cell.glyphKey]
    local hasMask = source and not (source.meta and source.meta.renderFallback) and source.tile
    local mask = hasMask and source.tile.image
      or Image(index.profile.cellWidth, index.profile.cellHeight, ColorMode.RGB)
    if flags ~= 0 and hasMask then
      mask = Transforms.renderMask(mask, flags)
    end
    local image = Profile.colorize(mask, cell.foregroundRGBA, cell.backgroundRGBA, cell.outline)
    cache[key] = image
    return image
  end
end

---Paint cells within a preview well bounded by layout constraints.
---@param gc GraphicsContext Canvas graphics context.
---@param well table Target well bounding coordinates.
---@param layout table Scaled grid layout metrics.
---@param profile table Font profile with cell dimensions.
---@param selection table Captured cell selection snapshot.
---@param transformCell? fun(cell: table): table Optional cell transformation.
---@param renderCell fun(cell: table): Image Render function for colorized cell images.
local function paintGrid(gc, well, layout, profile, selection, transformCell, renderCell)
  local gx = well.x + (well.width - layout.gridWidth) // 2
  local gy = well.y + (well.height - layout.gridHeight) // 2
  for _, rawCell in ipairs(selection.cells) do
    local relCol = rawCell.col - selection.minCol
    local relRow = rawCell.row - selection.minRow
    if relCol >= 0 and relCol < layout.columns and relRow >= 0 and relRow < layout.rows then
      local cell = transformCell and transformCell(rawCell) or rawCell
      local image = renderCell(cell)
      local cx = gx + relCol * layout.cellWidth
      local cy = gy + relRow * layout.cellHeight
      gc:drawImage(
        image,
        Rectangle(0, 0, profile.cellWidth, profile.cellHeight),
        Rectangle(cx, cy, layout.cellWidth, layout.cellHeight)
      )
    end
  end
  gc.color = gc.theme.color.selected
  gc:strokeRect(Rectangle(gx - 1, gy - 1, layout.gridWidth + 2, layout.gridHeight + 2))
end

---Paint before and after previews for a selection.
---@param gc GraphicsContext Preview canvas.
---@param index table Font profile and indexed glyph masks.
---@param selection table? Captured selected cells.
---@param spec table? Replacement choices.
---@param renderCell? fun(cell: table): Image Optional cell renderer.
function M.paint(gc, index, selection, spec, renderCell)
  local p = index.profile
  local hasCells = selection and selection.count and selection.count > 0
  local layout = M.layout(
    gc.width,
    gc.height,
    p,
    hasCells and selection.columns or 1,
    hasCells and selection.rows or 1
  )
  gc.color = gc.theme.color.text or gc.theme.color.button_selected_text
  Theme.drawCenteredText(gc, layout.beforeWell, "Before", 2)
  Theme.drawCenteredText(gc, layout.afterWell, "After", 2)
  Theme.previewSurface(gc, layout.beforeWell)
  Theme.previewSurface(gc, layout.afterWell)
  drawArrow(gc, layout.beforeWell, layout.afterWell)

  if not hasCells then
    gc.color = Theme.placeholderColor(gc.theme.color)
    Theme.drawCenteredText(gc, layout.beforeWell, "Empty")
    Theme.drawCenteredText(gc, layout.afterWell, "Empty")
    return
  end

  local renderer = renderCell or M.createRenderer(index)
  paintGrid(gc, layout.beforeWell, layout, p, selection, nil, renderer)

  local activeAny = spec and (spec.replaceFg or spec.replaceBg or spec.replaceGlyph) or false
  local validAfter = activeAny and (not spec.replaceGlyph or spec.glyphValid)
  if not validAfter then
    gc.color = Theme.placeholderColor(gc.theme.color)
    Theme.drawCenteredText(gc, layout.afterWell, "?")
    return
  end

  paintGrid(gc, layout.afterWell, layout, p, selection, function(cell)
    return M.resolveAfterCell(cell, spec)
  end, renderer)
end

return M
