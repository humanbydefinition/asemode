local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local Snapshot = require("src.document.snapshot")
local M = {}

---Export a layer as text and report discarded visual information.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to export.
---@param frame Frame|integer Source frame or number.
---@param options table? ASCII and lossy-transform options.
---@return string text Exported text with a trailing newline.
---@return table details Color-loss flag, transform count, and grid size.
function M.text(sprite, layer, frame, options)
  options = options or {}
  U.check(Model.layerManaged(layer), "Select an Asemode layer")
  local snapshot = Snapshot.capture(sprite, { layer }, frame)
  local extent = snapshot.extent
  local cols, rows = extent.columns, extent.rows
  local lines, transformed = {}, 0
  for row = 0, rows - 1 do
    local chars = {}
    for col = 0, cols - 1 do
      local char = " "
      local cell = snapshot.layers[1].rows[row + 1][col + 1]
      if cell then
        local meta, flags = cell.meta, cell.flags
        char = meta.glyphKey
        if flags ~= 0 then
          transformed = transformed + 1
        end
        U.check(
          not options.ascii or utf8.codepoint(char) <= 126,
          string.format(
            "ASCII cannot represent U+%04X at cell %d,%d",
            utf8.codepoint(char),
            col,
            row
          )
        )
      end
      chars[#chars + 1] = char
    end
    lines[#lines + 1] = table.concat(chars)
  end
  U.check(
    transformed == 0 or options.allowTransforms,
    "Text export discards "
      .. transformed
      .. " transformed glyph(s); enable lossy transforms explicitly"
  )
  return table.concat(lines, "\n") .. "\n",
    { colorLoss = true, transformed = transformed, columns = cols, rows = rows }
end

---Write a font atlas image and JSON manifest.
---@param sprite Sprite Source document.
---@param id string Font profile identifier.
---@param pngPath string Destination image path.
---@param jsonPath string Destination manifest path.
---@return table manifest Atlas metadata written to disk.
function M.atlas(sprite, id, pngPath, jsonPath)
  Validate.requireValid(sprite)
  local index = Profile.index(sprite, id)
  local count, w, h = #index.order, index.profile.cellWidth, index.profile.cellHeight
  -- A final row can have unused slots; glyphCount explicitly describes them.
  local columns = math.min(16, count)
  local rows = math.ceil(count / columns)
  local image = Image(columns * w, rows * h, ColorMode.RGB)
  local glyphs = {}
  for i, key in ipairs(index.order) do
    local source = index.glyphs[key]
    local x, y = (i - 1) % columns * w, (i - 1) // columns * h
    image:drawImage(source.tile.image, Point(x, y))
    local m = source.meta
    glyphs[#glyphs + 1] = {
      glyphKey = key,
      codePoint = utf8.codepoint(key),
      x = x,
      y = y,
      advance = m.advance,
      xMin = m.xMin,
      xMax = m.xMax,
      yMin = m.yMin,
      yMax = m.yMax,
      offsetX = m.offsetX,
      renderFallback = m.renderFallback,
    }
  end
  local manifest = {
    format = "asemode-atlas",
    version = 1,
    columns = columns,
    rows = rows,
    glyphCount = count,
    cellWidth = w,
    cellHeight = h,
    profile = index.profile,
    glyphs = glyphs,
  }
  image:saveAs(pngPath)
  U.write(jsonPath, U.prettyJson(manifest))
  return manifest
end

return M
