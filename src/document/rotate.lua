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
  local layers, profiles = {}, {}
  for _, layer in ipairs(Model.layers(sprite)) do
    if Model.layerManaged(layer) then
      layers[#layers + 1] = { layer = layer, id = Model.meta(layer).fontProfileId }
    elseif rectangular and layer.isTilemap then
      Model.checkUnmanagedTilemap(
        layer,
        "A native tilemap shares Asemode font tiles; give it an independent tileset first"
      )
    end
  end
  if rectangular then
    for _, entry in ipairs(Profile.profiles(sprite)) do
      local index = Profile.index(sprite, entry.id)
      local profile, glyphs, masks = U.copy(index.profile), {}, {}
      profile.cellWidth, profile.cellHeight = old.cellHeight, old.cellWidth
      for i = 1, #index.masks - 1 do
        local tile = index.masks:tile(i)
        glyphs[i] = Model.meta(tile)
        local image = Image(profile.cellWidth, profile.cellHeight, ColorMode.RGB)
        image:drawImage(
          tile.image,
          Point(
            (profile.cellWidth - old.cellWidth) // 2,
            (profile.cellHeight - old.cellHeight) // 2
          )
        )
        masks[i] = image
      end
      profiles[#profiles + 1] = {
        id = entry.id,
        masks = index.masks,
        paint = index.paint,
        job = { profile = profile, glyphs = glyphs, masks = masks, position = #glyphs },
      }
    end
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
      geometry.cellWidth, geometry.cellHeight = old.cellHeight, old.cellWidth
    end
    geometry.originX = geometry.originX % geometry.cellWidth
    geometry.originY = geometry.originY % geometry.cellHeight
    Model.setMeta(sprite, geometry)
    local replacements = {}
    for _, item in ipairs(profiles) do
      replacements[item.id] = Profile.install(sprite, item.job, true)
    end
    for _, item in ipairs(layers) do
      item.targetId = replacements[item.id] or item.id
    end
    Edit.remapLayers(sprite, layers, function(flags)
      return rotateFlags(flags, angle)
    end)
    for _, item in ipairs(layers) do
      if replacements[item.id] then
        Profile.bindLayer(item.layer, item.targetId, Profile.index(sprite, item.targetId))
      end
    end
    for _, item in ipairs(profiles) do
      sprite:deleteTileset(item.paint)
      sprite:deleteTileset(item.masks)
    end
    Profile.invalidate()
    Validate.requireValid(sprite)
  end)
end
return M
