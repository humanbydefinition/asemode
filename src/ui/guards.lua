local M = {}

---Install guarded callbacks on a UI controller.
function M.install(self)
  ---Report recurring background errors without opening modal dialogs.
  ---@param run function Background callback.
  ---@return function guarded Callback that logs distinct errors.
  function self:backgroundGuard(run)
    local lastError, running
    return function(...)
      if running or self.errorDialogOpen then
        return
      end
      running = true
      local args = { ... }
      local ok, err = xpcall(function()
        return run(table.unpack(args))
      end, debug.traceback)
      running = false
      if not ok then
        local trace = tostring(err)
        local message = trace:match("^[^\n]*") or trace
        if message ~= lastError then
          print("[Asemode background error]\n" .. trace)
          lastError = message
        end
      else
        lastError = nil
      end
    end
  end
end

return M
