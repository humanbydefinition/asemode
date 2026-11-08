-- A cancelable preparation task. No document transaction may cross a yield.
local M = {}

---Create a cancelable coroutine task. Transactions must not span checkpoints.
---@param run fun(checkpoint: fun(message?: string, fraction?: number)): any Work to run with cooperative checkpoints.
---@return AsemodeTask task Task controlled by step, cancel, and finish.
function M.new(run)
  local task = { done = false, canceled = false, progress = "Preparing...", fraction = 0 }
  local deadline

  ---Cooperative checkpoint invoked during task execution.
  ---@param message? string Optional progress status message.
  ---@param fraction? number Optional completion fraction in range 0.0 to 1.0.
  local function checkpoint(message, fraction)
    if task.canceled then
      error("Preparation canceled", 0)
    end
    if message then
      task.progress = message
    end
    if type(fraction) == "number" then
      task.fraction = math.max(0, math.min(1, fraction))
    end
    if deadline and os.clock() >= deadline then
      coroutine.yield()
    end
  end

  local thread = coroutine.create(function()
    return run(checkpoint)
  end)

  ---Resume the task until completion or its next checkpoint.
  ---@param milliseconds? number Checkpoint time budget; defaults to eight milliseconds.
  ---@return boolean done Whether the task has completed.
  function task:step(milliseconds)
    -- Native modal dialogs can dispatch the same timer before resume returns.
    -- Ignore that tick without changing the suspended/running thread's state.
    if self.canceled or self.running then
      return false
    end
    if self.done then
      return true
    end
    deadline = os.clock() + (milliseconds or 8) / 1000
    local active = thread
    self.running = true
    local ok, result = coroutine.resume(active)
    self.running = false

    -- cancel() may run in a nested UI callback and release our thread reference.
    if self.canceled then
      return false
    end
    if not ok then
      self.done = true
      thread = nil
      error(result, 0)
    end
    self.done = coroutine.status(active) == "dead"
    if self.done then
      self.result = result
      thread = nil
    end
    return self.done
  end

  ---Cancel the task and discard its result.
  function task:cancel()
    self.canceled = true
    thread = nil
    self.result = nil
  end

  ---Run the task to completion or raise if canceled.
  ---@return any result Task result.
  function task:finish()
    while not self:step(1000) do
      assert(not self.canceled, "Preparation canceled")
    end
    return self.result
  end

  return task
end

return M
