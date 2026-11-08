local U = require("src.core.util")
local M = {}

---Install color synchronization methods on a drawing session.
---@param session table Target drawing session object.
---@param state table Internal session state table.
---@param changed fun() Notification callback when state changes.
function M.install(session, state, changed)
  ---Queue color synchronization for the active drawing target.
  ---@param source string Change origin.
  ---@param channel? string Changed native color channel.
  function session:queueColorCommit(source, channel)
    local sprite, layer = self:active()
    if not (sprite and layer) then
      state.pendingColors = nil
      return
    end
    if source == "external" and (sprite ~= state.ownerSprite or layer ~= state.lastLayer) then
      return
    end
    local previous = state.pendingColors
    local fg, bg
    if source == "external" then
      if previous and previous.sprite == sprite and previous.layer == layer then
        fg, bg =
          previous.source == "dialog" and state.fg or previous.fg,
          previous.source == "dialog" and state.bg or previous.bg
      else
        fg, bg = U.colorHex(app.fgColor), U.colorHex(app.bgColor)
      end
      if channel == nil or channel == "fgcolorchange" then
        fg = U.colorHex(app.fgColor)
      end
      if channel == nil or channel == "bgcolorchange" then
        bg = U.colorHex(app.bgColor)
      end
    end
    state.pendingColors = {
      sprite = sprite,
      layer = layer,
      source = source,
      quietTicks = 0,
      fg = fg,
      bg = bg,
    }
  end

  ---Update session colors and optionally queue a host color commit.
  ---@param source string? Change origin; nil skips the host commit.
  ---@param foreground string? Foreground RGBA color.
  ---@param background string? Background RGBA color.
  function session:setColors(source, foreground, background)
    if self:isBusy() then
      return
    end
    if source then
      self:ensureActive()
      state.invalidSaved = nil
      local pending = state.pendingColors
      if pending and pending.source == "external" then
        state.fg, state.bg = pending.fg, pending.bg
      end
    end
    if foreground then
      state.fg = foreground
    end
    if background then
      state.bg = background
    end
    state.secondaryFg, state.secondaryBg = state.fg, state.bg
    changed()
    if source then
      self:queueColorCommit(source)
    end
  end
end

return M
