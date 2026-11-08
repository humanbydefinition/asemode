-- Run in Aseprite batch mode with --script-param root=<repository>.
local root = assert(app.params.root, "Pass the repository root as a script parameter")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Controller = require("src.ui.controller")
local Model = require("src.document.model")
local Edit = require("src.document.edit")
local Profile = require("src.document.profile")
local Transforms = require("src.document.transforms")
local Validate = require("src.document.validate")
local Snapshot = require("src.document.snapshot")
local pc = app.pixelColor

local controller = Controller.new({ preferences = {} })
controller:start()
for _, dimensions in ipairs({ { 8, 8 }, { 8, 16 } }) do
  for _, angle in ipairs({ 90, 180, -90 }) do
    local job = controller.library
      :job({ kind = "bundled", id = "atascii" }, {
        pixelSize = 8,
        cellWidth = dimensions[1],
        cellHeight = dimensions[2],
        characters = "AB",
      })
      :finish()
    local sprite, layer = Model.create(job, 4, 3, true, "transparent")
    app.sprite, app.layer = sprite, layer
    Edit.insert(sprite, layer, 1, "AB", 0, 0, "#ffffffff", "#000000ff")
    local image = layer.cels[1].image:clone()
    local metadata, flags = Profile.decode(layer, image:getPixel(0, 0))
    local id = Model.meta(layer).fontProfileId
    local flipped = pc.TILE_XFLIP
    image:drawPixel(
      0,
      0,
      Profile.orientedTile(
        sprite,
        id,
        metadata.glyphKey,
        metadata.foregroundRGBA,
        metadata.backgroundRGBA,
        flipped
      )
    )
    layer.cels[1].image = image
    sprite:newFrame()
    sprite.width, sprite.height = sprite.width + 1, sprite.height + 3
    local original = layer.cels[1].image.bytes
    local originalWidth, originalHeight = sprite.width, sprite.height
    local cellsWidth, cellsHeight = image.width, image.height
    local normal = sprite:newLayer()
    app.layer = normal
    app.command.Rotate({ ui = false, target = "sprite", angle = angle })
    local x, y
    if angle == 90 then
      x, y = cellsHeight - 1, 0
    elseif angle == -90 then
      x, y = 0, cellsWidth - 1
    else
      x, y = cellsWidth - 1, cellsHeight - 1
    end
    local _, actual = Profile.decode(layer, layer.cels[1].image:getPixel(x, y))
    local expected = Transforms.rotate(flipped, angle ~= -90)
    if angle == 180 then
      expected = Transforms.rotate(expected, true)
    end
    assert(actual == expected, "cell orientation was not rotated")
    assert(
      select(2, Profile.decode(layer, layer:cel(2).image:getPixel(x, y))) == expected,
      "second-frame cell orientation was not rotated"
    )
    assert(#Validate.run(sprite) == 0, "rotated document is invalid")
    Snapshot.capture(sprite, { layer }, 1)
    Snapshot.capture(sprite, { layer }, 2)
    local geometry = Model.geometry(sprite)
    assert(geometry.cellWidth == (angle == 180 and dimensions[1] or dimensions[2]))
    assert(geometry.cellHeight == (angle == 180 and dimensions[2] or dimensions[1]))
    app.undo()
    assert(sprite.width == originalWidth and sprite.height == originalHeight)
    assert(layer.cels[1].image.bytes == original, "one undo did not restore the cells")
    assert(Model.meta(layer).fontProfileId == id and #Validate.run(sprite) == 0)
    app.redo()
    assert(select(2, Profile.decode(layer, layer.cels[1].image:getPixel(x, y))) == expected)
    assert(#Validate.run(sprite) == 0)
    sprite:close()
    print("PASS rotation " .. dimensions[1] .. "x" .. dimensions[2] .. " " .. angle)
  end
end
local regular = Sprite(2, 3, ColorMode.RGB)
app.sprite = regular
app.command.Rotate({ ui = false, target = "sprite", angle = 90 })
assert(regular.width == 3 and regular.height == 2, "regular sprite rotation was changed")
regular:close()
print("PASS regular sprite rotation")
controller:close()
