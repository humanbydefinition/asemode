-- Host automation harness for Aseprite UI screenshot capture.
-- Intercepts Dialog, Timer, Task.new, and app.alert, tracks open windows as a stack,
-- introspects live dialog/tab/loading/alert titles from src/ui/, and validates against catalog.json.
local U = require("src.core.util")
local Task = require("src.core.task")

local M = {}

local function splitCsv(value)
  local list = {}
  if type(value) ~= "string" or value == "" then
    return list
  end
  for item in value:gmatch("([^,]+)") do
    local trimmed = item:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      list[#list + 1] = trimmed
    end
  end
  return list
end

local function addWrappedAlertLines(d, line)
  local chars, current = U.characters(tostring(line)), {}
  if #chars == 0 then
    d:label({ text = "" }):newrow()
    return
  end
  for _, char in ipairs(chars) do
    current[#current + 1] = char
    if #current == 88 then
      d:label({ text = table.concat(current) }):newrow()
      current = {}
    end
  end
  if #current > 0 then
    d:label({ text = table.concat(current) }):newrow()
  end
end

function M.new(options)
  local root = assert(options.root, "Missing root path")
  local output = assert(options.output, "Missing output path")
  local catalogPath = root .. "/scripts/screenshots/catalog.json"
  local catalogData = assert(
    U.decode(assert(U.read(catalogPath, 262144), "Cannot read catalog.json")),
    "Invalid catalog.json"
  )

  local catalogById = {}
  local suitesOrder = {}
  local seenSuites = {}
  for _, item in ipairs(catalogData.screenshots or {}) do
    catalogById[item.id] = item
    if not seenSuites[item.suite] then
      seenSuites[item.suite] = true
      suitesOrder[#suitesOrder + 1] = item.suite
    end
  end

  local requestedSuites = splitCsv(options.suites)
  if #requestedSuites == 0 then
    requestedSuites = suitesOrder
  end
  local activeSuiteSet = {}
  for _, s in ipairs(requestedSuites) do
    activeSuiteSet[s] = true
  end

  local requestedOnly = splitCsv(options.only)
  local onlySet = nil
  if #requestedOnly > 0 then
    onlySet = {}
    for _, id in ipairs(requestedOnly) do
      assert(catalogById[id], "Unknown screenshot id in filter: " .. tostring(id))
      onlySet[id] = true
    end
  end

  local harness = {
    root = root,
    output = output,
    catalog = catalogData,
    catalogById = catalogById,
    requestedSuites = requestedSuites,
    activeSuiteSet = activeSuiteSet,
    onlySet = onlySet,
    captured = {},
    resolvedTitles = {},
    openStack = {},
    lastShownSeq = 0,
    pendingTab = nil,
    loadingPauseRemaining = 0,
    activeLoadingDialog = nil,
    loadingReady = false,
    heldLoadingTimer = nil,
    pendingAlertId = nil,
    pendingAlertReturn = 1,
    beforecommandListeners = {},
    customAlert = nil,
    customApiVersion = nil,
  }

  local nativeDialog = Dialog
  local nativeTimer = Timer
  local nativeApp = app
  local nativeEvents = nativeApp.events
  local nativeTaskNew = Task.new

  function harness:recordProgress(step)
    local f = io.open(self.output .. "/progress", "w")
    if f then
      f:write(tostring(step))
      f:close()
    end
  end

  function harness:wait(ticks)
    for _ = 1, (ticks or 1) do
      coroutine.yield()
    end
  end

  function harness:deriveDialogTitle(id, proxy)
    local spec = assert(self.catalogById[id], "Unknown screenshot ID: " .. tostring(id))
    local header = assert(proxy._title, "Dialog is missing a title for: " .. tostring(id))
    local tabText = proxy.activeTabText
    if spec.variant then
      if spec.includeTab and tabText then
        return string.format("%s: %s tab (%s)", header, tabText, spec.variant)
      end
      return string.format("%s: %s", header, spec.variant)
    end
    if tabText then
      return string.format("%s: %s tab", header, tabText)
    end
    return header
  end

  function harness:deriveLoadingTitle(id, proxy)
    assert(self.catalogById[id], "Unknown loading screenshot ID: " .. tostring(id))
    local header = assert(proxy._title, "Loading dialog is missing a title for: " .. tostring(id))
    return string.format("Loading: %s", header)
  end

  function harness:deriveAlertTitle(id, alertTitle)
    local spec = assert(self.catalogById[id], "Unknown alert screenshot ID: " .. tostring(id))
    local descriptor = spec.variant or alertTitle
    return string.format(
      "Alert: %s",
      assert(descriptor, "Missing alert title for: " .. tostring(id))
    )
  end

  function harness:shouldWriteCapture(id, derivedTitle)
    local spec = assert(
      self.catalogById[id],
      "Screenshot ID '" .. tostring(id) .. "' is not registered in scripts/screenshots/catalog.json"
    )
    assert(
      not self.captured[id],
      "Screenshot ID '" .. tostring(id) .. "' was captured more than once in the same run"
    )
    self.captured[id] = spec
    self.resolvedTitles[id] = assert(derivedTitle, "Missing derived title for: " .. tostring(id))
    if self.onlySet and not self.onlySet[id] then
      return false
    end
    return true
  end

  function harness:captureBounds(bounds, id, derivedTitle)
    self:recordProgress("capture:" .. id)
    if not self:shouldWriteCapture(id, derivedTitle) then
      self:wait(1)
      return
    end
    local previous = app.sprite
    app.command.Screenshot({})
    local shot = assert(app.sprite, "Screenshot did not create an image")
    local image = shot.cels[1].image
    assert(
      bounds.x >= 0
        and bounds.y >= 0
        and bounds.x + bounds.width <= image.width
        and bounds.y + bounds.height <= image.height,
      "Dialog is outside the visible screen: " .. tostring(derivedTitle or id)
    )
    local cropped = Image(bounds.width, bounds.height, ColorMode.RGB)
    cropped:drawImage(image, Point(-bounds.x, -bounds.y))
    cropped:saveAs(self.output .. "/" .. id .. ".png")
    shot:close()
    app.sprite = previous
    self:wait(1)
  end

  function harness:emitBeforeCommand(name, params)
    for _, listener in ipairs(self.beforecommandListeners) do
      listener({
        name = name,
        params = params or {},
        stopPropagation = function() end,
      })
    end
  end

  function harness:expectAlert(id, returnValue)
    assert(self.catalogById[id], "Unknown alert ID in catalog.json: " .. tostring(id))
    self:recordProgress("expectAlert:" .. id)
    self.pendingAlertId = id
    self.pendingAlertReturn = returnValue or 1
  end

  function harness:captureAlert(id, fn, returnValue)
    self:expectAlert(id, returnValue)
    fn()
    assert(not self.pendingAlertId, "Expected app.alert to be triggered for: " .. tostring(id))
  end

  function harness:withApiVersion(version, fn)
    self.customApiVersion = version
    local ok, err = pcall(fn)
    self.customApiVersion = nil
    if not ok then
      error(err, 0)
    end
  end

  function harness:alertsForSuite(suiteName)
    local items = {}
    for _, entry in ipairs(self.catalog.screenshots) do
      if entry.suite == suiteName and entry.kind == "alert" and entry.command then
        items[#items + 1] = entry
      end
    end
    return items
  end

  function harness:captureLoading(id)
    assert(self.catalogById[id], "Unknown loading screenshot ID in catalog.json: " .. tostring(id))
    self:recordProgress("captureLoading:" .. id)
    for _ = 1, 200 do
      if self.loadingReady and self.activeLoadingDialog then
        break
      end
      self:wait(1)
    end
    assert(
      self.loadingReady and self.activeLoadingDialog,
      "Timed out waiting for loading dialog: " .. tostring(id)
    )
    local loadingDlg = self.activeLoadingDialog
    local derivedTitle = self:deriveLoadingTitle(id, loadingDlg)
    self:wait(2)
    self:captureBounds(loadingDlg.bounds, id, derivedTitle)
    self.loadingReady = false
    self.activeLoadingDialog = nil
    local held = self.heldLoadingTimer
    self.heldLoadingTimer = nil
    if held then
      held:start()
    end
  end

  local function wrapDialogHandle(proxy)
    local handle = { dialog = proxy }

    function handle:capture(id)
      harness:wait(2)
      local derivedTitle = harness:deriveDialogTitle(id, self.dialog)
      harness:captureBounds(self.dialog.bounds, id, derivedTitle)
      return self
    end

    function handle:set(fieldOrTable, value)
      if type(fieldOrTable) == "table" then
        for k, v in pairs(fieldOrTable) do
          self:set(k, v)
        end
        return self
      end
      local id = assert(fieldOrTable, "Widget id is required")
      local kind = self.dialog.widgetKinds[id] or "text"
      if kind == "file" then
        self.dialog:modify({ id = id, filename = tostring(value) })
      elseif kind == "combobox" then
        self.dialog:modify({ id = id, option = tostring(value) })
      elseif kind == "selected" then
        self.dialog:modify({ id = id, selected = not not value })
      else
        self.dialog:modify({ id = id, text = tostring(value) })
      end
      if self.dialog.changes[id] then
        self.dialog.changes[id]()
      end
      return self
    end

    function handle:click(buttonId, opts)
      local callback = assert(
        self.dialog.buttons[buttonId],
        string.format(
          "Missing button id '%s' in dialog '%s'",
          tostring(buttonId),
          tostring(self.dialog._title)
        )
      )
      local loadingList = {}
      if opts and opts.loading then
        loadingList = type(opts.loading) == "table" and opts.loading or { opts.loading }
        harness.loadingPauseRemaining = #loadingList
      end
      if opts and opts.tab then
        harness.pendingTab = opts.tab
      end
      if opts and opts.alert then
        if type(opts.alert) == "table" then
          harness:expectAlert(opts.alert.id, opts.alert.result or opts.alert.returnValue)
        else
          harness:expectAlert(opts.alert, opts.alertResult or 1)
        end
      end
      callback()
      if opts and opts.alert then
        assert(
          not harness.pendingAlertId,
          "Expected alert during button click: " .. tostring(buttonId)
        )
      end
      for _, loadingId in ipairs(loadingList) do
        harness:captureLoading(loadingId)
      end
      return self
    end

    function handle:clickAndOpen(buttonId, opts)
      local beforeSeq = harness.lastShownSeq
      self:click(buttonId, opts)
      return harness:waitForNewDialog(beforeSeq, buttonId)
    end

    function handle:isOpen(controller)
      return controller.openDialogs[self.dialog] ~= nil
    end

    function handle:close()
      self.dialog:close()
      harness:wait(1)
    end

    return handle
  end

  function harness:waitForNewDialog(beforeSeq, contextLabel)
    self:recordProgress("waitDialog:" .. tostring(contextLabel or "open"))
    for _ = 1, 200 do
      if self.lastShownSeq > beforeSeq and #self.openStack > 0 then
        local top = self.openStack[#self.openStack]
        if top._seq > beforeSeq then
          return wrapDialogHandle(top)
        end
      end
      self:wait(1)
    end
    error("Timed out waiting for dialog to open (" .. tostring(contextLabel or "unknown") .. ")")
  end

  function harness:open(fn, opts)
    local beforeSeq = self.lastShownSeq
    local loadingList = {}
    if opts and opts.loading then
      loadingList = type(opts.loading) == "table" and opts.loading or { opts.loading }
      self.loadingPauseRemaining = #loadingList
    end
    if opts and opts.tab then
      self.pendingTab = opts.tab
    end
    fn()
    for _, loadingId in ipairs(loadingList) do
      self:captureLoading(loadingId)
    end
    local handle = self:waitForNewDialog(beforeSeq, opts and opts.tab or "open")
    if opts and opts.wait then
      self:wait(opts.wait)
    end
    return handle
  end

  -- Install global Aseprite proxies
  local eventsProxy = setmetatable({}, {
    __index = function(_, key)
      if key == "on" then
        return function(_, eventName, callback)
          if eventName == "beforecommand" then
            harness.beforecommandListeners[#harness.beforecommandListeners + 1] = callback
          end
          return nativeEvents:on(eventName, callback)
        end
      end
      local value = nativeEvents[key]
      if type(value) == "function" then
        return function(_, ...)
          return value(nativeEvents, ...)
        end
      end
      return value
    end,
  })

  app = setmetatable({}, {
    __index = function(_, key)
      if key == "alert" and harness.customAlert then
        return harness.customAlert
      end
      if key == "events" then
        return eventsProxy
      end
      if key == "apiVersion" and harness.customApiVersion then
        return harness.customApiVersion
      end
      return nativeApp[key]
    end,
    __newindex = function(_, key, value)
      if key == "alert" then
        harness.customAlert = value
        return
      end
      nativeApp[key] = value
    end,
  })

  app.alert = function(spec)
    if not harness.pendingAlertId then
      local msg = type(spec) == "table"
          and (type(spec.text) == "table" and table.concat(spec.text, "\n") or tostring(spec.text))
        or tostring(spec)
      local file = io.open(harness.output .. "/error", "w")
      if file then
        file:write("Unexpected app.alert: " .. msg)
        file:close()
      end
      app.exit()
      error("Unexpected app.alert: " .. msg)
    end
    local id = harness.pendingAlertId
    local result = harness.pendingAlertReturn
    harness.pendingAlertId = nil
    harness.pendingAlertReturn = 1
    local title = type(spec) == "table" and (spec.title or "Asemode") or "Asemode"
    local text = type(spec) == "table" and spec.text or spec
    if id == "alert-error-preserved" and type(text) == "table" then
      local normalized = {}
      local rootPattern = harness.root:gsub("(%W)", "%%%1")
      for i, line in ipairs(text) do
        -- Stack traces contain machine-specific checkout paths and line numbers.
        normalized[i] = line
          :gsub("/private" .. rootPattern, "<project>")
          :gsub(rootPattern, "<project>")
          :gsub("[^%s]*src/", "<project>/src/")
          :gsub("[^%s]*scripts/", "<project>/scripts/")
          :gsub("%.lua:%d+", ".lua:<line>")
      end
      text = normalized
    end
    local buttons = (type(spec) == "table" and type(spec.buttons) == "table" and #spec.buttons > 0)
        and spec.buttons
      or { "&OK" }
    local d = nativeDialog({ title = title })
    if type(text) == "table" then
      for _, line in ipairs(text) do
        addWrappedAlertLines(d, line)
      end
    else
      for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        addWrappedAlertLines(d, line)
      end
    end
    d:separator({})
    for i, btn in ipairs(buttons) do
      d:button({ text = tostring(btn), focus = (i == 1) })
    end
    d:show({ wait = false, autoscrollbars = true })
    harness:wait(2)
    local derivedTitle = harness:deriveAlertTitle(id, title)
    harness:captureBounds(d.bounds, id, derivedTitle)
    d:close()
    harness:wait(1)
    return result
  end

  Task.new = function(runTask)
    local task = nativeTaskNew(function(checkpoint)
      local pausedOnce = false
      return runTask(function(message, fraction)
        checkpoint(message, fraction)
        if
          message
          and (fraction == nil or fraction > 0)
          and not pausedOnce
          and harness.loadingPauseRemaining > 0
          and harness.activeLoadingDialog
        then
          pausedOnce = true
          coroutine.yield()
        end
      end)
    end)
    local step = task.step
    function task:step(milliseconds)
      -- Let the first informative checkpoint choose the captured progress state.
      if harness.loadingPauseRemaining > 0 and harness.activeLoadingDialog then
        return step(self, 1000)
      end
      return step(self, milliseconds)
    end
    return task
  end

  Timer = function(timerOptions)
    if
      type(timerOptions) == "table"
      and timerOptions.interval == 0.015
      and harness.loadingPauseRemaining > 0
      and harness.activeLoadingDialog
    then
      local shouldPause = true
      local ticks = 0
      local nativeInstance
      nativeInstance = nativeTimer({
        interval = timerOptions.interval,
        ontick = function()
          if shouldPause then
            ticks = ticks + 1
          end
          timerOptions.ontick()
        end,
      })
      local proxy = {}
      setmetatable(proxy, {
        __index = function(_, key)
          if key == "start" then
            return function()
              if shouldPause and ticks >= 1 then
                shouldPause = false
                harness.loadingPauseRemaining = math.max(0, harness.loadingPauseRemaining - 1)
                harness.loadingReady = true
                harness.heldLoadingTimer = nativeInstance
                return
              end
              return nativeInstance:start()
            end
          end
          if key == "stop" then
            return function()
              return nativeInstance:stop()
            end
          end
          return nativeInstance[key]
        end,
      })
      return proxy
    end
    return nativeTimer(timerOptions)
  end

  Dialog = function(dialogOptions)
    local title = type(dialogOptions) == "table" and dialogOptions.title or dialogOptions
    local native = nativeDialog(dialogOptions)
    local buttons, changes, widgetKinds, tabs, tabOrder = {}, {}, {}, {}, {}
    local activeTabId, activeTabText = nil, nil
    local proxy = {
      _title = tostring(title or ""),
      _hasProgressLabel = false,
      _hasProgressBar = false,
      _isLoadingDialog = false,
      _seq = 0,
    }
    setmetatable(proxy, {
      __index = function(_, key)
        if key == "buttons" then
          return buttons
        end
        if key == "changes" then
          return changes
        end
        if key == "widgetKinds" then
          return widgetKinds
        end
        if key == "activeTabId" then
          return activeTabId
        end
        if key == "activeTabText" then
          return activeTabText
        end
        local value = native[key]
        if type(value) ~= "function" then
          return value
        end
        return function(_, arg)
          if key == "label" and type(arg) == "table" and arg.id == "progress" then
            proxy._hasProgressLabel = true
          end
          if key == "canvas" and type(arg) == "table" and arg.id == "progressBar" then
            proxy._hasProgressBar = true
          end
          if key == "tab" and type(arg) == "table" and arg.id then
            tabs[arg.id] = arg.text or arg.id
            tabOrder[#tabOrder + 1] = arg.id
          end
          if key == "button" and type(arg) == "table" and arg.onclick then
            buttons[arg.id or arg.text] = arg.onclick
          end
          if type(arg) == "table" and arg.id then
            if key == "file" then
              widgetKinds[arg.id] = "file"
            elseif key == "combobox" then
              widgetKinds[arg.id] = "combobox"
            elseif key == "check" or key == "radio" then
              widgetKinds[arg.id] = "selected"
            elseif key == "entry" or key == "number" then
              widgetKinds[arg.id] = "text"
            end
            if arg.onchange then
              changes[arg.id] = arg.onchange
            end
          end
          if key == "endtabs" and type(arg) == "table" then
            if harness.pendingTab then
              arg.selected = harness.pendingTab
              harness.pendingTab = nil
            end
            local selectedId = arg.selected or tabOrder[1]
            activeTabId = selectedId
            activeTabText = selectedId and tabs[selectedId] or nil
          end
          if key == "close" then
            for i = #harness.openStack, 1, -1 do
              if harness.openStack[i] == proxy then
                table.remove(harness.openStack, i)
              end
            end
          end
          local result = value(native, arg)
          if key == "show" then
            if proxy._hasProgressLabel and (proxy._hasProgressBar or next(buttons) == nil) then
              proxy._isLoadingDialog = true
              if harness.loadingPauseRemaining > 0 then
                harness.activeLoadingDialog = proxy
              end
            else
              harness.lastShownSeq = harness.lastShownSeq + 1
              proxy._seq = harness.lastShownSeq
              for i = #harness.openStack, 1, -1 do
                if harness.openStack[i] == proxy then
                  table.remove(harness.openStack, i)
                end
              end
              harness.openStack[#harness.openStack + 1] = proxy
            end
          end
          if result == native then
            return proxy
          end
          return result
        end
      end,
      __newindex = function(_, key, value)
        native[key] = value
      end,
    })
    return proxy
  end

  function harness:verifyComplete()
    for _, entry in ipairs(self.catalog.screenshots) do
      if self.activeSuiteSet[entry.suite] then
        if not self.onlySet or self.onlySet[entry.id] then
          assert(
            self.captured[entry.id],
            string.format(
              "Suite '%s' finished without capturing catalog entry '%s'",
              entry.suite,
              entry.id
            )
          )
        end
      end
    end
    U.write(self.output .. "/titles.json", json.encode(self.resolvedTitles))
  end

  return harness
end

return M
