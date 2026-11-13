local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Stamps = require("src.actions.stamps")
local StampState = require("src.document.stamp_state")
local Rotate = require("src.document.rotate")
local Flip = require("src.document.flip")
local NativeOperations = require("src.session.native_operations")
local ColorSync = require("src.session.color_sync")
local HostContext = require("src.session.host_context")
local M = {}

-- Aseprite only updates its tile buttons when the preference changes. After
-- startup, the stored tile can already match while the button is still empty.
---Force update an Aseprite native tile preference.
---@param key string Preference property name ("fgTile" or "bgTile").
---@param tile integer Target tile index.
local function setNativeTile(key, tile)
  if app[key] == tile then
    app[key] = tile == 0 and 1 or 0
  end
  app[key] = tile
end

---Create a drawing session using the supplied host callbacks.
---@param options table Drawing callbacks and host integration.
---@return table session Drawing session.
function M.new(options)
  local state = {
    glyph = "0",
    bgGlyph = "1",
    fg = "#ffffffff",
    bg = "#000000ff",
    flags = 0,
    bgFlags = 0,
    secondaryFg = "#ffffffff",
    secondaryBg = "#000000ff",
    suppressionDepth = 0,
    subscriptions = {},
    spriteListeners = {},
    deferred = {},
  }
  local session = {}

  ---Notify host listener that session state has changed.
  local function changed()
    options.changed()
  end

  ---Display or log an alert warning for blocked native operations.
  ---@param message string|string[] Alert message text or array of lines.
  local function showNativeWarning(message)
    if state.warningOpen then
      return
    end
    state.warningOpen = true
    if app.isUIAvailable then
      local shown, problem = pcall(app.alert, { title = "Asemode", text = message })
      if not shown then
        print("[Asemode] Could not show warning: " .. tostring(problem))
      end
    else
      print("[Asemode] " .. (type(message) == "table" and table.concat(message, " ") or message))
    end
    state.warningOpen = false
  end

  ---Compute a stable lookup key for a layer.
  ---@param layer Layer Target layer.
  ---@return any key Layer ID or layer instance.
  local function layerKey(layer)
    return layer.id or layer
  end

  ---Return a copy of the current drawing selection and pending colors.
  ---@return table snapshot Drawing session state.
  function session:snapshot()
    local pending = state.pendingColors
    return {
      glyph = state.primaryEmpty and "" or state.glyph,
      primaryEmpty = state.primaryEmpty or false,
      bgGlyph = state.bgGlyph,
      fg = state.fg,
      bg = state.bg,
      flags = state.flags,
      bgFlags = state.bgFlags,
      secondaryFg = state.secondaryFg,
      secondaryBg = state.secondaryBg,
      missingPrimary = state.primaryError or false,
      missingSecondary = state.secondaryError or false,
      invalidSaved = state.invalidSaved or false,
      pendingColors = pending and {
        sprite = pending.sprite,
        layer = pending.layer,
        source = pending.source,
        quietTicks = pending.quietTicks,
      } or nil,
    }
  end

  ---Check whether drawing actions are blocked or suppressed.
  ---@return boolean busy Whether the session is busy.
  function session:isBusy()
    return state.suppressionDepth > 0 or options.blocksDrawing()
  end

  ---Run a callback while suppressing drawing synchronization.
  ---@param fn fun(): any Callback to run.
  ---@return any result Callback result.
  function session:withSuppression(fn)
    state.suppressionDepth = state.suppressionDepth + 1
    local ok, result = pcall(fn)
    state.suppressionDepth = state.suppressionDepth - 1
    if not ok then
      error(result, 0)
    end
    return result
  end

  ---Find the active valid text layer and its sprite.
  ---@return Sprite? sprite Active sprite, if eligible.
  ---@return Layer? layer Active text layer, if eligible.
  function session:active()
    local sprite, layer = app.sprite, app.layer
    if Model.textLayer(sprite, layer) then
      return sprite, layer
    end
  end

  ---Require an active editable text layer.
  ---@return Sprite sprite Active document.
  ---@return Layer layer Active editable text layer.
  function session:target()
    local sprite, layer = self:active()
    U.check(sprite and layer, "Select an Asemode layer or create a new textmode sprite")
    Model.editable(sprite, layer)
    return sprite, layer
  end

  ColorSync.install(session, state, changed)

  ---Update the selected glyphs after a portable import.
  ---@param foreground string Primary glyph key.
  ---@param background string? Secondary glyph key.
  ---@param importOptions table? Destination and imported paint count.
  function session:setImportedStamps(foreground, background, importOptions)
    if importOptions and importOptions.destination == "new" then
      state.pendingColors = nil
    end
    if importOptions and importOptions.destination == "existing" then
      local stamp = importOptions.paintCount > 1 and 1 or 0
      setNativeTile("fgTile", stamp)
      setNativeTile("bgTile", stamp)
      background = foreground
    end
    state.glyph, state.bgGlyph, state.flags, state.bgFlags = foreground, background, 0, 0
    state.primaryEmpty = importOptions
        and importOptions.destination == "existing"
        and importOptions.paintCount <= 1
      or false
    state.primaryError, state.secondaryError = nil, nil
    state.invalidSaved = nil
    state.secondaryFg, state.secondaryBg = state.fg, state.bg
    local sprite, layer = self:active()
    if sprite then
      state.ownerSprite, state.lastLayer = sprite, layer
      state.lastPersisted = nil
      state.deferred[layerKey(layer)] = nil
    end
    state.lastTile, state.lastBgTile = nil, nil
  end

  ---Discard cached stamp ownership and native tile selections.
  function session:invalidateStamps()
    state.ownerSprite, state.lastLayer = nil, nil
    state.lastTile, state.lastBgTile = nil, nil
    state.historyRestore = nil
  end

  HostContext.install(session, state)

  ---Prepare and select a native stamp for a glyph and colors.
  ---@param button? integer Native mouse button; defaults to primary.
  ---@param glyph? string Glyph key; defaults to the current primary glyph.
  ---@param flags? integer Orientation flags; defaults to current flags.
  function session:prepare(button, glyph, flags)
    if self:isBusy() then
      return
    end
    local sprite, layer = self:target()
    self:ensureActive()
    state.invalidSaved = nil
    local pending = state.pendingColors
    if
      pending
      and pending.sprite == sprite
      and pending.layer == layer
      and pending.source ~= "dialog"
    then
      state.pendingColors = nil
      state.fg, state.bg = pending.fg, pending.bg
    end
    local id = Model.meta(layer).fontProfileId
    glyph, flags, button =
      glyph or state.glyph, flags == nil and state.flags or flags, button or MouseButton.LEFT
    local ok, err = pcall(function()
      self:withSuppression(function()
        if not options.panelOpen or options.panelOpen() then
          self:enter()
        end
        local tile = Profile.orientedTile(sprite, id, glyph, state.fg, state.bg, flags)
        if button == MouseButton.RIGHT then
          setNativeTile("bgTile", tile)
          state.bgGlyph, state.bgFlags, state.lastBgTile = glyph, flags, app.bgTile
          state.secondaryFg, state.secondaryBg = state.fg, state.bg
          state.secondaryError = nil
        else
          setNativeTile("fgTile", tile)
          state.glyph, state.flags, state.lastTile = glyph, flags, app.fgTile
          state.primaryEmpty = false
          state.primaryError = nil
        end
        app.fgColor, app.bgColor = U.color(state.fg), U.color(state.bg)
        state.pendingMode = (not options.panelOpen or options.panelOpen()) and 4 or nil
        options.remember(glyph)
      end)
    end)
    changed()
    if not ok then
      error(err, 0)
    end
  end

  ---Prepare both selected stamps and apply pending colors.
  function session:prepareBoth()
    local pending = state.pendingColors
    if pending and pending.source == "external" then
      state.fg, state.bg = pending.fg, pending.bg
      state.secondaryFg, state.secondaryBg = state.fg, state.bg
    end
    local bgGlyph, bgFlags = state.bgGlyph, state.bgFlags
    if not state.primaryEmpty then
      self:prepare(MouseButton.LEFT, state.glyph, state.flags)
    end
    if bgGlyph then
      self:prepare(MouseButton.RIGHT, bgGlyph, bgFlags)
    elseif state.primaryEmpty then
      self:withSuppression(function()
        app.fgColor, app.bgColor = U.color(state.fg), U.color(state.bg)
      end)
    end
    if state.pendingColors == pending then
      state.pendingColors = nil
    end
  end

  ---Select and prepare a glyph for the requested mouse button.
  ---@param button integer Native mouse button.
  ---@param key string Glyph key.
  function session:selectGlyph(button, key)
    if self:isBusy() then
      return
    end
    self:ensureActive()
    if button == MouseButton.RIGHT then
      state.bgFlags = state.flags or 0
      self:prepare(MouseButton.RIGHT, key, state.flags or 0)
    else
      state.glyph = key
      changed()
      self:prepare(MouseButton.LEFT, key, state.flags or 0)
    end
  end

  ---Check whether a stamp action applies to the current target.
  ---@param id string Stamp action identifier.
  ---@param target? integer|string Optional target: MouseButton.LEFT, MouseButton.RIGHT, "secondary", "both".
  ---@return boolean allowed Whether the action can run.
  function session:canRunAction(id, target)
    local sprite, layer = self:active()
    if not sprite or sprite ~= state.ownerSprite or layer ~= state.lastLayer then
      return false
    end
    return Stamps.canExecute(id, self:isBusy(), target)
  end

  ---Apply a stamp action to the current drawing target.
  ---@param id string Stamp action identifier.
  ---@param target? integer|string Optional mouse button or string target; right-click targets secondary stamp only, "both" targets both.
  function session:runAction(id, target)
    U.check(not self:isBusy(), "Finish the current Asemode operation first")
    self:ensureActive()
    local captured = Stamps.read(id, self:isBusy(), target)
    local pending = state.pendingColors
    local sameTarget = pending
      and pending.sprite == captured.sprite
      and pending.layer == captured.layer
    local fg = captured.primary and captured.primary.meta.foregroundRGBA or state.fg
    local bg = captured.primary and captured.primary.meta.backgroundRGBA or state.bg
    if sameTarget then
      if pending.source == "dialog" then
        fg, bg = state.fg, state.bg
      else
        fg, bg = U.colorHex(app.fgColor), U.colorHex(app.bgColor)
      end
    end
    local colors = sameTarget and { foregroundRGBA = fg, backgroundRGBA = bg } or nil
    local result = self:withSuppression(function()
      return Stamps.apply(captured, colors, target)
    end)
    self:bindSprite(result.sprite)
    state.lastLayer = result.layer
    if result.primary then
      state.glyph, state.flags, state.lastTile =
        result.primary.meta.glyphKey, result.primary.flags, result.fgTile
      state.primaryEmpty = false
    else
      state.lastTile = result.fgTile
    end
    state.bgGlyph = result.secondary and result.secondary.meta.glyphKey or nil
    state.bgFlags, state.lastBgTile =
      result.secondary and result.secondary.flags or 0, result.bgTile
    if result.secondary then
      state.secondaryFg = result.secondary.meta.foregroundRGBA
      state.secondaryBg = result.secondary.meta.backgroundRGBA
    end
    local secondaryOnly = target == "secondary" or (MouseButton and target == MouseButton.RIGHT)
    if id == "swapColors" then
      -- Stamps.apply resolves pending colors for both stamps during a swap.
      if not secondaryOnly then
        if result.primary then
          state.fg, state.bg =
            result.primary.meta.foregroundRGBA, result.primary.meta.backgroundRGBA
        end
        state.pendingColors = nil
      elseif sameTarget then
        state.fg, state.bg = fg, bg
        state.pendingColors = nil
      end
    else
      if not secondaryOnly then
        state.fg, state.bg = fg, bg
        if not sameTarget then
          state.pendingColors = nil
        end
      end
    end
    changed()
    if options.actionComplete then
      options.actionComplete()
    end
  end

  ---Capture a serializable snapshot of the active primary and secondary stamps.
  ---@return table snapshot Stamp state snapshot.
  local function stampSnapshot()
    return {
      primary = {
        glyph = state.glyph,
        fg = state.fg,
        bg = state.bg,
        flags = state.flags,
        empty = state.primaryEmpty and true or nil,
      },
      secondary = state.bgGlyph and {
        glyph = state.bgGlyph,
        fg = state.secondaryFg,
        bg = state.secondaryBg,
        flags = state.bgFlags,
      } or nil,
    }
  end

  ---Save the current valid stamp selection on the active layer.
  function session:persist()
    local sprite, layer = self:active()
    if
      not sprite
      or state.ownerSprite ~= sprite
      or state.lastLayer ~= layer
      or self:isBusy()
      or state.primaryError
      or state.secondaryError
      or state.invalidSaved
    then
      return
    end
    local snapshot = stampSnapshot()
    local encoded = StampState.encode(snapshot)
    if encoded == state.lastPersisted then
      state.deferred[layerKey(layer)] = nil
      return
    end
    self:withSuppression(function()
      StampState.write(sprite, layer, snapshot)
    end)
    state.lastPersisted = encoded
    state.deferred[layerKey(layer)] = nil
  end

  ---Restore saved or default stamp selection for a text layer.
  ---@param sprite Sprite Active document.
  ---@param layer Layer Active text layer.
  function session:restore(sprite, layer)
    local saved, problem = StampState.read(layer)
    if problem then
      print("[Asemode] " .. problem .. "; select a stamp to replace it.")
    end
    local deferred = state.deferred[layerKey(layer)]
    if deferred then
      saved = deferred.snapshot
    elseif not saved then
      local index = Profile.index(sprite, Model.meta(layer).fontProfileId)
      local primary, secondary = Profile.defaultStamps(index, true)
      primary, secondary = primary or "0", secondary or primary or "0"
      saved = {
        primary = { glyph = primary, fg = "#ffffffff", bg = "#000000ff", flags = 0 },
        secondary = { glyph = secondary, fg = "#ffffffff", bg = "#000000ff", flags = 0 },
      }
    end
    local primary, secondary = saved.primary, saved.secondary
    local id = Model.meta(layer).fontProfileId
    local fgTile, bgTile, missingPrimary, missingSecondary
    self:withSuppression(function()
      local index = Profile.index(sprite, id)
      local square = index.profile ~= nil and index.profile.cellWidth == index.profile.cellHeight

      ---Check whether the baked variant for a stamp exists in the font index.
      ---@param stamp table Stamp definition with glyph, fg, bg, and flags.
      ---@return boolean baked True if the oriented variant is registered.
      local function baked(stamp)
        local key = U.key(stamp.glyph, stamp.fg, stamp.bg, stamp.flags or 0)
        return index.variants ~= nil and index.variants[key] ~= nil
      end

      ---Find the untransformed variant of a legacy square-cell stamp.
      ---Legacy square-cell documents stored orientation in native tile flags.
      ---@param stamp table Stamp definition with glyph, fg, bg, and flags.
      ---@return integer? tile Paint tile index of the untransformed variant.
      local function legacyBase(stamp)
        if (stamp.flags or 0) == 0 or not square or not index.variants then
          return nil
        end
        return index.variants[U.key(stamp.glyph, stamp.fg, stamp.bg, 0)]
      end

      ---Check whether a stamp definition already exists in the font index.
      ---@param stamp table Stamp definition with glyph, fg, bg, and flags.
      ---@return boolean exists True if tile is registered in the font profile.
      local function exists(stamp)
        return baked(stamp) or legacyBase(stamp) ~= nil
      end

      ---Resolve the native tile value for a stamp, supporting legacy square-cell orientation.
      ---@param stamp table Stamp definition with glyph, fg, bg, and flags.
      ---@return integer tile Native tile value.
      local function resolveTile(stamp)
        if not stamp or stamp.empty then
          return 0
        end
        local flags = stamp.flags or 0
        if not baked(stamp) then
          local base = legacyBase(stamp)
          if base then
            return app.pixelColor.tile(base, flags)
          end
        end
        return Profile.orientedTile(sprite, id, stamp.glyph, stamp.fg, stamp.bg, flags)
      end
      local ready = (primary.empty or exists(primary)) and (not secondary or exists(secondary))

      ---Resolve native tiles for both primary and secondary stamps.
      local function prepare()
        fgTile = resolveTile(primary)
        bgTile = resolveTile(secondary)
      end
      if ready then
        prepare()
      else
        missingPrimary = not primary.empty and not exists(primary)
        missingSecondary = secondary and not exists(secondary) or false
        fgTile = not primary.empty and not missingPrimary and resolveTile(primary) or 0
        bgTile = secondary and not missingSecondary and resolveTile(secondary) or 0
        print("[Asemode] A saved stamp is unavailable; select it again to recreate it.")
      end
      setNativeTile("fgTile", fgTile)
      setNativeTile("bgTile", bgTile)
      app.fgColor, app.bgColor = U.color(primary.fg), U.color(primary.bg)
    end)
    state.glyph, state.fg, state.bg, state.flags =
      primary.glyph, primary.fg, primary.bg, primary.flags
    state.primaryEmpty = primary.empty or false
    state.bgGlyph, state.bgFlags =
      secondary and secondary.glyph or nil, secondary and secondary.flags or 0
    state.secondaryFg = secondary and secondary.fg or primary.fg
    state.secondaryBg = secondary and secondary.bg or primary.bg
    state.ownerSprite, state.lastLayer = sprite, layer
    state.lastTile, state.lastBgTile = fgTile, bgTile
    state.primaryError, state.secondaryError = missingPrimary, missingSecondary
    state.invalidSaved = problem ~= nil and not (deferred and deferred.replaceInvalid)
    state.historyRestore = nil
    state.lastPersisted = not deferred and StampState.encode(saved) or nil
    state.deferred[layerKey(layer)] = nil
    state.pendingColors = nil
    changed()
  end

  ---Restore the drawing session when the active target has changed.
  function session:ensureActive()
    local sprite, layer = self:target()
    if state.ownerSprite ~= sprite or state.lastLayer ~= layer then
      self:restore(sprite, layer)
    end
  end

  ---Read native stamp selections into the active session.
  function session:syncNative()
    local sprite, layer = self:active()
    if not sprite or sprite ~= state.ownerSprite or layer ~= state.lastLayer or self:isBusy() then
      return
    end
    local tile = app.fgTile
    if tile ~= state.lastTile then
      local ok, meta, flags = pcall(Profile.decode, layer, tile)
      if ok and meta then
        state.primaryError = nil
        state.invalidSaved = nil
        state.primaryEmpty = false
        state.glyph, state.flags = meta.glyphKey, flags
        if not state.pendingColors then
          state.fg, state.bg = meta.foregroundRGBA, meta.backgroundRGBA
          self:withSuppression(function()
            app.fgColor, app.bgColor = U.color(state.fg), U.color(state.bg)
          end)
        end
      elseif not ok then
        state.primaryError = true
        print("[Asemode primary tile error] " .. tostring(meta))
      else
        state.primaryError = nil
        state.invalidSaved = nil
        state.primaryEmpty = true
        state.flags = 0
      end
      state.lastTile = tile
      changed()
    end
    local bgTile = app.bgTile
    if bgTile ~= state.lastBgTile then
      local ok, meta, flags = pcall(Profile.decode, layer, bgTile)
      if not ok then
        state.secondaryError = true
        print("[Asemode secondary tile error] " .. tostring(meta))
      else
        state.secondaryError = nil
        state.invalidSaved = nil
        state.bgGlyph = meta and meta.glyphKey or nil
        state.bgFlags = flags or 0
        if meta then
          state.secondaryFg, state.secondaryBg = meta.foregroundRGBA, meta.backgroundRGBA
        end
      end
      state.lastBgTile = bgTile
      changed()
    end
  end

  ---Apply pending color changes and persist the active selection.
  function session:flush()
    local sprite, layer = self:active()
    if not sprite or state.ownerSprite ~= sprite or state.lastLayer ~= layer or self:isBusy() then
      return
    end
    self:syncNative()
    if state.pendingColors then
      U.check(
        not state.primaryError and not state.secondaryError,
        "Select valid Asemode stamps before applying pending colors"
      )
      self:prepareBoth()
      state.pendingColors = nil
    end
    self:syncNative()
    self:persist()
  end

  ---Queue stamp state persistence until site changes settle.
  ---@param key any Lookup key for the layer.
  ---@param sprite Sprite Target sprite.
  ---@param layer Layer Target layer.
  ---@param snapshot table Serialized stamp snapshot.
  local function queueDeferredStamps(key, sprite, layer, snapshot)
    state.deferred[key] = {
      sprite = sprite,
      layer = layer,
      snapshot = snapshot,
      replaceInvalid = not state.invalidSaved,
    }
  end

  ---Log a command failure and format user-facing alert message parts.
  ---@param prefix string Action failure context prefix.
  ---@param err any Error value.
  ---@return string[] message Formatted warning message lines.
  local function commandFailure(prefix, err)
    local detail = U.cleanError(err)
    if not detail:match("[%p]$") then
      detail = detail .. "."
    end
    local message = { prefix, detail }
    print("[Asemode] " .. table.concat(message, " "))
    return message
  end

  ---Persist eligible deferred selections for the active sprite.
  ---@param sprite Sprite? Sprite whose deferred changes are flushed.
  function session:flushDeferred(sprite)
    if not sprite or app.sprite ~= sprite or self:isBusy() then
      return
    end
    for key, deferred in pairs(state.deferred) do
      if deferred.sprite == sprite then
        local ok, owner = pcall(function()
          return deferred.layer.sprite
        end)
        if not ok or owner ~= sprite or not deferred.replaceInvalid then
          state.deferred[key] = nil
        else
          self:withSuppression(function()
            StampState.write(sprite, deferred.layer, deferred.snapshot)
          end)
          state.deferred[key] = nil
        end
      end
    end
  end

  ---Move change and save listeners to the requested sprite.
  ---@param sprite Sprite? Sprite to observe, or nil to detach.
  function session:bindSprite(sprite)
    if state.observedSprite == sprite then
      return
    end
    if state.observedSprite and state.observedSprite.isValid then
      for _, listener in ipairs(state.spriteListeners) do
        state.observedSprite.events:off(listener)
      end
    end
    state.spriteListeners, state.observedSprite = {}, sprite
    if sprite then
      state.spriteListeners[#state.spriteListeners + 1] = sprite.events:on("change", function()
        Profile.invalidate()
        changed()
      end)
      state.spriteListeners[#state.spriteListeners + 1] = sprite.events:on("beforesave", function()
        self:flush()
        self:flushDeferred(sprite)
      end)
    end
    state.lastTile, state.lastBgTile = nil, nil
    changed()
  end

  ---Synchronize the session when the drawing panel opens.
  ---@param first boolean First-open indicator supplied by the caller.
  function session:panelOpened(first)
    local sprite, layer = self:active()
    if sprite then
      self:bindSprite(sprite)
      if state.ownerSprite ~= sprite or state.lastLayer ~= layer then
        self:restore(sprite, layer)
      end
    end
  end

  ---Flush eligible changes and restore host drawing settings.
  function session:panelClosed()
    local busy = self:isBusy()
    if not busy then
      self:flush()
    end
    self:leaveDrawingContext()
    if not busy then
      state.pendingColors = nil
    end
  end

  ---Synchronize host state and pending selections for one timer tick.
  ---@param panelOpen boolean Whether the drawing panel is open.
  function session:tick(panelOpen)
    if self:isBusy() then
      return
    end
    local sprite, layer = self:active()
    if state.nativeDrawingContext and state.nativeDrawingContext.sprite ~= sprite then
      self:leaveDrawingContext()
    end
    self:restoreHostModes()
    if panelOpen and sprite and (not state.nativeDrawingContext or state.contextLayer ~= layer) then
      self:enter()
    end
    self:bindSprite(sprite)
    if sprite and (state.ownerSprite ~= sprite or state.lastLayer ~= layer) then
      if self:isBusy() then
        return
      end
      self:restore(sprite, layer)
    end
    if sprite then
      self:syncNative()
    end
    if state.pendingColors then
      local pending = state.pendingColors
      if pending.sprite == sprite and pending.layer == layer then
        pending.quietTicks = pending.quietTicks + 1
        if pending.quietTicks >= 2 and not (state.primaryError or state.secondaryError) then
          if pending.source == "dialog" then
            state.pendingColors = nil
          end
          self:prepareBoth()
        end
      else
        state.pendingColors = nil
      end
    end
    if sprite then
      if panelOpen and state.pendingMode and state.pendingMode > 0 then
        self:enter()
        state.pendingMode = state.pendingMode - 1
        if app.site.tilemapMode == TilemapMode.TILES then
          state.pendingMode = nil
        end
      end
      self:syncNative()
      if not state.pendingColors then
        self:persist()
        self:flushDeferred(sprite)
      end
    else
      state.ownerSprite, state.lastLayer = nil, nil
    end
  end

  ---Start host event subscriptions and background synchronization.
  function session:start()
    if state.started then
      return
    end
    state.started = true
    if app.isUIAvailable then
      state.backgroundTimer = Timer({
        interval = 0.15,
        ontick = (options.backgroundGuard or options.guard)(function()
          if options.reconcileProjects then
            options.reconcileProjects()
          end
          if not options.panelOpen() then
            self:tick(false)
          end
        end),
      })
      state.backgroundTimer:start()
    end
    state.subscriptions[#state.subscriptions + 1] = app.events:on("beforesitechange", function(ev)
      if state.suppressionDepth > 0 then
        return
      end
      if not (ev and ev.fromUndo) then
        if self:isBusy() then
          local sprite, layer = self:active()
          if sprite and state.ownerSprite == sprite and state.lastLayer == layer then
            if state.pendingColors and state.pendingColors.source == "external" then
              state.fg, state.bg = state.pendingColors.fg, state.pendingColors.bg
              state.secondaryFg, state.secondaryBg = state.fg, state.bg
            end
            queueDeferredStamps(layerKey(layer), sprite, layer, stampSnapshot())
          end
        else
          self:flush()
          self:flushDeferred(app.sprite)
        end
      end
    end)
    state.subscriptions[#state.subscriptions + 1] = app.events:on("sitechange", function()
      local sprite, layer = self:active()
      if
        state.suppressionDepth == 0
        and state.ownerSprite
        and (state.ownerSprite ~= sprite or state.lastLayer ~= layer)
      then
        local ok, key = pcall(layerKey, state.lastLayer)
        if ok and key then
          local pending = state.pendingColors
          local outgoingPending = pending
            and pending.sprite == state.ownerSprite
            and pending.layer == state.lastLayer
          if outgoingPending and pending.source == "external" then
            state.fg, state.bg = state.pendingColors.fg, state.pendingColors.bg
            state.secondaryFg, state.secondaryBg = state.fg, state.bg
          end
          local snapshot = stampSnapshot()
          if outgoingPending or StampState.encode(snapshot) ~= state.lastPersisted then
            queueDeferredStamps(key, state.ownerSprite, state.lastLayer, snapshot)
          end
        end
      end
      Profile.invalidate()
      changed()
    end)
    state.subscriptions[#state.subscriptions + 1] = app.events:on("beforecommand", function(ev)
      if not ev or state.suppressionDepth > 0 then
        return
      end
      local ok, decision = pcall(NativeOperations.classify, ev.name, ev.params, {
        sprite = app.sprite,
        layer = app.layer,
        range = ev.name == "FlattenLayers" and app.range or nil,
      })
      if not ok then
        print("[Asemode] Could not check native operation: " .. tostring(decision))
        decision = {
          action = "block",
          message = { "Asemode could not check this operation.", "Try again or reopen the sprite." },
        }
      end
      if decision.action ~= "allow" then
        ev.stopPropagation()
        if decision.action == "replace" then
          local flipping = decision.operation == "flip"
          local label = flipping and "Flip Asemode Canvas" or "Rotate Asemode Canvas"
          local success, err = pcall(function()
            U.check(not self:isBusy(), "Finish the current Asemode operation first")
            app.transaction(label, function()
              self:flush()
              self:withSuppression(function()
                if flipping then
                  Flip.apply(app.sprite, decision.orientation)
                else
                  Rotate.apply(app.sprite, decision.angle)
                end
              end)
            end)
            self:invalidateStamps()
            changed()
          end)
          if not success then
            Profile.invalidate()
            self:invalidateStamps()
            changed()
            local message = commandFailure(
              flipping and "Could not flip the Asemode canvas."
                or "Could not rotate the Asemode canvas.",
              err
            )
            if app.isUIAvailable then
              showNativeWarning(message)
            end
          end
        else
          showNativeWarning(decision.message)
        end
        -- Nested commands can reset Aseprite's cancellation flag.
        ev.stopPropagation()
        return
      end
      local save = ev.name == "SaveFile" or ev.name == "SaveFileAs" or ev.name == "SaveFileCopyAs"
      local history = ev.name == "Undo" or ev.name == "Redo"
      if save or history or ev.name == "CloseFile" then
        -- Immediately after Undo, restoring and persisting a stamp can create
        -- a new history entry and discard the pending Redo operation.
        if
          ev.name == "Redo"
          and state.historyRestore
          and state.historyRestore.sprite == app.sprite
        then
          return
        end
        local sprite, layer = self:active()
        local document = app.sprite
        local hasDeferred = false
        for _, deferred in pairs(state.deferred) do
          if deferred.sprite == document then
            hasDeferred = true
            break
          end
        end
        if not document or (not sprite and not hasDeferred) then
          return
        end
        local ok, problem = pcall(function()
          U.check(not self:isBusy(), "Finish the current Asemode operation first")
          if sprite and (state.ownerSprite ~= sprite or state.lastLayer ~= layer) then
            self:restore(sprite, layer)
          end
          self:flush()
          self:flushDeferred(document)
        end)
        if not ok then
          if history then
            state.canceledHistory = ev.name
          end
          ev.stopPropagation()
          local message = commandFailure("Could not preserve Asemode stamp state.", problem)
          if app.isUIAvailable then
            app.alert({ title = "Asemode", text = message })
          end
        end
      end
    end)
    state.subscriptions[#state.subscriptions + 1] = app.events:on("aftercommand", function(ev)
      if ev and (ev.name == "Undo" or ev.name == "Redo") then
        if state.canceledHistory == ev.name then
          state.canceledHistory = nil
          return
        end
        local sprite, layer = self:active()
        if layer then
          state.deferred[layerKey(layer)] = nil
        end
        state.ownerSprite, state.lastLayer = nil, nil
        state.historyRestore = sprite and { sprite = sprite, layer = layer } or nil
        state.pendingColors = nil
        changed()
      end
    end)
    for _, name in ipairs({ "fgcolorchange", "bgcolorchange" }) do
      state.subscriptions[#state.subscriptions + 1] = app.events:on(
        name,
        options.guard(function()
          if state.suppressionDepth > 0 then
            return
          end
          local sprite = self:active()
          if sprite then
            self:queueColorCommit("external", name)
          end
        end)
      )
    end
  end

  ---Flush state and remove timers and event subscriptions.
  function session:close()
    self:panelClosed()
    if state.backgroundTimer then
      state.backgroundTimer:stop()
      state.backgroundTimer = nil
    end
    for _, code in ipairs(state.subscriptions) do
      app.events:off(code)
    end
    state.subscriptions = {}
    state.deferred = {}
    state.started = false
    self:bindSprite(nil)
  end

  return session
end

return M
