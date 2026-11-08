local Model = require("src.document.model")
local M = {}

---Track open sprites and decide when to open the drawing panel.
---@return table tracker Project lifecycle tracker.
function M.new()
  local entries = {}
  local tracker = {}

  ---Detach change listeners and remove project entry.
  ---@param id any Sprite identifier.
  ---@param entry table Cached project entry containing sprite and listener.
  local function discard(id, entry)
    local sprite = entry.sprite
    if sprite.isValid and entry.listener then
      sprite.events:off(entry.listener)
    end
    entries[id] = nil
  end

  ---Check the current sprite after the host has finished changing sites.
  ---@param sprite Sprite? Active sprite.
  ---@param sprites Sprite[] Open sprites.
  ---@param panelOpen boolean Whether the panel is visible.
  ---@return boolean open Whether the panel should open.
  function tracker:check(sprite, sprites, panelOpen)
    local open = {}
    for _, item in ipairs(sprites) do
      open[item.id] = true
    end
    for id, entry in pairs(entries) do
      if not open[id] or not entry.sprite.isValid then
        discard(id, entry)
      end
    end
    if not (sprite and sprite.isValid and open[sprite.id]) then
      return false
    end
    local entry = entries[sprite.id]
    if not entry then
      entry = { dirty = true, sprite = sprite }
      entries[sprite.id] = entry
      entry.listener = sprite.events:on("change", function()
        entry.dirty = true
      end)
    end
    if entry.checked or entry.dismissed or not entry.dirty then
      return false
    end
    entry.dirty = false
    if Model.hasMarkedLayers(sprite) then
      entry.checked = true
      return not panelOpen
    end
    return false
  end

  ---Remember that the user closed the panel for this open sprite.
  ---@param sprite Sprite? Active sprite.
  function tracker:dismiss(sprite)
    local entry = sprite and entries[sprite.id]
    if entry then
      entry.dismissed = true
    end
  end

  ---Remove document listeners.
  function tracker:close()
    for id, entry in pairs(entries) do
      discard(id, entry)
    end
  end

  return tracker
end

return M
