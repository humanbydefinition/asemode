local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Controller = require("src.ui.controller")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Edit = require("src.document.edit")
local Clipboard = require("src.document.clipboard")
local Validate = require("src.document.validate")
local Snapshot = require("src.document.snapshot")
local controller = Controller.new({ preferences = {} })
controller:start()
local function job(chars, w, h, font)
  return controller.library
    :job({ kind = "bundled", id = font or "atascii" }, {
      pixelSize = 8,
      cellWidth = w,
      cellHeight = h,
      characters = chars,
    })
    :finish()
end
for _, size in ipairs({ { 8, 8 }, { 8, 16 } }) do
  local source, layer = Model.create(job("AB", size[1], size[2]), 4, 3, true, "transparent")
  app.sprite, app.layer = source, layer
  Edit.insert(source, layer, 1, "ABA", 0, 0, "#ffffffff", "#000000ff")
  local sourceImage = layer:cel(1).image:clone()
  local sourceMeta = Profile.decode(layer, sourceImage:getPixel(0, 0))
  sourceImage:drawPixel(
    0,
    0,
    Profile.orientedTile(
      source,
      Model.meta(layer).fontProfileId,
      sourceMeta.glyphKey,
      sourceMeta.foregroundRGBA,
      sourceMeta.backgroundRGBA,
      app.pixelColor.TILE_XFLIP
    )
  )
  layer:cel(1).image = sourceImage
  local selected = Selection(Rectangle(0, 0, size[1] * 2, size[2]))
  local copied = Clipboard.copy(source, layer, 1, selected)
  assert(#copied.cells == 2)
  source.selection = selected
  controller.document:copyCells()
  local captured = Clipboard.copy(source, layer, 1, source.selection)
  assert(#captured.cells == 2 and captured.cells[2].glyph == "B", "workflow source changed")
  local shared = Model.addLayer(source, Model.meta(layer).fontProfileId, "Shared font")
  app.sprite, app.layer = source, shared
  local sameSprite = Clipboard.prepare(source, shared, 1, nil, copied)
  controller.drawing:withSuppression(function()
    Clipboard.apply(sameSprite)
  end)
  assert(Profile.decode(shared, shared:cel(1).image:getPixel(1, 0)).glyphKey == "B")
  local holes = Selection(Rectangle(0, 0, size[1] * 3, size[2]))
  holes:subtract(Rectangle(size[1], 0, size[1], size[2]))
  local sparse = Clipboard.copy(source, layer, 1, holes)
  assert(#sparse.cells == 2 and sparse.cells[2].col == 2)
  local sparsePaste = Clipboard.prepare(source, shared, 1, nil, sparse)
  controller.drawing:withSuppression(function()
    Clipboard.apply(sparsePaste)
  end)
  assert(Profile.decode(shared, shared:cel(1).image:getPixel(1, 0)).glyphKey == "B")
  assert(Profile.decode(shared, shared:cel(1).image:getPixel(2, 0)).glyphKey == "A")
  assert(#Validate.run(source) == 0)
  local target, targetLayer =
    Model.create(job("A", size[1], size[2], "bescii"), 4, 3, true, "transparent")
  app.sprite, app.layer = target, targetLayer
  source:close()
  controller.drawing:ensureActive()
  controller.drawing:flush()
  local destination = Selection(Rectangle(size[1], size[2], size[1], size[2]))
  local prepared = Clipboard.prepare(target, targetLayer, 1, destination, copied)
  assert(prepared.missing == 0, "supported B was incorrectly marked missing")
  controller.drawing:withSuppression(function()
    Clipboard.apply(prepared)
  end)
  local cel = assert(targetLayer:cel(1))
  local a, flags = Profile.decode(targetLayer, cel.image:getPixel(1, 1))
  local b = Profile.decode(targetLayer, cel.image:getPixel(2, 1))
  assert(a.glyphKey == "A" and b.glyphKey == "B", "wrong glyphs pasted")
  assert(flags == app.pixelColor.TILE_XFLIP, "orientation was not preserved")
  assert(#Validate.run(target) == 0)
  Snapshot.capture(target, { targetLayer }, 1)
  app.undo()
  assert(app.sprite == target, "undo switched sprite")
  assert(
    not targetLayer:cel(1) or app.pixelColor.tileI(targetLayer:cel(1).image:getPixel(1, 1)) == 0
  )
  app.redo()
  assert(app.sprite == target, "redo switched sprite")
  assert(#Validate.run(target) == 0)
  assert(
    Profile.index(target, Model.meta(targetLayer).fontProfileId).glyphs.B.meta.renderFallback == nil
  )
  local invalid = Selection(Rectangle(size[1] * 3, size[2], size[1], size[2]))
  assert(not pcall(Clipboard.prepare, target, targetLayer, 1, invalid, copied))
  local missingCopy = {
    col = 0,
    row = 0,
    cells = {
      { col = 0, row = 0, glyph = "🦄", fg = "#ffffffff", bg = "#000000ff", flags = 0 },
    },
  }
  local missing = Clipboard.prepare(target, targetLayer, 1, nil, missingCopy)
  assert(missing.missing == 1 and missing.writes[1].glyph == " ")
  controller.drawing:withSuppression(function()
    Clipboard.apply(missing)
  end)
  assert(Profile.decode(targetLayer, targetLayer:cel(1).image:getPixel(0, 0)).glyphKey == " ")
  assert(#Validate.run(target) == 0)
  target.selection = Selection(Rectangle(0, size[2] * 2, size[1], size[2]))
  controller.document:pasteCells()
  assert(Profile.decode(targetLayer, targetLayer:cel(1).image:getPixel(0, 2)).glyphKey == "A")
  local actualB = Profile.decode(targetLayer, targetLayer:cel(1).image:getPixel(1, 2))
  assert(
    actualB and actualB.glyphKey == "B",
    "workflow pasted " .. tostring(actualB and actualB.glyphKey)
  )
  assert(#Validate.run(target) == 0)
  target:close()
end
controller:close()
local commands = {}
local plugin = {
  preferences = {},
  newMenuGroup = function() end,
  newCommand = function(_, command)
    commands[command.id] = command
  end,
}
dofile(root .. "/src/main.lua")
init(plugin)
assert(
  commands.AsemodeCopyCells and commands.AsemodePasteCells,
  "clipboard commands not registered"
)
assert(not commands.AsemodePasteCells.onenabled(), "paste enabled without a copied selection")
local gateSprite, gateLayer = Model.create(job("AB", 8, 8), 4, 3, true, "transparent")
app.sprite, app.layer = gateSprite, gateLayer
assert(not commands.AsemodeCopyCells.onenabled(), "copy enabled without selection")
gateSprite.selection = Selection(Rectangle(0, 0, 8, 8))
assert(commands.AsemodeCopyCells.onenabled(), "copy disabled with selection")
local regularLayer = gateSprite:newLayer()
app.layer = regularLayer
assert(not commands.AsemodeCopyCells.onenabled(), "copy enabled on a regular layer")
gateSprite:close()
exit(plugin)
print("PASS Asemode cell clipboard")
