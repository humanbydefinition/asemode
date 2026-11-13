-- Run in Aseprite batch mode with --script-param root=<repository>.
local root = assert(app.params.root, "Pass the repository root as a script parameter")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Controller = require("src.ui.controller")
local Model = require("src.document.model")
local Edit = require("src.document.edit")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local pc = app.pixelColor

local controller = Controller.new({ preferences = {} })
controller:start()

local function render(sprite, frame)
  local image = Image(sprite.width, sprite.height, ColorMode.RGB)
  image:drawSprite(sprite, frame)
  return image
end

local function mirror(image, orientation)
  local copy = image:clone()
  copy:flip(orientation == "horizontal" and FlipType.HORIZONTAL or FlipType.VERTICAL)
  return copy.bytes
end

for _, dimensions in ipairs({ { 8, 8 }, { 8, 16 }, { 7, 12 } }) do
  for _, orientation in ipairs({ "horizontal", "vertical" }) do
    local job = controller.library
      :job({ kind = "bundled", id = "atascii" }, {
        pixelSize = 8,
        cellWidth = dimensions[1],
        cellHeight = dimensions[2],
        characters = "AB",
      })
      :finish()
    local sprite, layer = Model.create(job, 8, 3, true, "transparent")
    app.sprite, app.layer = sprite, layer
    Edit.insert(sprite, layer, 1, "ABABABAB", 0, 0, "#ffffffff", "#000000ff")
    local id = Model.meta(layer).fontProfileId
    local image = layer:cel(1).image:clone()
    for x = 0, 7 do
      local meta = Profile.decode(layer, image:getPixel(x, 0))
      local flags = (x & 1 ~= 0 and pc.TILE_XFLIP or 0)
        | (x & 2 ~= 0 and pc.TILE_YFLIP or 0)
        | (x & 4 ~= 0 and pc.TILE_DFLIP or 0)
      image:drawPixel(
        x,
        0,
        Profile.orientedTile(
          sprite,
          id,
          meta.glyphKey,
          meta.foregroundRGBA,
          meta.backgroundRGBA,
          flags
        )
      )
    end
    layer:cel(1).image = image
    local second = Model.addLayer(sprite, id, "Second text layer")
    Edit.insert(sprite, second, 1, "B", 3, 1, "#ff0000ff", "#00000000")
    app.layer = layer
    app.command.NewFrame({ content = "cellinked" })
    assert(layer:cel(1).image.id == layer:cel(2).image.id, "frames must be linked")
    local geometry = Model.geometry(sprite)
    geometry.originX, geometry.originY = 2, 3
    Model.setMeta(sprite, geometry)
    for _, textLayer in ipairs({ layer, second }) do
      local positions = {}
      for _, cel in ipairs(textLayer.cels) do
        positions[cel.frameNumber] = Point(cel.position.x + 2 - dimensions[1], cel.position.y + 3)
      end
      for _, cel in ipairs(textLayer.cels) do
        cel.position = positions[cel.frameNumber]
      end
    end
    sprite.width, sprite.height = sprite.width - 3, sprite.height - 2
    local normal = sprite:newLayer()
    second.isEditable = false
    local normalImage = Image(sprite.width, sprite.height, ColorMode.RGB)
    normalImage:drawPixel(1, 1, pc.rgba(100, 30, 70, 255))
    sprite:newCel(normal, 1, normalImage, Point(0, 0))
    sprite:newCel(normal, 2, normalImage:clone(), Point(0, 0))
    local width, height = sprite.width, sprite.height
    sprite.selection = Selection(Rectangle(1, 2, 3, 4))
    local before = render(sprite, 1)
    local expected = mirror(before, orientation)
    local expectedSecond = mirror(render(sprite, 2), orientation)
    local bytes = layer:cel(1).image.bytes
    local masks = Profile.index(sprite, id).masks:tile(1).image.bytes
    app.command.Flip({ target = "canvas", orientation = orientation })
    assert(render(sprite, 1).bytes == expected, "canvas pixels were not mirrored: " .. orientation)
    assert(render(sprite, 2).bytes == expectedSecond, "second frame was not mirrored")
    assert(layer:cel(1).image.id == layer:cel(2).image.id, "flip broke linked cels")
    for x = 0, 7 do
      local targetX = orientation == "horizontal" and 7 - x or x
      local targetY = orientation == "vertical" and image.height - 1 or 0
      local meta, flags = Profile.decode(layer, layer:cel(1).image:getPixel(targetX, targetY))
      local originalFlags = (x & 1 ~= 0 and pc.TILE_XFLIP or 0)
        | (x & 2 ~= 0 and pc.TILE_YFLIP or 0)
        | (x & 4 ~= 0 and pc.TILE_DFLIP or 0)
      local flipFlag = orientation == "horizontal" and pc.TILE_XFLIP or pc.TILE_YFLIP
      assert(meta.glyphKey == (x % 2 == 0 and "A" or "B") and flags == originalFlags ~ flipFlag)
    end
    assert(sprite.width == width and sprite.height == height, "canvas size changed")
    local bounds = sprite.selection.bounds
    assert(bounds.x == (orientation == "horizontal" and width - 4 or 1))
    assert(bounds.y == (orientation == "vertical" and height - 6 or 2))
    local result = Model.geometry(sprite)
    assert(result.cellWidth == dimensions[1] and result.cellHeight == dimensions[2])
    assert(
      Model.meta(layer).fontProfileId == id
        and Profile.index(sprite, id).masks:tile(1).image.bytes == masks
    )
    assert(#Validate.run(sprite) == 0, "flipped document is invalid")
    app.undo()
    assert(
      layer:cel(1).image.bytes == bytes and render(sprite, 1).bytes == before.bytes,
      "undo failed"
    )
    app.redo()
    assert(render(sprite, 1).bytes == expected, "redo failed")
    app.command.Flip({ target = "canvas", orientation = orientation })
    assert(render(sprite, 1).bytes == before.bytes, "double flip failed")
    assert(#Validate.run(sprite) == 0)
    if orientation == "horizontal" then
      app.command.Flip({ target = "canvas", orientation = "horizontal" })
      app.command.Flip({ target = "canvas", orientation = "vertical" })
      local twice = render(sprite, 1).bytes
      app.undo()
      app.undo()
      app.command.Rotate({ target = "canvas", angle = 180, ui = false })
      assert(render(sprite, 1).bytes == twice, "two-axis flip differs from 180 degree rotation")
    end
    sprite:close()
    print("PASS canvas flip " .. dimensions[1] .. "x" .. dimensions[2] .. " " .. orientation)
  end
end
local regular = Sprite(3, 2, ColorMode.RGB)
app.sprite = regular
local regularImage = Image(3, 2, ColorMode.RGB)
regularImage:drawPixel(0, 0, pc.rgba(200, 50, 30, 255))
regular.cels[1].image = regularImage
app.command.Flip({ target = "canvas", orientation = "horizontal" })
assert(regular.cels[1].image:getPixel(2, 0) == pc.rgba(200, 50, 30, 255), "ordinary flip changed")
regular:close()
local invalidJob = controller.library
  :job({ kind = "bundled", id = "atascii" }, {
    pixelSize = 8,
    cellWidth = 8,
    cellHeight = 16,
    characters = "A",
  })
  :finish()
local invalid, invalidLayer = Model.create(invalidJob, 2, 2, true, "transparent")
app.sprite, app.layer = invalid, invalidLayer
Edit.insert(invalid, invalidLayer, 1, "A", 0, 0, "#ffffffff", "#000000ff")
local initialBytes = invalidLayer:cel(1).image.bytes
local initialPosition = invalidLayer:cel(1).position
local initialGeometry = Model.geometry(invalid)
local originalRemap, originalPrint = Edit.remapLayers, print
local warning
Edit.remapLayers = function()
  error("forced remap failure")
end
print = function(message)
  warning = message
end
app.command.Flip({ target = "canvas", orientation = "horizontal" })
Edit.remapLayers, print = originalRemap, originalPrint
assert(warning and warning:find("Could not flip", 1, true), "failed flip was not reported")
assert(
  invalidLayer:cel(1).image.bytes == initialBytes
    and invalidLayer:cel(1).position.x == initialPosition.x
)
assert(Model.geometry(invalid).originX == initialGeometry.originX and #Validate.run(invalid) == 0)
invalidLayer:cel(1).position = Point(1, 0)
local invalidBytes = invalidLayer:cel(1).image.bytes
warning = nil
print = function(message)
  warning = message
end
app.command.Flip({ target = "canvas", orientation = "horizontal" })
print = originalPrint
assert(warning and warning:find("Could not flip", 1, true), "invalid document was not reported")
assert(invalidLayer:cel(1).position.x == 1 and invalidLayer:cel(1).image.bytes == invalidBytes)
invalid:close()
controller:close()
