return function(test)
  local previousApp, previousColorMode = app, ColorMode
  local previousModel = package.loaded["src.document.model"]
  local previousProfile = package.loaded["src.document.profile"]
  app = {
    pixelColor = {
      TILE_XFLIP = 0x10000000,
      TILE_YFLIP = 0x20000000,
      TILE_DFLIP = 0x40000000,
      tileI = function(value)
        return value & 0xffff
      end,
      tileF = function(value)
        return value & 0x70000000
      end,
    },
  }
  ColorMode = { TILEMAP = 2 }
  local U = require("src.core.util")
  local model = {
    celOrigin = function(cel, geometry)
      return (cel.position.x - geometry.originX) // geometry.cellWidth,
        (cel.position.y - geometry.originY) // geometry.cellHeight
    end,
  }
  local profile = {}
  package.loaded["src.document.model"] = model
  package.loaded["src.document.profile"] = profile
  function model.meta(object)
    return object.meta or {}
  end

  function model.geometry(sprite)
    return sprite.geometry
  end

  function model.coverage()
    return { firstCol = 0, firstRow = 0, columns = 1, rows = 1 }
  end

  function model.layers(sprite)
    return sprite.layers
  end

  function model.layerManaged(layer)
    return layer.isTilemap and layer.meta.schemaVersion == 1
  end

  function model.textLayer(_, layer)
    return model.layerManaged(layer)
  end

  function model.editable()
    return "font"
  end

  function profile.invalidate() end
  function profile.profiles(sprite)
    return { { id = "font", profile = sprite.index.profile } }
  end

  function profile.index(sprite)
    return sprite.index
  end

  function profile.decode(layer, value)
    local tile = layer.tileset:tile(value)
    return tile and tile.meta, 0
  end
  local Validate = require("src.document.validate")
  local Snapshot = require("src.document.snapshot")
  local Edit = require("src.document.edit")

  local function fixture()
    local function image(bytes)
      return {
        width = 8,
        height = 8,
        bytes = bytes,
        isEmpty = function()
          return bytes == ""
        end,
      }
    end

    local function tileset(role)
      local tile = {
        image = image(role),
        meta = {
          schemaVersion = 1,
          glyphKey = "A",
          imageHash = U.hash(role),
          fontProfileId = "font",
          foregroundRGBA = "#ffffffff",
          backgroundRGBA = "#00000000",
        },
      }
      local ts = {
        true,
        true,
        name = role,
        meta = { fontProfileId = "font", role = role },
        grid = { tileSize = { width = 8, height = 8 } },
        tiles = { [0] = { image = image("") }, [1] = tile },
      }
      function ts:tile(i)
        return self.tiles[i]
      end
      return ts, tile
    end
    local masks = tileset("masks")
    local paint, paintTile = tileset("paint")
    local tileImage = { colorMode = ColorMode.TILEMAP, width = 1, height = 1, value = 1 }
    function tileImage:pixels()
      local done = false
      return function()
        if done then
          return nil
        end
        done = true
        return setmetatable({ x = 0, y = 0 }, {
          __call = function()
            return self.value
          end,
        })
      end
    end

    function tileImage:getPixel()
      return self.value
    end
    local cel = { frameNumber = 1, position = { x = 0, y = 0 }, image = tileImage }
    local layer = {
      name = "Text",
      isTilemap = true,
      meta = { schemaVersion = 1, fontProfileId = "font" },
      tileset = paint,
      cels = { cel },
    }
    function layer:cel(frame)
      return frame == 1 and cel or nil
    end
    local sprite = {
      geometry = { cellWidth = 8, cellHeight = 8, originX = 0, originY = 0 },
      index = {
        profile = { name = "Font", cellWidth = 8, cellHeight = 8 },
        masks = masks,
        paint = paint,
        glyphs = { A = true },
        order = { "A" },
      },
      layers = { layer },
      frames = { true },
    }
    return sprite, layer, cel, paintTile
  end

  test("valid text data passes validation and snapshot export", function()
    local sprite, layer = fixture()
    assert(#Validate.run(sprite, layer) == 0)
    Validate.requireValid(sprite, layer)
    assert(Edit.insert(sprite, layer, 1, "", 0, 0) == 0)
    local snapshot = Snapshot.capture(sprite, { layer }, 1)
    assert(snapshot.layers[1].rows[1][1].meta.glyphKey == "A")
  end)

  test("edited tile pixels block editing and export", function()
    local sprite, layer, _, tile = fixture()
    tile.image.bytes = "edited"
    local issues = Validate.run(sprite, layer)
    assert(Validate.text(issues):find("Glyph pixels were edited", 1, true))
    local ok, err = pcall(Edit.insert, sprite, layer, 1, "A", 0, 0)
    assert(not ok and tostring(err):find("Glyph pixels were edited", 1, true))
    ok, err = pcall(Snapshot.capture, sprite, { layer }, 1)
    assert(not ok and tostring(err):find("Glyph pixels were edited", 1, true))
  end)

  test("foreign tiles and off-grid cels identify their location", function()
    local sprite, layer, cel, tile = fixture()
    tile.meta.glyphKey = nil
    cel.position.x = 1
    local text = Validate.text(Validate.run(sprite, layer))
    assert(text:find("Missing glyph metadata", 1, true))
    assert(text:find("Text: Foreign tile in frame 1 at cell 0,0", 1, true))
    assert(text:find("Text: Cel is not aligned in frame 1", 1, true))
    assert(not pcall(Snapshot.capture, sprite, { layer }, 1))
  end)

  test("oriented tile variants pass validation on square and non-square fonts", function()
    local sprite, layer, _, tile = fixture()
    tile.meta.schemaVersion = 2
    tile.meta.orientation = app.pixelColor.TILE_XFLIP
    assert(#Validate.run(sprite, layer) == 0)
    Validate.requireValid(sprite, layer)
  end)

  -- Teardown: restore document modules and host environment
  package.loaded["src.document.validate"] = nil
  package.loaded["src.document.snapshot"] = nil
  package.loaded["src.document.edit"] = nil
  package.loaded["src.document.model"] = previousModel
  package.loaded["src.document.profile"] = previousProfile
  app, ColorMode = previousApp, previousColorMode
end
