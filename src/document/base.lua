local U = require("src.core.util")
local M = {}

---Copy the Asemode property namespace from a host object.
---@param object any Aseprite object supporting properties.
---@return table metadata Copy of its Asemode metadata.
function M.meta(object)
  local result = {}
  for k, v in pairs(object.properties("asemode")) do
    result[k] = v
  end
  return result
end

---Replace the Asemode property namespace on a host object.
---@param object any Aseprite object supporting properties.
---@param value table Metadata to persist.
function M.setMeta(object, value)
  object.properties("asemode", value)
end

---Check whether a valid sprite has the current Asemode schema.
---@param sprite Sprite? Sprite to inspect.
---@return boolean? managed True for a managed sprite; nil when absent.
function M.managed(sprite)
  return sprite and sprite.isValid and M.meta(sprite).schemaVersion == 1
end

---Check whether a tilemap layer has the current Asemode schema.
---@param layer Layer? Layer to inspect.
---@return boolean? managed True for a managed layer; nil when absent.
function M.layerManaged(layer)
  return layer and layer.isTilemap and M.meta(layer).schemaVersion == 1
end

---Read and validate the grid geometry of a managed RGB document.
---@param sprite Sprite Managed sprite.
---@return table geometry Document metadata containing validated grid dimensions and origin.
function M.geometry(sprite)
  U.check(M.managed(sprite), "Open an Asemode document or create one first")
  local d = M.meta(sprite)
  U.check(sprite.colorMode == ColorMode.RGB, "Asemode requires an RGBA document")
  U.integer(d.cellWidth, "Stored cell width", 1, 512)
  U.integer(d.cellHeight, "Stored cell height", 1, 512)
  U.integer(d.originX, "Stored grid origin X", -65535, 65535)
  U.integer(d.originY, "Stored grid origin Y", -65535, 65535)
  return d
end

return M
