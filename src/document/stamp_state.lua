local U = require("src.core.util")
local Repertoire = require("src.fonts.repertoire")
local Json = require("src.portable.json")
local Model = require("src.document.model")
local Profile = require("src.document.profile")

local M = {}
local FIELD = "stampStateJson"

---Resolve the active Model implementation or loaded test override.
---@return table model Active model module.
local function currentModel()
  return package.loaded["src.document.model"] or Model
end

---Resolve the active Profile implementation or loaded test override.
---@return table profile Active profile module.
local function currentProfile()
  return package.loaded["src.document.profile"] or Profile
end

---Check whether a table contains valid stamp properties.
---@param stamp any Candidate stamp table.
---@return boolean valid True if stamp has valid glyph, colors, and transform flags.
local function validStamp(stamp)
  local pc = app.pixelColor
  return type(stamp) == "table"
    and pcall(Repertoire.scalar, stamp.glyph)
    and U.isHexColor(stamp.fg)
    and U.isHexColor(stamp.bg)
    and math.type(stamp.flags) == "integer"
    and stamp.flags >= 0
    and stamp.flags & ~(pc.TILE_XFLIP | pc.TILE_YFLIP | pc.TILE_DFLIP) == 0
    and (stamp.empty == nil or type(stamp.empty) == "boolean")
end

---Validate and serialize primary and optional secondary stamp state.
---@param value table Stamp state to encode.
---@return string json Compact JSON representation.
function M.encode(value)
  assert(validStamp(value.primary), "Invalid primary stamp state")
  assert(
    value.secondary == nil or (validStamp(value.secondary) and not value.secondary.empty),
    "Invalid secondary stamp state"
  )
  return Json.stringify({
    version = 1,
    primary = value.primary,
    secondary = value.secondary or Json.null,
  }, { pretty = false })
end

---Read saved stamp state from a layer.
---@param layer Layer Layer containing saved metadata.
---@return table? state Valid state, or nil when absent or invalid.
---@return string? error Error message when saved data is invalid.
function M.read(layer)
  local raw = currentModel().meta(layer)[FIELD]
  if raw == nil then
    return nil
  end
  if type(raw) ~= "string" or #raw > 4096 then
    return nil, "Invalid saved Asemode stamp state"
  end
  local ok, value = pcall(Json.parse, raw)
  if
    not ok
    or type(value) ~= "table"
    or value.version ~= 1
    or not validStamp(value.primary)
    or (value.secondary ~= Json.null and (not validStamp(value.secondary) or value.secondary.empty))
  then
    return nil, "Invalid saved Asemode stamp state"
  end
  if value.secondary == Json.null then
    value.secondary = nil
  end
  return value
end

---Save stamp state on the active document when it has changed.
---@param sprite Sprite Active document.
---@param layer Layer Destination layer in the active document.
---@param value table Stamp state to save.
---@return boolean changed Whether metadata was written.
function M.write(sprite, layer, value)
  assert(
    app.sprite == sprite and layer.sprite == sprite,
    "Stamp state document is no longer active"
  )
  local encoded = M.encode(value)
  local ModelImpl = currentModel()
  local meta = ModelImpl.meta(layer)
  if meta[FIELD] == encoded then
    return false
  end
  app.transaction("Remember Asemode Stamps", function()
    meta[FIELD] = encoded
    ModelImpl.setMeta(layer, meta)
  end)
  return true
end

---Ensure saved stamps remain available after a profile change.
---@param sprite Sprite Document containing the layer.
---@param layer Layer Text layer with saved stamp metadata.
---@param profileId string Font profile identifier.
function M.reconcileLayer(sprite, layer, profileId)
  local saved, problem = M.read(layer)
  if problem then
    print("[Asemode] " .. problem .. "; select a stamp to replace it.")
    return
  end
  if not saved then
    return
  end
  local ProfileImpl = currentProfile()
  for _, stamp in ipairs({ saved.primary, saved.secondary }) do
    if not stamp.empty then
      ProfileImpl.orientedTile(sprite, profileId, stamp.glyph, stamp.fg, stamp.bg, stamp.flags)
    end
  end
end

return M
