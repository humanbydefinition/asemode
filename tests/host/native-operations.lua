-- Run in Aseprite batch mode with --script-param root=<repository>.
local root = assert(app.params.root, "Pass the repository root as a script parameter")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Controller = require("src.ui.controller")
local Edit = require("src.document.edit")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")

local controller = Controller.new({ preferences = {} })
controller:start()
local job = controller.library
  :job({ kind = "bundled", id = "atascii" }, {
    pixelSize = 8,
    cellWidth = 8,
    cellHeight = 8,
    characters = "AB",
  })
  :finish()
local sprite, layer = Model.create(job, 4, 3, true, "transparent")
app.sprite, app.layer = sprite, layer
Edit.insert(sprite, layer, 1, "AB", 0, 0, "#ffffffff", "#000000ff")
local normal = sprite:newLayer()
app.layer = normal
local width, height = sprite.width, sprite.height
app.command.SpriteSize({ ui = false, width = width * 2, height = height * 2 })
app.command.CanvasSize({ ui = false, width = width * 2, height = height * 2 })
assert(sprite.width == width and sprite.height == height, "native resize was not blocked")
app.command.ChangePixelFormat({ format = "indexed" })
assert(sprite.colorMode == ColorMode.RGB, "native color conversion was not blocked")
local layerCount = #sprite.layers
app.command.FlattenLayers()
assert(#sprite.layers == layerCount, "native flatten was not blocked")
app.layer = layer
app.command.ConvertLayer({ to = "layer" })
assert(layer.isTilemap, "native layer conversion was not blocked")
app.layer = normal
local index = Profile.index(sprite, Model.meta(layer).fontProfileId)
local function tileBytes()
  local result = {}
  for _, tileset in ipairs({ index.masks, index.paint }) do
    for i = 0, #tileset - 1 do
      result[#result + 1] = tileset:tile(i).image.bytes
    end
  end
  return table.concat(result)
end
local before = tileBytes()
local celBytes = layer:cel(1).image.bytes
app.layer = layer
local previousPrint, warning = print, nil
print = function(message)
  warning = message
end
app.command.PasteText({ ui = false, text = "A" })
print = previousPrint
assert(warning and warning:find("Insert Text", 1, true), "insert text warning was not shown")
assert(tileBytes() == before and layer:cel(1).image.bytes == celBytes)
warning = nil
print = function(message)
  warning = message
end
app.command.Paste()
print = previousPrint
assert(warning and warning:find("Native Paste", 1, true), "paste warning was not shown")
assert(tileBytes() == before and layer:cel(1).image.bytes == celBytes, "paste changed Asemode data")
app.layer = normal
local normalImage = Image(sprite.width, sprite.height, ColorMode.RGB)
local copiedPixel = app.pixelColor.rgba(30, 90, 150, 255)
normalImage:drawPixel(0, 0, copiedPixel)
sprite:newCel(normal, 1, normalImage, Point(0, 0))
sprite.selection = Selection(Rectangle(0, 0, 1, 1))
app.command.Copy()
app.command.Paste({ x = 2, y = 0 })
assert(
  normal:cel(1).image:getPixel(2, 0) == copiedPixel,
  "paste into mixed sprite pixel layer was blocked"
)
assert(tileBytes() == before and layer:cel(1).image.bytes == celBytes)
app.layer = layer
controller:close()
app.command.InvertColor({ ui = false })
assert(
  tileBytes() ~= before and #Validate.run(sprite, layer) > 0,
  "unguarded filter did not change tiles"
)
app.undo()
assert(tileBytes() == before and #Validate.run(sprite, layer) == 0, "undo did not restore tiles")
controller:start()
for _, name in ipairs({
  "ReplaceColor",
  "InvertColor",
  "BrightnessContrast",
  "HueSaturation",
  "ColorCurve",
  "Outline",
  "ConvolutionMatrix",
  "Despeckle",
}) do
  for _, target in ipairs({ layer, normal }) do
    app.layer = target
    app.command[name]({ ui = false })
  end
  assert(tileBytes() == before and layer:cel(1).image.bytes == celBytes, name .. " changed tiles")
  assert(#Validate.run(sprite, layer) == 0, name .. " invalidated the text layer")
  print("PASS blocked filter " .. name)
end
sprite:close()
local plain = Sprite(8, 8, ColorMode.RGB)
local image = plain.cels[1].image
local pixel = app.pixelColor.rgba(40, 60, 80, 255)
image:drawPixel(0, 0, pixel)
plain.selection = Selection(Rectangle(0, 0, 1, 1))
app.command.Copy()
app.command.Paste({ x = 2, y = 0 })
assert(plain.cels[1].image:getPixel(2, 0) == pixel, "regular sprite paste was blocked")
app.command.CopyMerged()
app.command.InvertColor({ ui = false })
assert(plain.cels[1].image:getPixel(0, 0) ~= pixel, "regular sprite filter was blocked")
plain:close()
local native = Sprite(16, 16, ColorMode.RGB)
app.command.NewLayer({ tilemap = true, ui = false, gridBounds = Rectangle(0, 0, 8, 8) })
local nativeTilemap = app.layer
assert(nativeTilemap.isTilemap and not Model.markedLayer(native, nativeTilemap))
local policy = require("src.session.native_operations")
for _, name in ipairs({
  "PasteText",
  "Paste",
  "SpriteSize",
  "CanvasSize",
  "ChangePixelFormat",
  "ConvertLayer",
  "FlattenLayers",
  "ReplaceColor",
  "InvertColor",
  "BrightnessContrast",
  "HueSaturation",
  "ColorCurve",
  "Outline",
  "ConvolutionMatrix",
  "Despeckle",
}) do
  local decision =
    policy.classify(name, nil, { sprite = native, layer = nativeTilemap, range = app.range })
  assert(decision.action == "allow", name .. " blocked an ordinary tilemap")
end
native:close()
controller:close()
print("PASS regular sprite filter and ordinary tilemap scope")
