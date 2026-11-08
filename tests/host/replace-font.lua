local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Controller = require("src.ui.controller")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Edit = require("src.document.edit")
local Validate = require("src.document.validate")
local controller = Controller.new({ preferences = {} })
local function job()
  return controller.library
    :job(
      { kind = "bundled", id = "atascii" },
      { pixelSize = 8, cellWidth = 8, cellHeight = 8, characters = "AB" }
    )
    :finish()
end
local sprite, layer = Model.create(job(), 4, 3, true, "transparent")
app.sprite, app.layer = sprite, layer
Edit.insert(sprite, layer, 1, "AB", 0, 0, "#ffffffff", "#000000ff")
app.command.NewFrame({ content = "cellinked" })
assert(layer:cel(1).image.id == layer:cel(2).image.id, "frames must share an image")
local id = Profile.install(sprite, job(), true)
Edit.replaceFont(sprite, layer, id)
assert(Model.meta(layer).fontProfileId == id and #Validate.run(sprite) == 0)
assert(layer:cel(1).image.id == layer:cel(2).image.id, "replacement must preserve linked cels")
for _, cel in ipairs(layer.cels) do
  local meta = Profile.decode(layer, cel.image:getPixel(0, 0))
  assert(meta and meta.glyphKey == "A")
end
sprite:close()
controller:close()
print("PASS replacement remaps linked cels")
