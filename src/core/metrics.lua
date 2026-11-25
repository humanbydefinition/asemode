local U = require("src.core.util")
local M = {}
-- Font coordinates are scaled floating-point values. Ignore errors far below a pixel.
local EPSILON = 1e-9

---Round an extent up to whole pixels without adding a pixel for floating-point noise.
---@param extent number Extent in pixels.
---@return integer pixels Whole-pixel extent.
local function pixelExtent(extent)
  local nearest = math.floor(extent + 0.5)
  return math.max(1, math.abs(extent - nearest) <= EPSILON and nearest or math.ceil(extent))
end

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
    left = profile.originX + (glyph.offsetX or 0) + glyph.xMin * scale < -EPSILON,
    right = profile.originX + (glyph.offsetX or 0) + glyph.xMax * scale
      > profile.cellWidth + EPSILON,
    top = profile.baseline - glyph.yMax * scale < -EPSILON,
    bottom = profile.baseline - glyph.yMin * scale > profile.cellHeight + EPSILON,
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
  if supported == 0 or advance == 0 then
    advance = ((font.maxAdvance and font.maxAdvance > 0) and font.maxAdvance or font.unitsPerEm)
      * scale
  end
  local left, right = 0, advance
  local placement = { advance = advance, scale = scale }
  for _, g in ipairs(glyphs) do
    g.offsetX = g.renderFallback and 0 or M.offsetX(placement, g)
    if #g.contours > 0 then
      left = math.min(left, g.offsetX + g.xMin * scale)
      right = math.max(right, g.offsetX + g.xMax * scale)
      top = math.max(top, g.yMax * scale)
      bottom = math.min(bottom, g.yMin * scale)
    end
  end
  local width, height = pixelExtent(right - left), pixelExtent(top - bottom)
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

---Choose the largest integer size at or below the preferred size that fits the primary glyphs.
---@param font table Parsed font metrics.
---@param glyphs table[] Complete glyph repertoire, including required characters.
---@param options table Cell dimensions and rendering options.
---@param primary table<string, boolean> Character keys to prioritize.
---@return table profile Measured profile at the chosen size.
---@return integer clipped Number of primary outlines that cross cell edges.
function M.fit(font, glyphs, options, primary)
  local size = math.max(1, math.min(128, math.floor(tonumber(options.pixelSize) or 8)))
  local measured, clipped
  local candidate = {}
  for key, value in pairs(options) do
    candidate[key] = value
  end
  for nextSize = size, 1, -1 do
    candidate.pixelSize = nextSize
    measured = M.measure(font, glyphs, candidate)
    clipped = 0
    for _, glyph in ipairs(glyphs) do
      if primary[glyph.glyphKey] and M.isClipped(measured, glyph) then
        clipped = clipped + 1
      end
    end
    if clipped == 0 then
      break
    end
  end
  return measured, clipped
end

---Place a glyph in its nominal advance without shifting zero-advance outlines out of the cell.
---@param profile table Cell geometry and font scale.
---@param glyph table Glyph advance and outline bounds in font units.
---@return number offset Centering offset in pixels.
function M.offsetX(profile, glyph)
  if glyph.advance == 0 then
    local left, right = glyph.xMin * profile.scale, glyph.xMax * profile.scale
    if left >= -EPSILON and right <= profile.advance + EPSILON then
      return 0
    end
    return (profile.advance - left - right) / 2
  end
  return (profile.advance - glyph.advance * profile.scale) / 2
end

return M
