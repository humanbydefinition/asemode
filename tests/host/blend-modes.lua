-- Run in Aseprite batch mode with --script-param root=<repository>.
local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local U = require("src.core.util")
local Import = require("src.document.portable_import")
local Export = require("src.document.portable_export")
local Controller = require("src.ui.controller")
local modes = {
  "normal",
  "additive",
  "multiply",
  "screen",
  "subtract",
  "darken",
  "lighten",
  "overlay",
  "softLight",
  "hardLight",
  "colorDodge",
  "colorBurn",
  "difference",
  "exclusion",
  "hslHue",
  "hslSaturation",
  "hslColor",
  "hslLuminosity",
  "divide",
}
local result = Import.read(U.read(root .. "/tests/fixtures/portable/v4-single-layer.json"))
assert(result.ok, result.error and result.error.message)
local layers = result.document.frames[1].layers
local template = layers[1]
local controller = Controller.new({ preferences = {} })
local job = controller.library:job(
  { kind = "bundled", id = "atascii" },
  { pixelSize = 8, cellWidth = 8, cellHeight = 8 }
)
local jobs, substitutes = {}, {}
for i, mode in ipairs(modes) do
  local layer = {}
  for key, value in pairs(template) do
    layer[key] = value
  end
  layer.id, layer.blendMode = "blend-" .. mode, mode
  layers[i] = layer
  jobs[i], substitutes[i] = job, true
end
local plan = Import.prepareImport(
  result.document,
  { jobs = jobs, substitutes = substitutes },
  { mode = "new" }
)
local output = Import.commitImport(plan, { allowClipping = true })
local exported =
  Export.export(output.sprite, output.layers[1], 1, { target = "all", frames = "all" })
local actual = {}
for _, layer in ipairs(exported.document.frames[1].layers) do
  actual[layer.id] = layer.blendMode
end
for _, mode in ipairs(modes) do
  assert(actual["blend-" .. mode] == mode, "blend mode did not round-trip: " .. mode)
end
output.sprite:close()
controller:close()
print("PASS all 19 portable blend modes")
