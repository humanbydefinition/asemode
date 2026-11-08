local Theme = require("src.ui.theme")
local M = {}

---Install dialog lifecycle and theme tracking on a UI controller.
function M.install(self)
  self.singletons = self.singletons or {}

  ---Focus and bring an open singleton dialog to front if already active.
  ---@param key string Singleton dialog identifier.
  ---@return boolean focused Whether an existing dialog was found and focused.
  function self:focusDialog(key)
    local d = self.singletons and self.singletons[key]
    if d and self.openDialogs[d] then
      if d.show then
        d:show({ wait = false })
      end
      return true
    end
    return false
  end

  ---Create and track a dialog, including close and theme callbacks.
  ---@param title string Dialog title.
  ---@param options table? Host dialog options; updated with title and close handler.
  ---@return Dialog dialog Tracked host dialog.
  function self:dialog(title, options)
    options = options or {}
    options.title = title
    local singletonKey = options.singleton
    local d, previousClose
    previousClose = options.onclose
    options.onclose = function()
      if singletonKey and self.singletons and self.singletons[singletonKey] == d then
        self.singletons[singletonKey] = nil
      end
      local callbacks = self.openDialogs[d] or {}
      self.openDialogs[d] = nil
      for _, callback in ipairs(callbacks) do
        callback()
      end
      for i = #self.dialogs, 1, -1 do
        if self.dialogs[i] == d then
          table.remove(self.dialogs, i)
          break
        end
      end
      if previousClose then
        previousClose()
      end
      if not next(self.openDialogs) and self.themeTimer then
        self.themeTimer:stop()
        self.themeTimer = nil
        self.themeSignature = nil
      end
    end
    d = Dialog(options)
    self.openDialogs[d] = {}
    self.dialogs[#self.dialogs + 1] = d
    if singletonKey then
      self.singletons[singletonKey] = d
    end
    if not self.themeTimer and app.isUIAvailable then
      self.themeSignature = Theme.signature(app.theme)
      self.themeTimer = Timer({
        interval = 0.15,
        ontick = function()
          self:refreshTheme()
        end,
      })
      self.themeTimer:start()
    end
    return d
  end

  ---Repaint open dialogs when the host theme changes.
  function self:refreshTheme()
    local signature = Theme.signature(app.theme)
    if signature == self.themeSignature then
      return
    end
    self.themeSignature = signature
    for d in pairs(self.openDialogs) do
      d:repaint()
    end
  end
end

return M
