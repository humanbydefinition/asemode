-- Suite: Modal Alerts & Native Operation Guards
local U = require("src.core.util")

return function(ctx)
  local harness, controller = ctx.harness, ctx.controller

  controller:start()
  harness:captureAlert("alert-error-preserved", function()
    controller:guard(function()
      error("Choose an artwork JSON filename first", 0)
    end)()
  end, 1)

  for _, spec in ipairs(harness:alertsForSuite("alerts")) do
    harness:captureAlert(spec.id, function()
      harness:emitBeforeCommand(spec.command, spec.params or {})
    end, 1)
  end

  controller.tasks.active = { blocksDrawing = true }
  harness:captureAlert("alert-rotate-error", function()
    harness:emitBeforeCommand("Rotate", { angle = "90" })
  end, 1)

  harness:captureAlert("alert-stamp-state-busy", function()
    harness:emitBeforeCommand("SaveFile", {})
  end, 1)
  controller.tasks.active = nil

  local mainSource = U.read(harness.root .. "/src/main.lua", 65536)
  local mainChunk = assert(load(mainSource, "@src/main.lua", "t", _G))
  mainChunk()
  harness:withApiVersion(40, function()
    harness:captureAlert("alert-version-requirement", function()
      init({})
    end, 1)
  end)
end
