local U = require("src.core.util")
local Profile = require("src.document.profile")
local M = {}

---Resolve the active Profile module or test mock.
---@return table profile Active profile module.
local function currentProfile()
  return package.loaded["src.document.profile"] or Profile
end

---Remap linked cels across layers before replacing any source image.
---@param sprite Sprite Document containing the layers.
---@param layers table[] Staged layer remap descriptors with { layer, id, targetId }.
---@param flagsTransform? fun(flags: integer): integer Optional transform callback for tile flags.
function M.layers(sprite, layers, flagsTransform)
  local profile = currentProfile()
  local seen, copies, variants = {}, {}, {}
  for _, item in ipairs(layers) do
    for _, cel in ipairs(item.layer.cels) do
      local previous = seen[cel.image.id]
      if previous then
        U.check(previous.id == item.id, "Linked cels use different Asemode font profiles")
      else
        local copy = {
          cel = cel,
          image = cel.image:clone(),
          layer = item.layer,
          id = item.id,
          targetId = item.targetId,
        }
        seen[cel.image.id] = copy
        copies[#copies + 1] = copy
      end
    end
  end
  for _, copy in ipairs(copies) do
    local values = variants[copy.id] or {}
    variants[copy.id] = values
    for pixel in copy.image:pixels() do
      local value = pixel()
      if value ~= 0 and not values[value] then
        local meta, flags = profile.decode(copy.layer, value)
        if meta then
          values[value] = profile.orientedTile(
            sprite,
            copy.targetId,
            meta.glyphKey,
            meta.foregroundRGBA,
            meta.backgroundRGBA,
            flagsTransform and flagsTransform(flags) or flags,
            meta.outline
          )
        end
      end
      if values[value] then
        pixel(values[value])
      end
    end
  end
  for _, copy in ipairs(copies) do
    copy.cel.image = copy.image
  end
end

return M
