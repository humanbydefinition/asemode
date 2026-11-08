-- Owns one preparation operation and its timer. Transactions must not yield.
local U = require("src.core.util")
local Theme = require("src.ui.theme")
local M = {}

local PROGRESS_BAR_WIDTH = 180
local PROGRESS_BAR_HEIGHT = 16

---Create a runner for cooperative tasks and their progress dialogs.
---@param options table Host callbacks for dialogs, timers, and guarded execution.
---@return table runner Task runner.
function M.new(options)
  local self = { active = nil }
  ---Check whether a preparation task is active.
  ---@return boolean active Whether a task is active.
  function self:isActive()
    return self.active ~= nil
  end

  ---Check whether the active task blocks drawing.
  ---@return boolean blocked Whether drawing is blocked.
  function self:blocksDrawing()
    return self.active ~= nil and self.active.blocksDrawing
  end

  ---Start one cooperative task and manage its callbacks and progress dialog.
  ---@param task AsemodeTask Task to run.
  ---@param config table Progress, completion, cancellation, and cleanup options.
  ---@return table handle Task handle with cancellation state.
  function self:start(task, config)
    U.check(not self.active, "Finish or cancel the current import first")
    local handle = { task = task, state = "running", blocksDrawing = config.blocksDrawing or false }
    local dialog, timer, stepping
    self.active = handle
    local function report(err)
      options.guard(function()
        error(err, 0)
      end)()
    end

    local function settle(state, result)
      if handle.state ~= "running" then
        return
      end
      handle.state = state
      local failures = {}
      local function invoke(fn, ...)
        if not fn then
          return
        end
        local ok, err = pcall(fn, ...)
        if not ok then
          failures[#failures + 1] = err
        end
      end
      if self.active == handle then
        self.active = nil
      end
      if timer then
        invoke(function()
          timer:stop()
        end)
      end
      if state ~= "completed" and not task.done then
        invoke(function()
          task:cancel()
        end)
      end
      if dialog then
        invoke(function()
          dialog:close()
        end)
      end
      if state == "completed" then
        invoke(config.complete, result)
      else
        invoke(config.cancel)
        if state == "failed" then
          if config.error then
            invoke(config.error, result)
          else
            failures[#failures + 1] = result
          end
        end
      end
      invoke(config.cleanup, state)
      for _, err in ipairs(failures) do
        report(err)
      end
    end

    function handle:cancel()
      settle("canceled")
    end

    local function tick()
      if handle.state ~= "running" or stepping or self.active ~= handle then
        return
      end
      stepping = true
      if timer then
        timer:stop()
      end
      local ok, done = pcall(function()
        return task:step(config.milliseconds or 8)
      end)
      if handle.state ~= "running" or self.active ~= handle then
        stepping = false
        return
      end
      if not ok then
        stepping = false
        settle("failed", done)
        return
      end
      if dialog then
        local updated, err = pcall(function()
          dialog:modify({ id = "progress", text = task.progress })
          dialog:repaint()
        end)
        if not updated then
          stepping = false
          settle("failed", err)
          return
        end
      end
      -- Widget updates can dispatch nested callbacks, including cancellation.
      if handle.state ~= "running" or self.active ~= handle then
        stepping = false
        return
      end
      stepping = false
      if done then
        local result = task.result
        task.result = nil
        settle("completed", result)
      elseif timer then
        timer:start()
      end
    end
    if not options.uiAvailable() then
      while handle.state == "running" do
        tick()
      end
      return handle
    end
    local ok, err = pcall(function()
      local title = config.title or "Preparing"
      dialog = options.dialog(title, {
        onclose = function()
          handle:cancel()
        end,
      })
      dialog
        :label({ id = "progress", text = config.progress or "Preparing..." })
        :newrow()
        :canvas({
          id = "progressBar",
          width = PROGRESS_BAR_WIDTH,
          height = PROGRESS_BAR_HEIGHT,
          hexpand = true,
          vexpand = false,
          autoscaling = true,
          onpaint = function(ev)
            Theme.progressBar(ev.context, task.fraction or 0)
          end,
        })
        :show({ wait = false })
      if handle.state ~= "running" then
        return
      end
      timer = options.timer({ interval = 0.015, ontick = tick })
      if handle.state ~= "running" then
        timer:stop()
        return
      end
      timer:start()
    end)
    if not ok then
      settle("failed", err)
    end
    return handle
  end

  ---Cancel the active task, if any.
  function self:close()
    if self.active then
      self.active:cancel()
    end
  end
  return self
end
return M
