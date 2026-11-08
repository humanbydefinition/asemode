local M = {}

---Install host drawing-mode methods on a session.
---@param session table Target drawing session object.
---@param state table Internal session state table.
function M.install(session, state)
  ---Restore the host drawing settings captured on entry.
  function session:leaveDrawingContext()
    local saved = state.nativeDrawingContext
    state.nativeDrawingContext, state.pendingMode, state.contextLayer = nil, nil, nil
    if not saved then
      return
    end
    if saved.sprite.isValid then
      local preferences = app.preferences.document(saved.sprite)
      if preferences.grid.snap == false then
        preferences.grid.snap = saved.snap
      end
    end
    state.pendingHostContext = saved
    self:restoreHostModes()
  end

  ---Restore host modes when Aseprite exposes an active tilemap site.
  function session:restoreHostModes()
    local saved = state.pendingHostContext
    if not (saved and app.isUIAvailable and app.layer and app.layer.isTilemap) then
      return
    end
    state.pendingHostContext = nil
    local mode = saved.tilesetMode == TilesetMode.MANUAL and "manual"
      or (saved.tilesetMode == TilesetMode.STACK and "stack" or "auto")
    if app.site.tilesetMode == TilesetMode.MANUAL then
      app.command.TilesetMode({ mode = mode })
    end
    if app.site.tilemapMode == TilemapMode.TILES and saved.tilemapMode ~= TilemapMode.TILES then
      app.command.ToggleTilesMode()
    end
  end

  ---Enter tile drawing mode and preserve the previous host settings.
  function session:enter()
    local sprite, layer = self:active()
    if not sprite or not app.isUIAvailable then
      return
    end
    if state.nativeDrawingContext and state.nativeDrawingContext.sprite ~= sprite then
      self:leaveDrawingContext()
    end
    self:restoreHostModes()
    local preferences = app.preferences.document(sprite)
    if not state.nativeDrawingContext then
      state.nativeDrawingContext = {
        sprite = sprite,
        snap = preferences.grid.snap,
        tilemapMode = app.site.tilemapMode,
        tilesetMode = app.site.tilesetMode,
      }
    end
    preferences.grid.snap = false
    app.command.TilesetMode({ mode = "manual" })
    if app.site.tilemapMode ~= TilemapMode.TILES then
      app.command.ToggleTilesMode()
    end
    state.contextLayer = layer
  end
end

return M
