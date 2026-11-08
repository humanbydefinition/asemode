-- Run in Aseprite batch mode with --script-param root=<repository>.
local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local U = require("src.core.util")
local Import = require("src.document.portable_import")
local Export = require("src.document.portable_export")
local Validate = require("src.document.validate")
local Controller = require("src.ui.controller")
local controller = Controller.new({ preferences = {} })
for _, fixture in ipairs({
  "/tests/fixtures/portable/v4-single-layer.json",
  "/tests/test-documents/layer-variants.textmode.json",
}) do
  local result = Import.read(U.read(root .. fixture))
  assert(result.ok, result.error and result.error.message)
  local job = controller.library:job(
    { kind = "bundled", id = "atascii" },
    { pixelSize = 8, cellWidth = 8, cellHeight = 8 }
  )
  local jobs, substitutes = {}, {}
  for _, frame in ipairs(result.document.frames) do
    for _ in ipairs(frame.layers) do
      jobs[#jobs + 1], substitutes[#substitutes + 1] = job, true
    end
  end
  local plan = Import.prepareImport(
    result.document,
    { jobs = jobs, substitutes = substitutes },
    { mode = "new" }
  )
  if #result.document.frames > 1 then
    assert(plan.layerVariantsSplit and #plan.layerVariants == 2)
  end
  local output = Import.commitImport(plan, { allowClipping = true })
  assert(#output.layers > 0 and #Validate.run(output.sprite) == 0)
  local exported =
    Export.export(output.sprite, output.layers[1], 1, { target = "all", frames = "all" })
  assert(#exported.document.frames == #result.document.frames)
  for i, frame in ipairs(result.document.frames) do
    assert(#exported.document.frames[i].layers == #frame.layers)
    assert(exported.document.frames[i].layers[1].blendMode == frame.layers[1].blendMode)
  end
  output.sprite:close()
end
controller:close()
print("PASS portable import preparation, commit, and export")
