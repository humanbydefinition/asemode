local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Library = require("src.fonts.library")
local About = require("src.ui.about")
local Stamps = require("src.actions.stamps")
local PortableUI = require("src.ui.portable")
local FontWorkflow = require("src.ui.font_workflow")
local DocumentWorkflow = require("src.ui.document_workflow")
local Controls = require("src.ui.controls")
local TaskRunner = require("src.ui.task_runner")
local Drawing = require("src.session.drawing")
local Projects = require("src.session.projects")
local GlyphBrowser = require("src.ui.glyph_browser")
local Settings = require("src.core.settings")
local Theme = require("src.ui.theme")
local SettingsDialog = require("src.ui.settings_dialog")
local PanelGeometry = require("src.ui.panel_geometry")
local Guards = require("src.ui.guards")
local DialogRegistry = require("src.ui.dialog_registry")
local M = {}

local GRID_CELL_DEFAULT = Settings.GRID_CELL_DEFAULT
local GRID_DEFAULT_ROWS = 6
local ACTION_ICON_SIZE = 16
local ACTION_ROW_HEIGHT = 24

---Truncate text with an ellipsis to fit within a given horizontal pixel budget.
---@param gc GraphicsContext Canvas graphics context for text measurement.
---@param text string Original text string.
---@param maxWidth number Maximum width in pixels.
---@return string fitted Fitted text with ellipsis or empty string.
local function fitText(gc, text, maxWidth)
  if gc:measureText(text).width <= maxWidth then
    return text
  end
  local suffix = "..."
  if gc:measureText(suffix).width > maxWidth then
    return ""
  end
  local length = utf8.len(text) or #text
  local low, high = 0, length
  while low < high do
    local middle = (low + high + 1) // 2
    local nextByte = utf8.offset(text, middle + 1)
    local prefix = nextByte and text:sub(1, nextByte - 1) or text
    if gc:measureText(prefix .. suffix).width <= maxWidth then
      low = middle
    else
      high = middle - 1
    end
  end
  local nextByte = utf8.offset(text, low + 1)
  return (nextByte and text:sub(1, nextByte - 1) or text) .. suffix
end

---Create the Asemode UI controller and its drawing, font, and task services.
---@param plugin table Aseprite plugin with persistent preferences.
---@param options table? Optional injected services.
---@return table controller UI controller.
function M.new(plugin, options)
  options = options or {}
  local library = Library.new(plugin.preferences)
  local self = {
    plugin = plugin,
    library = library,
    openDialogs = {},
    dialogs = {},
    dirty = true,
    panelBounds = PanelGeometry.fromPreferences(plugin.preferences.panelBounds),
  }
  self.projects = Projects.new()

  self.tasks = options.tasks
    or TaskRunner.new({
      uiAvailable = function()
        return app.isUIAvailable
      end,
      dialog = function(title, options)
        return self:dialog(title, options)
      end,
      timer = function(options)
        return Timer(options)
      end,
      guard = function(fn)
        return self:guard(fn)
      end,
    })
  self.drawing = Drawing.new({
    blocksDrawing = function()
      return self.tasks:blocksDrawing()
    end,
    panelOpen = function()
      return self.panel ~= nil
    end,
    reconcileProjects = function()
      self:reconcileProjects()
    end,
    guard = function(fn)
      return self:guard(fn)
    end,
    backgroundGuard = function(fn)
      return self:backgroundGuard(fn)
    end,
    changed = function()
      self.dirty = true
    end,
    actionComplete = function()
      if self.panel then
        self:refresh()
      end
    end,
    remember = function(key)
      local recent = self.plugin.preferences.recent or {}
      local result = { key }
      for _, old in ipairs(recent) do
        if old ~= key and #result < 64 then
          result[#result + 1] = old
        end
      end
      self.plugin.preferences.recent = result
    end,
  })

  self.browser = GlyphBrowser.new({
    gridCellSize = plugin.preferences.glyphGridSize or GRID_CELL_DEFAULT,
    changed = function()
      self.dirty = true
    end,
    select = function(key, button)
      self.drawing:selectGlyph(button, key)
    end,
    tooltip = function(message)
      app.tip(message)
    end,
  })

  ---Set the glyph grid size and persist it in plugin preferences.
  ---@param value number|string Requested grid cell size.
  ---@return integer size Applied grid cell size.
  function self:setGlyphGridSize(value)
    local size = self.browser:setGridCellSize(tonumber(value))
    self.plugin.preferences.glyphGridSize = size
    self.dirty = true
    if self.panel then
      self.panel:repaint()
    end
    return size
  end

  ---Open the Asemode settings dialog.
  function self:settings()
    return SettingsDialog.open(self)
  end

  ---Open the host keyboard shortcut settings for Asemode.
  function self:keyboardShortcuts()
    app.command.KeyboardShortcuts({ search = "Asemode" })
  end

  ---Wrap a callback with error reporting and UI invalidation.
  ---@param run function Callback to guard.
  ---@return function guarded Callback that reports errors through the host.
  function self:guard(run)
    return function(...)
      if self.errorDialogOpen then
        return
      end
      local args = { ... }
      local ok, err = xpcall(function()
        return run(table.unpack(args))
      end, debug.traceback)
      if not ok then
        local trace = tostring(err)
        if app.isUIAvailable then
          print("[Asemode error]\n" .. trace)
          local details, count = {}, 0
          for line in (trace .. "\n"):gmatch("(.-)\n") do
            if line ~= "" then
              count = count + 1
              if count <= 10 then
                details[#details + 1] = line
              end
            end
          end
          if count > 10 then
            details[#details + 1] = "Trace truncated; see the Aseprite console for the full error."
          end
          details[#details + 1] = "Your existing artwork was preserved."
          self.errorDialogOpen = true
          local shown, alertError = pcall(app.alert, { title = "Asemode", text = details })
          self.errorDialogOpen = false
          if not shown then
            print("[Asemode alert error] " .. tostring(alertError))
          end
        else
          error(err, 0)
        end
      end
      self.dirty = true
    end
  end

  Guards.install(self)

  DialogRegistry.install(self)

  ---Request default panel positioning when no saved bounds exist.
  function self:positionPanelAtLeftSidebar()
    if self.panel then
      return
    end
    if not self.panelBounds then
      self.positionPanelLeftOnOpen = true
    end
  end

  ---Validate and persist panel bounds.
  ---@param bounds Rectangle|table Candidate panel bounds.
  function self:savePanelBounds(bounds)
    local saved = PanelGeometry.fromPreferences(bounds)
    if not saved then
      return
    end
    self.panelBounds = saved
    self.plugin.preferences.panelBounds = {
      x = saved.x,
      y = saved.y,
      width = saved.width,
      height = saved.height,
    }
  end

  ---Open the Asemode About dialog.
  function self:about()
    About.open(self)
  end

  ---Paint two labels, truncating them to fit the available width.
  ---@param ev table Canvas paint event.
  ---@param left string Left-aligned label.
  ---@param right string Right-aligned label.
  function self:paintAlignedLabels(ev, left, right)
    local gc = ev.context
    local gap = left ~= "" and right ~= "" and 8 or 0
    local available = math.max(0, gc.width - gap)
    local leftWidth, rightWidth = gc:measureText(left).width, gc:measureText(right).width
    if leftWidth + rightWidth > available then
      local half = available // 2
      local leftLimit = math.min(leftWidth, math.max(half, available - rightWidth))
      left = fitText(gc, left, leftLimit)
      right = fitText(gc, right, available - gc:measureText(left).width)
    end
    local rightSize = gc:measureText(right)
    local lineSize = gc:measureText(left .. " " .. right)
    local y = math.max(0, (gc.height - lineSize.height) // 2)
    gc.color = gc.theme.color.window_face
    gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
    gc.color = gc.theme.color.text
    gc:fillText(left, 0, y)
    if right ~= "" then
      gc:fillText(right, gc.width - rightSize.width, y)
    end
  end

  ---Paint the selected glyph and visible range labels.
  ---@param ev table Canvas paint event.
  function self:paintInfo(ev)
    local snapshot = self.drawing:snapshot()
    local name, range = self.browser:information(snapshot)
    if snapshot.missingPrimary then
      name, range = "Select a primary stamp", ""
    elseif snapshot.missingSecondary then
      name, range = "Right-click a glyph for secondary", ""
    elseif snapshot.invalidSaved then
      name, range = "Select a glyph to restore stamps", ""
    end
    self:paintAlignedLabels(ev, name, range)
  end

  ---Paint the active layer and font labels.
  ---@param ev table Canvas paint event.
  function self:paintDocumentInfo(ev)
    self:paintAlignedLabels(
      ev,
      self.documentLayerName or "No active text layer",
      self.documentFontName or ""
    )
  end

  local iconActions = Stamps.icons
  -- Each four hexadecimal digits encode one 16-pixel row, left to right.
  local pixelIcons = {
    "00000010000800047ffe0004000800100800100020007ffe2000100008000000",
    "00000000000001000100092011103d7811100920010001000000000000000000",
    "00000000010003800540010000001ff000000100054003800100000000000000",
    "0000000001e006180804100210027c023802100200020004061801e000000000",
    "0000000007801860201040084008403e401c4008400020001860078000000000",
  }
  ---Calculate the horizontal bounds for a stamp action icon button.
  ---@param index integer 1-based action icon index.
  ---@param width number Total available container width.
  ---@return integer left Left x offset.
  ---@return integer width Width in pixels.
  local function actionBounds(index, width)
    local gap, count = 4, #iconActions
    local available = width - gap * (count - 1)
    local left = (index - 1) * available // count + (index - 1) * gap
    local right = index * available // count + (index - 1) * gap
    return left, right - left
  end

  ---Check whether a given stamp action is currently executable.
  ---@param index integer 1-based action icon index.
  ---@return boolean enabled True if action can run.
  local function actionEnabled(index)
    return self.drawing:canRunAction(iconActions[index].id)
  end

  ---Resolve the action index under the pointer coordinates.
  ---@param x number Horizontal coordinate.
  ---@param y number Vertical coordinate.
  ---@param width number Total canvas width.
  ---@param height number Total canvas height.
  ---@return integer? index 1-based action index if hit and enabled.
  local function actionAt(x, y, width, height)
    if y < 0 or y >= height then
      return nil
    end
    for i = 1, #iconActions do
      local left, itemWidth = actionBounds(i, width)
      if x >= left and x < left + itemWidth then
        return actionEnabled(i) and i or nil
      end
    end
  end

  ---Paint the stamp action icons for the current state.
  ---@param ev table Canvas paint event.
  function self:paintActionIcons(ev)
    local gc = ev.context
    gc.antialias = false
    self.actionWidth, self.actionHeight = gc.width, gc.height
    for i = 1, #iconActions do
      local x, itemWidth = actionBounds(i, gc.width)
      local enabled = actionEnabled(i)
      local state = enabled and (self.actionDown == i and self.actionHot == i) and "button_selected"
        or (enabled and self.actionHot == i and "button_hot" or "button_normal")
      gc:drawThemeRect(state, Rectangle(x, 0, itemWidth, gc.height))
      gc.color = Theme.actionColor(gc.theme.color, state, enabled)
      local left, top = x + (itemWidth - ACTION_ICON_SIZE) // 2, (gc.height - ACTION_ICON_SIZE) // 2
      for row = 0, 15 do
        local bits = tonumber(pixelIcons[i]:sub(row * 4 + 1, row * 4 + 4), 16)
        for column = 0, 15 do
          if bits & (1 << (15 - column)) ~= 0 then
            gc:fillRect(Rectangle(left + column, top + row, 1, 1))
          end
        end
      end
    end
  end

  ---Refresh panel controls and repaint the active drawing state.
  function self:refresh()
    if not self.panel then
      return
    end
    local sprite, layer = self.drawing:active()
    local replaceEnabled = sprite ~= nil
    self.replaceSelectionEnabled = replaceEnabled
    self.copySelectionEnabled = self.document:canCopyCells()
    self.pasteSelectionEnabled = replaceEnabled and self.document:canPasteCells() or false
    local index = sprite and Profile.index(sprite, Model.meta(layer).fontProfileId) or nil
    self.browser:setProfile(index)
    self.browser:setQuery(self.panel.data.search or "", self.panel.data.group or "All characters")
    self.documentLayerName = sprite and layer.name or "Select an Asemode layer"
    if not sprite and Model.markedLayer(app.sprite, app.layer) then
      self.documentLayerName = "Asemode layer unavailable"
      if
        Model.meta(app.sprite).schemaVersion ~= Model.schemaVersion
        or Model.meta(app.layer).schemaVersion ~= Model.schemaVersion
      then
        self.documentFontName = "Unsupported project version"
      else
        self.documentFontName = "Check project and font data"
      end
    end
    if sprite then
      local geometry = Model.geometry(sprite)
      self.documentFontName = string.format(
        "%s · %d×%d cells",
        self.browser:profileName(),
        geometry.cellWidth,
        geometry.cellHeight
      )
      if not pcall(Model.editable, sprite, layer) then
        self.documentFontName = "Unlock and show the layer"
      end
    elseif not Model.markedLayer(app.sprite, app.layer) then
      self.documentFontName = ""
    end
    self.panel:modify({ id = "replaceSelection", enabled = replaceEnabled })
    self.panel:modify({ id = "copySelection", enabled = self.copySelectionEnabled })
    self.panel:modify({ id = "pasteSelection", enabled = self.pasteSelectionEnabled })
    local options, selected = { "All characters" }, self.panel.data.group or "All characters"
    local found = selected == "All characters"
    for _, group in ipairs(self.browser:groups()) do
      options[#options + 1] = group
      if group == selected then
        found = true
      end
    end
    if not found then
      selected = "All characters"
    end
    local optionKey = table.concat(options, "\0")
    local optionsChanged = optionKey ~= self.groupOptionsKey
    if optionsChanged or self.panel.data.group ~= selected then
      self.groupOptionsKey = optionKey
      self.panel:modify({ id = "group", options = options, option = selected })
    end
    if not self.panelBounds and (self.fitDefaultPanelWidth or optionsChanged) then
      local bounds, size = self.panel.bounds, self.panel.sizeHint
      if size.width > bounds.width then
        self.panel.bounds = Rectangle(bounds.x, bounds.y, size.width, bounds.height)
      end
      self.fitDefaultPanelWidth = false
    end
    self.panel:repaint()
    self.dirty = false
  end

  ---Open or close the main drawing panel.
  function self:togglePanel()
    if self.panel then
      self.panel:close()
    else
      self:open()
    end
  end

  ---Open the drawing panel or show the existing one.
  function self:open()
    if self.panel then
      self.panel:show({ wait = false })
      return
    end
    local d
    -- Label updates must retain the size chosen by the user.
    d = self:dialog("Asemode", {
      resizeable = true,
      autofit = 0,
      onclose = function()
        if not self.closing then
          self.projects:check(app.sprite, app.sprites, true)
          self.projects:dismiss(app.sprite)
        end
        self:savePanelBounds(d.bounds)
        self.drawing:panelClosed()
        self.panel = nil
        self.browser:clear()
        if self.timer then
          self.timer:stop()
          self.timer = nil
        end
      end,
    })
    self.panel = d
    self.fitDefaultPanelWidth = not self.panelBounds
    local sprite, layer = self.drawing:active()
    if sprite and not self.initialPanelReady then
      self.drawing:panelOpened(true)
      self.initialPanelReady = true
    else
      self.drawing:panelOpened(false)
    end
    d:canvas({
      id = "document",
      width = self.browser:minimumWidth(),
      height = 16,
      hexpand = true,
      vexpand = false,
      onpaint = self:guard(function(ev)
        self:paintDocumentInfo(ev)
      end),
    })
      :newrow()
      :entry({
        id = "search",
        text = "",
        placeholder = "Character name",
        onchange = function()
          self.browser:setScrollRow(0)
          self.dirty = true
        end,
      })
      :combobox({
        id = "group",
        options = { "All characters" },
        option = "All characters",
        onchange = function()
          self.browser:setScrollRow(0)
          self.dirty = true
        end,
      })
      :canvas({
        id = "glyphs",
        width = self.browser:minimumWidth(),
        height = self.browser:minimumHeight(),
        hexpand = true,
        vexpand = true,
        onpaint = self:guard(function(ev)
          self.browser:paint(ev, self.drawing:snapshot())
        end),
        onmousedown = self:guard(function(ev)
          self.browser:handleMouseDown(ev)
        end),
        onmousemove = function(ev)
          self.browser:handleMouseMove(ev)
        end,
        onmouseup = function(ev)
          self.browser:handleMouseUp(ev)
        end,
        onwheel = function(ev)
          self.browser:handleWheel(ev)
        end,
        onkeydown = self:guard(function(ev)
          self.browser:handleKeyDown(ev)
        end),
      })
      :newrow()
      :canvas({
        id = "glyphInfo",
        width = self.browser:minimumWidth(),
        height = 16,
        hexpand = true,
        vexpand = false,
        onpaint = self:guard(function(ev)
          self:paintInfo(ev)
        end),
      })
      :newrow()
      :canvas({
        id = "actions",
        width = self.browser:minimumWidth(),
        height = ACTION_ROW_HEIGHT,
        hexpand = true,
        vexpand = false,
        onpaint = self:guard(function(ev)
          self:paintActionIcons(ev)
        end),
        onmousemove = function(ev)
          local hot = actionAt(ev.x, ev.y, self.actionWidth or 320, self.actionHeight or 28)
          if hot ~= self.actionHot then
            self.actionHot = hot
            if hot then
              app.tip(iconActions[hot].title)
            end
            if self.panel then
              self.panel:repaint()
            end
          end
        end,
        onmousedown = function(ev)
          if ev.button == MouseButton.LEFT or ev.button == MouseButton.RIGHT then
            self.actionButton = ev.button
            self.actionDown = actionAt(ev.x, ev.y, self.actionWidth or 320, self.actionHeight or 28)
            if self.panel then
              self.panel:repaint()
            end
          end
        end,
        onmouseup = function(ev)
          local button = self.actionButton
          local index = (ev.button == button)
              and actionAt(ev.x, ev.y, self.actionWidth or 320, self.actionHeight or 28)
            or nil
          local pressed = self.actionDown
          self.actionDown, self.actionHot, self.actionButton = nil, index, nil
          if self.panel then
            self.panel:repaint()
          end
          if index and index == pressed then
            self:guard(function()
              self.drawing:runAction(iconActions[index].id, button)
            end)()
          end
        end,
      })
      :newrow()
      :separator({ text = "Selection" })
      :newrow()
      :button({
        id = "replaceSelection",
        text = "Replace..",
        enabled = sprite ~= nil,
        onclick = self:guard(function()
          self.document:replaceSelection()
        end),
      })
      :button({
        id = "copySelection",
        text = "Copy",
        enabled = false,
        onclick = self:guard(function()
          self.document:copyCells()
        end),
      })
      :button({
        id = "pasteSelection",
        text = "Paste",
        enabled = false,
        onclick = self:guard(function()
          self.document:pasteCells()
        end),
      })
      :show({
        wait = false,
        autoscrollbars = true,
        bounds = PanelGeometry.keepOnscreen(self.panelBounds),
      })
    if self.positionPanelLeftOnOpen then
      d.bounds = PanelGeometry.atLeftSidebar(d.bounds)
      self.positionPanelLeftOnOpen = nil
    end
    local initialGrid = self.browser:geometry()
    if not self.panelBounds and initialGrid then
      local bounds, grid = d.bounds, initialGrid
      d.bounds = Rectangle(
        bounds.x,
        bounds.y,
        bounds.width + math.max(0, self.browser:defaultWidth() - grid.canvasWidth) * app.uiScale,
        bounds.height + math.max(0, GRID_DEFAULT_ROWS - grid.rows) * GRID_CELL_DEFAULT * app.uiScale
      )
    end
    self.timer = Timer({
      interval = 0.15,
      ontick = function()
        if self.errorDialogOpen then
          return
        end
        local ok, err = pcall(function()
          self:tick()
        end)
        if not ok and self.panel then
          self.browser:clear()
          self.panel:repaint()
          if self.panelError ~= tostring(err) then
            print("[Asemode panel error] " .. tostring(err))
            self.panelError = tostring(err)
          end
        elseif ok then
          self.panelError = nil
        end
      end,
    })
    self.timer:start()
    self:refresh()
  end

  ---Synchronize the drawing session and refresh dirty panel state.
  function self:tick()
    self:reconcileProjects()
    if self.document and self.document.tick then
      self.document:tick()
    end
    local sprite = self.drawing:active()
    local replaceEnabled = sprite ~= nil
    local copyEnabled = self.document:canCopyCells()
    local pasteEnabled = replaceEnabled and self.document:canPasteCells() or false
    if
      replaceEnabled ~= self.replaceSelectionEnabled
      or copyEnabled ~= self.copySelectionEnabled
      or pasteEnabled ~= self.pasteSelectionEnabled
    then
      self.dirty = true
    end
    self.drawing:tick(self.panel ~= nil)
    if self.dirty then
      self:refresh()
    end
  end

  ---Open the panel once for an eligible project after a site change.
  function self:reconcileProjects()
    if app.isUIAvailable and not self.tasks:blocksDrawing() then
      if self.projects:check(app.sprite, app.sprites, self.panel ~= nil) then
        self:open()
      end
    end
  end

  ---Start drawing-session event handling.
  function self:start()
    self.drawing:start()
  end

  ---Cancel tasks, stop listeners and timers, and close tracked dialogs.
  function self:close()
    self.closing = true
    self.projects:close()
    self.tasks:close()
    self.drawing:close()
    if self.themeTimer then
      self.themeTimer:stop()
      self.themeTimer = nil
    end
    if self.timer then
      self.timer:stop()
      self.timer = nil
    end
    if self.panel then
      pcall(function()
        self:savePanelBounds(self.panel.bounds)
      end)
    end
    local dialogs = self.dialogs
    self.dialogs = {}
    for _, d in ipairs(dialogs) do
      pcall(function()
        d:close()
      end)
    end
    self.panel = nil
    Profile.invalidate()
  end

  local controls = Controls.new()

  ---Forward dialog creation to controller instance.
  ---@param ... any Arguments passed to self:dialog.
  ---@return Dialog dialog Created dialog instance.
  local function dialog(...)
    return self:dialog(...)
  end

  ---Forward callback guarding to controller instance.
  ---@param fn function Callback to guard.
  ---@return function guarded Guarded callback.
  local function guard(fn)
    return self:guard(fn)
  end

  ---Mark controller state dirty to trigger UI refresh.
  local function invalidate()
    self.dirty = true
  end

  ---Open main drawing panel.
  local function openPanel()
    self:open()
  end

  ---Position panel at left sidebar if bounds are unset.
  local function positionPanel()
    self:positionPanelAtLeftSidebar()
  end

  ---Focus an existing singleton dialog.
  ---@param key string Dialog key.
  ---@return boolean focused True if dialog was found and focused.
  local function focusDialog(key)
    return self:focusDialog(key)
  end
  self.font = FontWorkflow.new({
    library = library,
    preferences = plugin.preferences,
    tasks = self.tasks,
    drawing = self.drawing,
    controls = controls,
    dialog = dialog,
    focusDialog = focusDialog,
    guard = guard,
    invalidate = invalidate,
    openPanel = openPanel,
    onDialogClose = function(d, callback)
      local callbacks = self.openDialogs[d]
      if callbacks then
        callbacks[#callbacks + 1] = callback
      end
    end,
    isDialogOpen = function(d)
      return self.openDialogs[d] ~= nil
    end,
  })
  self.portable = PortableUI.new({
    library = library,
    tasks = self.tasks,
    drawing = self.drawing,
    controls = controls,
    font = self.font,
    dialog = dialog,
    focusDialog = focusDialog,
    guard = guard,
    openPanel = openPanel,
    positionPanel = positionPanel,
  })
  self.document = DocumentWorkflow.new({
    preferences = plugin.preferences,
    library = library,
    drawing = self.drawing,
    controls = controls,
    font = self.font,
    portable = self.portable,
    dialog = dialog,
    focusDialog = focusDialog,
    timer = function(options)
      return Timer(options)
    end,
    guard = guard,
    invalidate = invalidate,
    openPanel = openPanel,
    positionPanel = positionPanel,
  })
  return self
end

return M
