-- Suite: Asemode Panel & Status Warnings
local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local StampState = require("src.document.stamp_state")

return function(ctx)
  local harness, controller, fixtures = ctx.harness, ctx.controller, ctx.fixtures
  local sprite, layer = fixtures.sprite, fixtures.layer

  local panel = harness:open(function()
    controller:open()
  end)
  local function capturePanel(id)
    -- Avoid the search field's blinking caret and focus-dependent placeholder.
    panel.dialog:modify({ id = "group", focus = true })
    panel:capture(id)
  end
  capturePanel("asemode")

  layer.isEditable = false
  controller:refresh()
  capturePanel("asemode-panel-locked")
  layer.isEditable = true

  local unavailableMeta = U.copy(fixtures.savedLayerMeta)
  unavailableMeta.fontProfileId = "missing"
  Model.setMeta(layer, unavailableMeta)
  Profile.invalidate()
  controller:refresh()
  capturePanel("asemode-panel-unavailable")

  local unsupportedMeta = U.copy(fixtures.savedLayerMeta)
  unsupportedMeta.schemaVersion = 99
  Model.setMeta(layer, unsupportedMeta)
  Profile.invalidate()
  controller:refresh()
  capturePanel("asemode-panel-unsupported-version")

  Model.setMeta(layer, U.copy(fixtures.savedLayerMeta))
  Profile.invalidate()

  -- Keep the missing-stamp warning visible while the screenshot dialog yields.
  controller.timer:stop()
  StampState.write(sprite, layer, {
    primary = { glyph = "0", fg = "#123456ff", bg = "#654321ff", flags = 0 },
  })
  controller.drawing:invalidateStamps()
  controller.drawing:restore(sprite, layer)
  assert(controller.drawing:snapshot().missingPrimary, "Expected a missing primary stamp")
  controller:refresh()
  capturePanel("asemode-panel-missing-stamps")

  controller.drawing:prepareBoth()
  controller:refresh()
  controller.timer:start()
  panel:close()
end
