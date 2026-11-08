local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Repertoire = require("src.fonts.repertoire")
local Transforms = require("src.document.transforms")
local M = {
  definitions = {
    {
      id = "swapColors",
      command = "AsemodeSwapColors",
      title = "Swap Ink and Cell Colors",
      icon = 1,
    },
    {
      id = "flipHorizontal",
      command = "AsemodeFlipHorizontal",
      title = "Flip Stamps Horizontally",
      icon = 2,
    },
    {
      id = "flipVertical",
      command = "AsemodeFlipVertical",
      title = "Flip Stamps Vertically",
      icon = 3,
    },
    {
      id = "rotateCounterclockwise",
      command = "AsemodeRotateCounterclockwise",
      title = "Rotate Stamps 90° Counterclockwise",
      icon = 4,
    },
    {
      id = "rotateClockwise",
      command = "AsemodeRotateClockwise",
      title = "Rotate Stamps 90° Clockwise",
      icon = 5,
    },
    {
      id = "resetOrientation",
      command = "AsemodeResetOrientation",
      title = "Reset Stamp Orientation",
    },
  },
}
local pc = app.pixelColor
local X, Y, D = pc.TILE_XFLIP, pc.TILE_YFLIP, pc.TILE_DFLIP
local byId = {}
M.icons = {}
for _, action in ipairs(M.definitions) do
  byId[action.id] = action
  if action.icon then
    M.icons[action.icon] = action
  end
end

---Decode and validate a stamp from a tile value.
---@param layer Layer Target text layer.
---@param value integer Tile value with flags.
---@param index table Font profile index table.
---@param optional boolean Whether an empty or missing stamp is permitted.
---@return table? stamp Decoded stamp record or nil if optional.
local function stamp(layer, value, index, optional)
  local meta, flags = Profile.decode(layer, value)
  if not meta then
    U.check(optional, "Select a primary Asemode stamp first")
    return nil
  end
  Repertoire.scalar(meta.glyphKey)
  U.check(
    meta.fontProfileId == index.id
      and index.glyphs[meta.glyphKey]
      and type(meta.imageHash) == "string"
      and meta.imageHash:match("^%x%x%x%x%x%x%x%x$")
      and U.isHexColor(meta.foregroundRGBA)
      and U.isHexColor(meta.backgroundRGBA)
      and Transforms.validFlags(flags),
    "Selected stamp has invalid Asemode data. Undo the edit or select another stamp."
  )
  return { value = value, index = pc.tileI(value), flags = flags, meta = meta }
end

---Read the live stamp selection without changing resources or UI state.
---@param id string Stamp action identifier.
---@param busy boolean Whether another Asemode operation is active.
---@return AsemodeStampSnapshot snapshot Captured host state; validate it before applying.
function M.read(id, busy)
  local action = byId[id]
  U.check(action, "Unknown Asemode stamp action: " .. tostring(id))
  U.check(not busy, "Finish the current Asemode operation first")
  local sprite, layer = app.sprite, app.layer
  U.check(Model.textLayer(sprite, layer), "Select an Asemode layer first")
  local profileId = Model.editable(sprite, layer)
  local fgTile, bgTile = app.fgTile, app.bgTile
  local index = Profile.index(sprite, profileId)
  return {
    action = action,
    sprite = sprite,
    layer = layer,
    profileId = profileId,
    fgTile = fgTile,
    bgTile = bgTile,
    primary = stamp(layer, fgTile, index, false),
    secondary = stamp(layer, bgTile, index, true),
  }
end

---Check whether a stamp action can run against the current host state.
---@param id string Stamp action identifier.
---@param busy boolean Whether another operation is active.
---@return boolean allowed Whether the action can run.
function M.canExecute(id, busy)
  return (pcall(M.read, id, busy))
end

---Compute modified orientation flags for an action.
---@param flags integer Existing transform flags.
---@param id string Action identifier.
---@return integer flags Transformed flags.
local function transformed(flags, id)
  if id == "flipHorizontal" then
    return flags ~ X
  end
  if id == "flipVertical" then
    return flags ~ Y
  end
  if id == "resetOrientation" then
    return 0
  end
  return Transforms.rotate(flags, id == "rotateClockwise")
end

-- The caller holds its busy guard while host notifications run. Publish both
-- selections only after all variant preparation succeeds; rollback resources and
-- host selections together if the swap cannot complete.
---Apply a stamp action and restore host selections if it fails.
---@param state AsemodeStampSnapshot Previously captured stamp state.
---@param colors table? Optional foreground and background RGBA colors.
---@return AsemodeStampSnapshot snapshot Updated live stamp state.
function M.apply(state, colors)
  local live = M.read(state.action.id, false)
  U.check(
    live.sprite == state.sprite
      and live.layer == state.layer
      and live.fgTile == state.fgTile
      and live.bgTile == state.bgTile,
    "The selected stamps changed; run the action again"
  )
  state = live
  local id, primary, secondary = state.action.id, state.primary, state.secondary
  local oldFgColor, oldBgColor = Color(app.fgColor), Color(app.bgColor)
  local function publish()
    app.fgTile = primary.value
    app.bgTile = secondary and secondary.value or state.bgTile
  end
  local function orientStamp(stamp, fg, bg, flags)
    if not stamp then
      return nil
    end
    return Profile.orientedTile(state.sprite, state.profileId, stamp.meta.glyphKey, fg, bg, flags)
  end
  local ok, err = pcall(function()
    if id == "swapColors" then
      local fg = colors and colors.foregroundRGBA or primary.meta.foregroundRGBA
      local bg = colors and colors.backgroundRGBA or primary.meta.backgroundRGBA
      app.transaction("Swap Asemode Ink and Cell Colors", function()
        local first = orientStamp(primary, bg, fg, primary.flags)
        local second = secondary and orientStamp(secondary, bg, fg, secondary.flags)
        primary.value = first
        if secondary then
          secondary.value = second
        end
        app.fgColor, app.bgColor = U.color(bg), U.color(fg)
        publish()
      end)
    else
      local function orient()
        local function nextValue(stamp)
          return orientStamp(
            stamp,
            stamp.meta.foregroundRGBA,
            stamp.meta.backgroundRGBA,
            transformed(stamp.flags, id)
          )
        end
        primary.value = nextValue(primary)
        if secondary then
          secondary.value = nextValue(secondary)
        end
        publish()
      end
      app.transaction("Orient Asemode Stamps", orient)
    end
  end)
  if not ok then
    Profile.invalidate()
    app.fgTile, app.bgTile = state.fgTile, state.bgTile
    if id == "swapColors" then
      app.fgColor, app.bgColor = oldFgColor, oldBgColor
    end
    error(err, 0)
  end
  return M.read(id, false)
end

return M
