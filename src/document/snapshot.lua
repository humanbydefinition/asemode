local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local M = {}

---Capture validated cell data for layers in one frame.
---@param sprite Sprite Source document.
---@param layers Layer[] Text layers to capture.
---@param frame Frame|integer Frame or frame number.
---@param options table? Cached geometry, extent, validation context, and checkpoint.
---@return table snapshot Grid geometry, captured rows, and outside-cell count.
function M.capture(sprite, layers, frame, options)
  options = options or {}
  local context = options.context
  local geometry = U.copy(options.geometry or Model.geometry(sprite))
  local extent = options.extent or Model.coverage(sprite, geometry)
  local number = U.frameNumber(frame)
  U.check(sprite.frames[number], "The captured frame was removed")
  local result = { geometry = geometry, extent = extent, layers = {}, outside = 0 }
  local cells = 0
  for _, layer in ipairs(layers) do
    U.check(Model.textLayer(sprite, layer), "Select a valid Asemode tilemap layer")
    local validationOptions = { frame = number, checkpoint = options.checkpoint }
    local issues = context and context:run(layer, validationOptions)
      or Validate.run(sprite, layer, validationOptions)
    U.check(#issues == 0, Validate.text(issues))
    cells = cells + extent.columns * extent.rows
    U.check(cells <= 4000000, "Snapshot exceeds the cumulative cell budget")
    local cel = layer:cel(number)
    local entry = { layer = layer, cel = cel, rows = {}, outside = 0 }
    local baseX, baseY = 0, 0
    if cel then
      baseX, baseY = Model.celOrigin(cel, geometry)
      for pixel in cel.image:pixels() do
        if pixel.x == 0 and options.checkpoint then
          options.checkpoint()
        end
        local col, row = baseX + pixel.x - extent.firstCol, baseY + pixel.y - extent.firstRow
        if
          app.pixelColor.tileI(pixel()) ~= 0
          and (col < 0 or row < 0 or col >= extent.columns or row >= extent.rows)
        then
          entry.outside = entry.outside + 1
        end
      end
    end
    for row = 0, extent.rows - 1 do
      if options.checkpoint then
        options.checkpoint()
      end
      local cellsInRow = {}
      for col = 0, extent.columns - 1 do
        local x, y = col + extent.firstCol - baseX, row + extent.firstRow - baseY
        if cel and x >= 0 and y >= 0 and x < cel.image.width and y < cel.image.height then
          local meta, flags = Profile.decode(layer, cel.image:getPixel(x, y))
          if meta then
            cellsInRow[col + 1] = { meta = meta, flags = flags }
          end
        end
      end
      entry.rows[row + 1] = cellsInRow
    end
    result.layers[#result.layers + 1] = entry
    result.outside = result.outside + entry.outside
  end
  return result
end
return M
