local U = require("src.core.util")
local Edit = require("src.document.edit")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local M = {}

---Mirror a canvas and compose the mirror with each text cell's orientation.
---@param sprite Sprite Active sprite.
---@param orientation string Either "horizontal" or "vertical".
function M.apply(sprite, orientation)
  U.check(orientation == "horizontal" or orientation == "vertical", "Unsupported canvas flip")
  Validate.requireValid(sprite)
  local geometry = U.copy(Model.geometry(sprite))
  local horizontal = orientation == "horizontal"
  local layers = {}
  for _, layer in ipairs(Model.layers(sprite)) do
    if Model.layerManaged(layer) then
      local id = Model.meta(layer).fontProfileId
      local item = { layer = layer, id = id, targetId = id, cels = {} }
      for _, cel in ipairs(layer.cels) do
        item.cels[cel.frameNumber] = {
          x = cel.position.x,
          y = cel.position.y,
          width = cel.image.width * geometry.cellWidth,
          height = cel.image.height * geometry.cellHeight,
        }
      end
      layers[#layers + 1] = item
    end
  end
  app.transaction("Flip Asemode Canvas", function()
    app.command.Flip({ target = "canvas", orientation = orientation })
    if horizontal then
      geometry.originX = (sprite.width - geometry.originX) % geometry.cellWidth
    else
      geometry.originY = (sprite.height - geometry.originY) % geometry.cellHeight
    end
    Model.setMeta(sprite, geometry)
    for _, item in ipairs(layers) do
      for _, cel in ipairs(item.layer.cels) do
        local before = item.cels[cel.frameNumber]
        cel.position = Point(
          horizontal and sprite.width - before.x - before.width or before.x,
          horizontal and before.y or sprite.height - before.y - before.height
        )
      end
    end
    local flag = horizontal and app.pixelColor.TILE_XFLIP or app.pixelColor.TILE_YFLIP
    Edit.remapLayers(sprite, layers, function(flags)
      return flags ~ flag
    end)
    Profile.invalidate()
    Validate.requireValid(sprite)
  end)
end

return M
