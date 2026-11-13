local U = require("src.core.util")
local Edit = require("src.document.edit")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local Transforms = require("src.document.transforms")
local M = {}

---Rotate tile transform flags by a supported canvas angle (90, -90, 180 degrees).
---@param flags integer Native tile transform flags.
---@param angle integer Rotation angle in degrees (90, -90, 180).
---@return integer rotated Updated native tile transform flags.
local function rotateFlags(flags, angle)
  flags = Transforms.rotate(flags, angle ~= -90)
  return angle == 180 and Transforms.rotate(flags, true) or flags
end

---Rotate a complete sprite and the orientations of its Asemode cells.
---@param sprite Sprite Active sprite.
---@param angle integer Rotation angle in degrees.
function M.apply(sprite, angle)
  U.check(angle == 90 or angle == -90 or angle == 180, "Unsupported canvas rotation")
  Validate.requireValid(sprite)
  local old = Model.geometry(sprite)
  local width, height = sprite.width, sprite.height
  local quarter = angle ~= 180
  local rectangular = quarter and old.cellWidth ~= old.cellHeight
  local coverage = rectangular and Model.coverage(sprite, old) or nil
  local layers = {}
  for _, layer in ipairs(Model.layers(sprite)) do
    if Model.layerManaged(layer) then
      local id = Model.meta(layer).fontProfileId
      local item = { layer = layer, id = id, targetId = id, cels = {} }
      if rectangular then
        for _, cel in ipairs(layer.cels) do
          local col, row = Model.celOrigin(cel, old)
          item.cels[cel.frameNumber] =
            { col = col, row = row, width = cel.image.width, height = cel.image.height }
        end
      end
      layers[#layers + 1] = item
    end
  end
  if rectangular then
    U.check(
      coverage.rows * old.cellWidth <= 65535 and coverage.columns * old.cellHeight <= 65535,
      "Rotated canvas exceeds Aseprite dimensions"
    )
  end
  app.transaction("Rotate Asemode Canvas", function()
    app.command.Rotate({ ui = false, target = "sprite", angle = angle })
    local geometry = U.copy(old)
    if angle == 90 then
      geometry.originX, geometry.originY = height - old.originY, old.originX
    elseif angle == -90 then
      geometry.originX, geometry.originY = old.originY, width - old.originX
    else
      geometry.originX, geometry.originY = width - old.originX, height - old.originY
    end
    if rectangular then
      geometry.originX, geometry.originY = 0, 0
      sprite.width, sprite.height = coverage.rows * old.cellWidth, coverage.columns * old.cellHeight
      for _, item in ipairs(layers) do
        for _, cel in ipairs(item.layer.cels) do
          local before = item.cels[cel.frameNumber]
          local col, row = before.col - coverage.firstCol, before.row - coverage.firstRow
          if angle == 90 then
            cel.position =
              Point((coverage.rows - row - before.height) * old.cellWidth, col * old.cellHeight)
          else
            cel.position =
              Point(row * old.cellWidth, (coverage.columns - col - before.width) * old.cellHeight)
          end
        end
      end
    end
    geometry.originX = geometry.originX % geometry.cellWidth
    geometry.originY = geometry.originY % geometry.cellHeight
    Model.setMeta(sprite, geometry)
    Edit.remapLayers(sprite, layers, function(flags)
      return rotateFlags(flags, angle)
    end)
    Profile.invalidate()
    Validate.requireValid(sprite)
  end)
end
return M
