local U = require("src.core.util")
local M = {}

---Validate a single Unicode scalar and return its code point.
---@param key string One Unicode character.
---@return integer codepoint Unicode scalar value.
function M.scalar(key)
  U.check(type(key) == "string" and utf8.len(key) == 1, "Enter one Unicode character")
  local cp = utf8.codepoint(key)
  U.check(cp <= 0x10ffff and (cp < 0xd800 or cp > 0xdfff), "Invalid Unicode character")
  return cp
end

---Validate and deduplicate character keys, preserving their first appearance.
---@param value string|string[] Text or a list of character keys.
---@return string[] keys Unique character keys.
function M.keys(value)
  if type(value) == "string" then
    value = U.characters(value)
  end
  U.check(type(value) == "table", "Provide character keys")
  local result, seen = {}, {}
  for _, key in ipairs(value) do
    M.scalar(key)
    if not seen[key] then
      result[#result + 1], seen[key] = key, true
    end
  end
  return result
end

---Find unavailable characters in Unicode code point order.
---@param available table<string, any> Available characters by key.
---@param keys string|string[] Characters to check.
---@return string[] missing Unavailable character keys.
function M.missing(available, keys)
  local result = {}
  for _, key in ipairs(M.keys(keys)) do
    if not available[key] then
      result[#result + 1] = key
    end
  end
  table.sort(result, function(a, b)
    return utf8.codepoint(a) < utf8.codepoint(b)
  end)
  return result
end

---Create an empty fallback glyph for an unavailable character.
---@param key string One Unicode character.
---@param profile AsemodeFontProfile? Profile used to calculate the advance.
---@return table glyph Fallback glyph metrics and empty outline.
function M.fallback(key, profile)
  return {
    glyphKey = key,
    codePoint = M.scalar(key),
    renderFallback = "space",
    advance = profile and profile.cellWidth / (profile.scale or 1) or 0,
    xMin = 0,
    xMax = 0,
    yMin = 0,
    yMax = 0,
    offsetX = 0,
    contours = {},
    points = {},
  }
end

---Reject repertoires that exceed glyph or mask memory limits.
---@param profile AsemodeFontProfile Profile with cell dimensions and font kind.
---@param count integer Number of glyphs.
function M.budget(profile, count)
  U.check(
    count <= (profile.kind == "truetype" and 16384 or 65535),
    "Font repertoire exceeds the glyph limit"
  )
  U.check(
    count * profile.cellWidth * profile.cellHeight * 4 <= 128 * 1024 * 1024,
    "Font masks exceed 128 MiB; reduce cell size or choose fewer characters"
  )
end

---Build persisted glyph metadata with a hash of its rendered image.
---@param glyph table Glyph identity and metrics.
---@param image Image Rendered glyph mask.
---@return table metadata Serializable glyph metadata.
function M.metadata(glyph, image)
  return {
    schemaVersion = 1,
    glyphKey = glyph.glyphKey,
    imageHash = U.hash(image.bytes),
    advance = glyph.advance,
    xMin = glyph.xMin,
    xMax = glyph.xMax,
    yMin = glyph.yMin,
    yMax = glyph.yMax,
    offsetX = glyph.offsetX or 0,
    renderFallback = glyph.renderFallback,
  }
end

return M
