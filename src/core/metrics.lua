local U = require("src.core.util")
local M = {}

-- This is an outline-bounds check, not a count of cropped raster pixels.
---Find the cell edges crossed by a glyph's outline bounds.
---@param profile table Cell geometry and font scale.
---@param glyph table Glyph outline and bounds.
---@return table edges Flags for the left, right, top, and bottom edges.
function M.clippedEdges(profile, glyph)
  if glyph.renderFallback or not glyph.contours or #glyph.contours == 0 then
    return { left = false, right = false, top = false, bottom = false }
  end
  local scale = profile.scale
  return {
    left = profile.originX + (glyph.offsetX or 0) + glyph.xMin * scale < 0,
    right = profile.originX + (glyph.offsetX or 0) + glyph.xMax * scale > profile.cellWidth,
    top = profile.baseline - glyph.yMax * scale < 0,
    bottom = profile.baseline - glyph.yMin * scale > profile.cellHeight,
  }
end

---Test whether a glyph outline extends beyond its cell.
---@param profile table Cell geometry and font scale.
---@param glyph table Glyph outline and bounds.
---@return boolean clipped Whether the outline extends outside the cell.
function M.isClipped(profile, glyph)
  local edges = M.clippedEdges(profile, glyph)
  return edges.left or edges.right or edges.top or edges.bottom
end

---Measure a cell profile and update glyph horizontal offsets.
---@param font table Font metrics in font units.
---@param glyphs table[] Glyphs to measure and update.
---@param options table? Pixel size, cell dimensions, offsets, and antialiasing.
---@return table profile Measured cell profile and clipping count.
function M.measure(font, glyphs, options)
  options = options or {}
  local size = options.pixelSize or 8
  U.check(
    type(size) == "number" and size > 0 and size <= 512,
    "Font size must be greater than 0 and at most 512"
  )
  local scale = size / font.unitsPerEm
  local advance, top, bottom = 0, font.ascender * scale, font.descender * scale
  local supported = 0
  for _, g in ipairs(glyphs) do
    if not g.renderFallback then
      advance = math.max(advance, g.advance * scale)
      supported = supported + 1
    end
  end
  if supported == 0 then
    advance = (font.maxAdvance or font.unitsPerEm) * scale
  end
  local left, right = 0, advance
  for _, g in ipairs(glyphs) do
    g.offsetX = g.renderFallback and 0 or (advance - g.advance * scale) / 2
    if #g.contours > 0 then
      left = math.min(left, g.offsetX + g.xMin * scale)
      right = math.max(right, g.offsetX + g.xMax * scale)
      top = math.max(top, g.yMax * scale)
      bottom = math.min(bottom, g.yMin * scale)
    end
  end
  left, right, top, bottom = math.floor(left), math.ceil(right), math.ceil(top), math.floor(bottom)
  local width, height = math.max(1, right - left), math.max(1, top - bottom)
  local result = {
    schemaVersion = 1,
    pixelSize = size,
    unitsPerEm = font.unitsPerEm,
    scale = scale,
    advance = advance,
    ascender = font.ascender,
    descender = font.descender,
    lineGap = font.lineGap,
    naturalWidth = width,
    naturalHeight = height,
    cellWidth = options.cellWidth or width,
    cellHeight = options.cellHeight or height,
    baseline = top + (options.offsetY or 0),
    originX = -left + (options.offsetX or 0),
    antialias = options.antialias == true,
  }
  U.integer(result.cellWidth, "Cell width", 1, 512)
  U.integer(result.cellHeight, "Cell height", 1, 512)
  local clipped = 0
  for _, g in ipairs(glyphs) do
    if M.isClipped(result, g) then
      clipped = clipped + 1
    end
  end
  result.clippedGlyphs = clipped
  return result
end

---Calculate the horizontal centering offset for a glyph advance.
---@param profile table Cell geometry and font scale.
---@param glyphAdvance number Glyph advance width in font units.
---@return number offset Centering offset in pixels.
function M.offsetX(profile, glyphAdvance)
  return (profile.advance - glyphAdvance * profile.scale) / 2
end

return M
