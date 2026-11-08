-- Shared fixture files and deterministic sprite/layer state helpers for screenshot suites.
local U = require("src.core.util")
local Loader = require("src.fonts.loader")
local Model = require("src.document.model")
local Profile = require("src.document.profile")

local M = {}

function M.setup(controller, root, output)
  local sampleFontPath = output .. "/sample-user-font.ttf"
  local blankJsonPath = output .. "/blank.textmode.json"
  local warningsJsonPath = output .. "/warnings.textmode.json"

  U.write(sampleFontPath, Loader.resource("atascii").bytes)
  U.write(
    blankJsonPath,
    '{"format":"textmode.document","formatVersion":"4.0.0","frames":[{"durationMs":100,"layers":[]}]}'
  )

  local warningCell =
    '{"x":0,"y":0,"character":"\\u2603","foreground":"#ffffffff","background":"#000000ff","transform":{"invert":false,"flipX":false,"flipY":false,"rotation":30}}'
  local warningDoc = table.concat({
    '{"format":"textmode.document","formatVersion":"4.0.0","frames":[',
    '{"durationMs":100,"layers":[',
    '{"id":"Bad\\u0001Name","visible":true,"opacity":0.5,"blendMode":"normal","offsetX":4,"offsetY":0,"rotationZ":0,',
    '"font":{"id":"invalid-font-id","name":"BadFont"},',
    '"grid":{"cols":1,"rows":1,"cellWidth":8,"cellHeight":8},',
    '"cells":{"encoding":"object-rows-v1","rows":[[' .. warningCell .. "]]}},",
    '{"id":"Layer 2","visible":true,"opacity":1,"blendMode":"normal","offsetX":0,"offsetY":0,"rotationZ":0,',
    '"grid":{"cols":1,"rows":1,"cellWidth":8,"cellHeight":8},',
    '"cells":{"encoding":"object-rows-v1","rows":[[' .. warningCell .. "]]}}",
    "]},",
    '{"durationMs":100,"layers":[',
    '{"id":"Bad\\u0001Name","visible":true,"opacity":1,"blendMode":"normal","offsetX":0,"offsetY":0,"rotationZ":0,',
    '"grid":{"cols":2,"rows":1,"cellWidth":8,"cellHeight":8},',
    '"cells":{"encoding":"object-rows-v1","rows":[[',
    warningCell,
    ',{"x":1,"y":0,"character":"A","foreground":"#ffffffff","background":"#000000ff","transform":{"invert":false,"flipX":false,"flipY":false,"rotation":0}}]]}}',
    "]}]}",
  })
  U.write(warningsJsonPath, warningDoc)

  local job = controller.library
    :job({ kind = "bundled", id = "atascii" }, { pixelSize = 8 })
    :finish()
  local sprite, layer = Model.create(job, 24, 16, false, "white")
  app.sprite, app.layer = sprite, layer
  sprite.selection:select(Rectangle(0, 0, 32, 32))

  local cel = layer:cel(app.frame)
    or sprite:newCel(layer, app.frame, Image(24, 16, ColorMode.TILEMAP), Point(0, 0))
  local savedLayerMeta = U.copy(Model.meta(layer))

  local fixtures = {
    root = root,
    output = output,
    job = job,
    sprite = sprite,
    layer = layer,
    cel = cel,
    savedLayerMeta = savedLayerMeta,
    sampleFontPath = sampleFontPath,
    blankJsonPath = blankJsonPath,
    warningsJsonPath = warningsJsonPath,
    exportJsonPath = root .. "/tests/fixtures/browser/export.textmode.json",
    legacyJsonPath = root .. "/tests/fixtures/portable/legacy-all-v1.1.json",
    missingJsonPath = output .. "/missing-artwork.textmode.json",
  }

  function fixtures:path(filename)
    return self.output .. "/" .. filename
  end

  function fixtures:refreshTiles()
    self.cel = self.layer:cel(app.frame)
      or self.sprite:newCel(self.layer, app.frame, Image(24, 16, ColorMode.TILEMAP), Point(0, 0))
    self.savedLayerMeta = U.copy(Model.meta(self.layer))
    local profileId = self.savedLayerMeta.fontProfileId
    Profile.ensureCharacters(self.sprite, profileId, { "\u{2603}" })
    self.profileId = profileId
    self.tileA = Profile.orientedTile(self.sprite, profileId, "A", "#ffffffff", "#000000ff", 0)
    self.tileB = Profile.orientedTile(self.sprite, profileId, "B", "#55aaffff", "#000000ff", 0)
    self.tileMissing =
      Profile.orientedTile(self.sprite, profileId, "\u{2603}", "#ffffffff", "#000000ff", 0)
  end

  function fixtures:clearCells()
    self:refreshTiles()
    self.cel.image:clear()
    self.cel.position = Point(0, 0)
  end

  function fixtures:populateSampleCells()
    self:clearCells()
    self.cel.image:putPixel(0, 0, self.tileA)
    self.cel.image:putPixel(1, 0, self.tileB)
    self.cel.image:putPixel(0, 1, self.tileB)
    self.cel.image:putPixel(1, 1, self.tileA)
  end

  function fixtures:reset()
    app.sprite, app.layer = self.sprite, self.layer
    self.layer.isEditable = true
    Model.setMeta(self.layer, U.copy(self.savedLayerMeta))
    Profile.invalidate()
    self.sprite.selection:select(Rectangle(0, 0, 32, 32))
    controller.plugin.preferences.newSpriteDefaults = nil
    controller.library.error = nil
    controller.tasks.active = nil
    self:populateSampleCells()
  end

  fixtures:populateSampleCells()
  return fixtures
end

return M
