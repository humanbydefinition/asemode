local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Controller = require("src.ui.controller")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Edit = require("src.document.edit")
local Validate = require("src.document.validate")
local controller = Controller.new({ preferences = {} })

local function font(size, id)
  return controller.library
    :job({ kind = "bundled", id = id or "atascii" }, {
      pixelSize = size,
      cellWidth = 8,
      cellHeight = 8,
      characters = "ABgp",
    })
    :finish()
end

for _, target in ipairs({ { 16, 16 }, { 16, 8 }, { 8, 16 }, { 4, 4 } }) do
  local sprite, layer = Model.create(font(16), 4, 3, true, "transparent")
  app.sprite, app.layer = sprite, layer
  Edit.insert(sprite, layer, 1, "ABgp", 0, 0, "#ffffffff", "#000000ff")
  app.command.NewFrame({ content = "cellinked" })
  assert(layer:cel(1).image.id == layer:cel(2).image.id)
  local smallId = Profile.install(sprite, font(8, "cpc464"), true)
  local second = Model.addLayer(sprite, smallId, "Second font")
  Edit.insert(sprite, second, 1, "A", 1, 1, "#ffffffff", "#000000ff")
  local unused = Profile.install(sprite, font(32), true)
  local beforeBytes = layer:cel(1).image.bytes
  local preview = Edit.prepareRegrid(sprite, target[1], target[2])
  assert(#preview == 2, "unused font must not be measured")
  local found = {}
  for _, item in ipairs(preview) do
    assert(item.oldId ~= unused)
    found[item.oldId] = item.job.profile
    item.job:finish()
  end
  local largeId = Model.meta(layer).fontProfileId
  assert(found[largeId].pixelSize == 16 and found[smallId].pixelSize == 8)
  if target[1] == 16 and target[2] == 16 then
    assert(found[largeId].clippedGlyphs == 0, "larger cells should reveal the glyphs")
    local expected = controller.library
      :job({ kind = "bundled", id = "atascii" }, {
        pixelSize = 16,
        cellWidth = 16,
        cellHeight = 16,
        characters = "ABgp",
      })
      :finish()
    for _, item in ipairs(preview) do
      if item.oldId == largeId then
        assert(item.job.masks[1].bytes == expected.masks[1].bytes, "glyph mask was not restored")
      end
    end
  else
    assert(found[largeId].clippedGlyphs > 0, "clipping must be reported for smaller cells")
    assert(not pcall(Edit.regrid, sprite, preview, target[1], target[2], false, true))
    assert(Model.geometry(sprite).cellWidth == 8 and Model.geometry(sprite).cellHeight == 8)
  end
  app.layer = layer
  Edit.regrid(sprite, preview, target[1], target[2], true, true)
  assert(Profile.index(sprite, Model.meta(layer).fontProfileId).profile.pixelSize == 16)
  assert(Profile.index(sprite, Model.meta(second).fontProfileId).profile.pixelSize == 8)
  assert(sprite.width == 4 * target[1] and sprite.height == 3 * target[2])
  assert(layer:cel(1).image.id == layer:cel(2).image.id, "linked cels must remain linked")
  assert(#Validate.run(sprite) == 0)
  app.undo()
  assert(Model.geometry(sprite).cellWidth == 8 and Model.geometry(sprite).cellHeight == 8)
  assert(layer:cel(1).image.bytes == beforeBytes and #Validate.run(sprite) == 0)
  app.redo()
  assert(Model.geometry(sprite).cellWidth == target[1] and #Validate.run(sprite) == 0)
  sprite:close()
end

local mixed, text = Model.create(font(8), 4, 3, true, "transparent")
app.sprite, app.layer = mixed, text
Edit.insert(mixed, text, 1, "A", 0, 0, "#ffffffff", "#000000ff")
Edit.insert(mixed, text, 1, "B", 3, 2, "#ffffffff", "#000000ff")
app.command.NewFrame({ content = "cellinked" })
local pixels = mixed:newLayer()
local image = Image(32, 24, ColorMode.RGB)
image:drawPixel(31, 23, app.pixelColor.rgba(100, 50, 30, 255))
mixed:newCel(pixels, 1, image, Point(0, 0))
local pixelBytes = pixels:cel(1).image.bytes
app.layer = text
local stale = Edit.prepareRegrid(mixed, 16, 16)
for _, item in ipairs(stale) do
  item.job:finish()
end
Edit.insert(mixed, text, 1, "g", 1, 0, "#ffffffff", "#000000ff")
assert(not pcall(Edit.regrid, mixed, stale, 16, 16, true, true), "stale preview was accepted")
assert(Model.geometry(mixed).cellWidth == 8 and mixed.width == 32 and mixed.height == 24)
local current = Edit.prepareRegrid(mixed, 16, 16)
for _, item in ipairs(current) do
  item.job:finish()
end
local impact = Edit.previewRegrid(mixed, 16, 16)
assert(impact.mixed and impact.width == 32 and impact.height == 24 and impact.hidden > 0)
assert(not pcall(Edit.regrid, mixed, current, 16, 16, true, false), "hidden cells were not guarded")
Edit.regrid(mixed, current, 16, 16, true, true)
assert(mixed.width == 32 and mixed.height == 24 and pixels:cel(1).image.bytes == pixelBytes)
assert(Profile.index(mixed, Model.meta(text).fontProfileId).profile.pixelSize == 8)
assert(#Validate.run(mixed) == 0)
app.undo()
assert(Model.geometry(mixed).cellWidth == 8 and pixels:cel(1).image.bytes == pixelBytes)
app.redo()
assert(Model.geometry(mixed).cellWidth == 16 and pixels:cel(1).image.bytes == pixelBytes)
local hiddenBytes = text:cel(1).image.bytes
local path = app.fs.joinPath(app.fs.tempPath, "asemode-regrid-" .. tostring(Uuid()) .. ".aseprite")
mixed:saveAs(path)
mixed:close()
local restored = assert(app.open(path))
local restoredText
for _, layer in ipairs(Model.layers(restored)) do
  if Model.layerManaged(layer) then
    restoredText = layer
  end
end
assert(restoredText and restoredText:cel(1).image.bytes == hiddenBytes)
assert(#Validate.run(restored) == 0, "saved mixed document must remain valid")
restored:close()
os.remove(path)
controller:close()
print("PASS regrid preserves font sizes, linked cels, and mixed artwork")
