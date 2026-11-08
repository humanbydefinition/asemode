return function(test)
  test("default stamps prefer supported glyphs and preserve fallback order", function()
    local oldApp = app
    local oldProfile, oldTransforms =
      package.loaded["src.document.profile"], package.loaded["src.document.transforms"]
    app = { pixelColor = { TILE_XFLIP = 1, TILE_YFLIP = 2, TILE_DFLIP = 4 } }
    package.loaded["src.document.profile"], package.loaded["src.document.transforms"] = nil, nil
    local Profile = require("src.document.profile")
    local glyphs = {
      { glyphKey = "0", renderFallback = "space" },
      { glyphKey = "A" },
      { glyphKey = "B" },
    }
    local first, second = Profile.defaultStamps(glyphs)
    assert(first == "A" and second == "B")
    first, second = Profile.defaultStamps({
      glyphs = { ["0"] = { meta = { renderFallback = "space" } } },
      order = { "0", "Z" },
      supportedOrder = {},
    }, true)
    assert(first == "0" and second == "Z")
    local countOk, bytesOk = Profile.checkVariantBudget(65535, 1, 1)
    assert(not countOk and bytesOk)
    countOk, bytesOk = Profile.checkVariantBudget(511, 256, 256)
    assert(countOk and not bytesOk)
    local Transforms = require("src.document.transforms")
    assert(Transforms.validFlags(7) and not Transforms.validFlags(8))
    assert(not Transforms.validFlags(-1) and not Transforms.validFlags(1.5))
    package.loaded["src.document.profile"], package.loaded["src.document.transforms"] =
      oldProfile, oldTransforms
    app = oldApp
  end)

  test("remapping decodes linked images once before replacing them", function()
    local names = {
      "src.document.edit",
      "src.document.model",
      "src.document.profile",
      "src.document.validate",
      "src.fonts.loader",
      "src.document.stamp_state",
    }
    local saved = {}
    for _, name in ipairs(names) do
      saved[name] = package.loaded[name]
    end
    local oldApp = app
    app = { pixelColor = {} }
    local decoded = 0
    package.loaded["src.document.model"] = {
      meta = function()
        return { fontProfileId = "source" }
      end,
    }
    package.loaded["src.document.profile"] = {
      decode = function(_, value)
        if value == 0 then
          return nil, 0
        end
        decoded = decoded + 1
        return { glyphKey = "A", foregroundRGBA = "fg", backgroundRGBA = "bg" }, value
      end,
      orientedTile = function(_, id, glyph, fg, bg, flags)
        assert(id == "target" and glyph == "A" and fg == "fg" and bg == "bg")
        return flags + 100
      end,
    }
    package.loaded["src.document.validate"] = {}
    package.loaded["src.fonts.loader"] = {}
    package.loaded["src.document.stamp_state"] = {}
    package.loaded["src.document.edit"] = nil
    local Edit = require("src.document.edit")
    local function image(id, values)
      local result = { id = id, values = values }
      function result:clone()
        return image(self.id, { table.unpack(self.values) })
      end
      function result:pixels()
        local i = 0
        return function()
          i = i + 1
          if i > #self.values then
            return nil
          end
          local index = i
          return function(value)
            if value ~= nil then
              self.values[index] = value
            end
            return self.values[index]
          end
        end
      end
      return result
    end
    local shared = image(1, { 3, 3, 0 })
    local first, linked = { image = shared }, { image = shared }
    local other = { image = image(2, { 3, 4 }) }
    local layer = { cels = { first, linked, other } }
    Edit.remapLayers({}, { { layer = layer, id = "source", targetId = "target" } }, function(flags)
      return flags + 10
    end)
    assert(first.image.values[1] == 113 and first.image.values[2] == 113)
    assert(other.image.values[1] == 113 and other.image.values[2] == 114 and decoded == 2)
    assert(linked.image == shared, "only one linked cel should be assigned")
    for _, name in ipairs(names) do
      package.loaded[name] = saved[name]
    end
    app = oldApp
  end)

  test("portable import reports native limits during read and direct preparation", function()
    local names = {
      "src.document.portable_import",
      "src.document.model",
      "src.document.profile",
      "src.fonts.loader",
      "src.document.transforms",
      "src.document.blend",
    }
    local saved = {}
    for _, name in ipairs(names) do
      saved[name] = package.loaded[name]
    end
    package.loaded["src.document.model"] = {}
    package.loaded["src.document.profile"] = {}
    package.loaded["src.fonts.loader"] = { ensureCharacters = function() end }
    package.loaded["src.document.transforms"] = {}
    package.loaded["src.document.blend"] = {
      blend = function(mode)
        if mode == "multiply" then
          error("unsupported")
        end
        return 0
      end,
    }
    package.loaded["src.document.portable_import"] = nil
    local Import = require("src.document.portable_import")
    local JSON = require("src.portable.json")
    local file = assert(io.open("tests/fixtures/portable/v4-single-layer.json", "rb"))
    local document = JSON.parse(file:read("*a"))
    file:close()
    document.frames[1].durationMs = 0.5
    local result = Import.read(JSON.stringify(document))
    assert(not result.ok and result.error.code == "INVALID_DURATION")
    document.frames[1].durationMs = 100
    local validated = Import.read(JSON.stringify(document))
    assert(validated.ok)
    validated.document.frames[1].layers[1].cells.rows[1][1].transform.invert = true
    local prepared, changedError = pcall(
      Import.prepareImport,
      validated.document,
      { jobs = { {} } },
      { mode = "new" }
    )
    assert(not prepared and tostring(changedError):find("UNSUPPORTED_CELL_TRANSFORM", 1, true))
    document.frames[1].layers[1].cells.rows[1][1].transform.invert = true
    result = Import.read(JSON.stringify(document))
    assert(not result.ok and result.error.code == "UNSUPPORTED_CELL_TRANSFORM")
    assert(result.error.path:match("%.transform%.invert$"))
    local ok, err = pcall(Import.prepareImport, document, { jobs = { {} } }, { mode = "new" })
    assert(not ok and tostring(err):find("UNSUPPORTED_CELL_TRANSFORM", 1, true))
    document.frames[1].layers[1].blendMode = "multiply"
    result = Import.read(JSON.stringify(document))
    assert(not result.ok and result.error.code == "UNSUPPORTED_BLEND_MODE")
    ok, err = pcall(Import.prepareImport, document, { jobs = { {} } }, { mode = "new" })
    assert(not ok and tostring(err):find("UNSUPPORTED_CELL_TRANSFORM", 1, true))
    for _, name in ipairs(names) do
      package.loaded[name] = saved[name]
    end
  end)

  test("menu registration preserves command order and stamp action bindings", function()
    local events, actions = {}, {}
    local controller = {
      document = {},
      portable = {},
      font = {},
      drawing = {
        runAction = function(_, id)
          actions[#actions + 1] = id
        end,
        canRunAction = function()
          return true
        end,
      },
      guard = function(_, fn)
        return fn
      end,
      start = function() end,
      close = function() end,
    }
    local modules = {
      ["src.ui.controller"] = {
        new = function()
          return controller
        end,
      },
      ["src.document.model"] = {},
      ["src.actions.stamps"] = {
        definitions = {
          { command = "FirstStamp", title = "First", id = "first" },
          { command = "SecondStamp", title = "Second", id = "second" },
        },
      },
    }
    local env = setmetatable({
      app = { apiVersion = 41, version = 2 },
      Version = function()
        return 1
      end,
      require = function(name)
        return assert(modules[name])
      end,
    }, { __index = _G })
    assert(loadfile("src/main.lua", "t", env))()
    local plugin = {
      newMenuGroup = function(_, entry)
        events[#events + 1] = entry
      end,
      newCommand = function(_, entry)
        events[#events + 1] = entry
      end,
    }
    env.init(plugin)
    local ids = {}
    for _, event in ipairs(events) do
      ids[#ids + 1] = event.id
    end
    assert(table.concat(ids, ",") == table.concat({
      "asemode_menu",
      "AsemodeNew",
      "AsemodeImport",
      "AsemodePanel",
      "AsemodeLayer",
      "asemode_stamps",
      "FirstStamp",
      "SecondStamp",
      "asemode_selection",
      "AsemodeReplace",
      "AsemodeCopyCells",
      "AsemodePasteCells",
      "AsemodeFont",
      "AsemodeRegrid",
      "AsemodeExport",
      "AsemodeSettings",
      "AsemodeKeyboardShortcuts",
      "AsemodeCredits",
    }, ","))
    events[7].onclick()
    events[8].onclick()
    assert(actions[1] == "first" and actions[2] == "second")
    env.exit(plugin)
  end)

  test("orientedTile bakes transformed variants for square and non-square profiles", function()
    local oldApp, oldImage, oldColorMode, oldJson = app, Image, ColorMode, json
    local oldProfile, oldTransforms =
      package.loaded["src.document.profile"], package.loaded["src.document.transforms"]
    local JSON = require("src.portable.json")
    json = { encode = JSON.stringify, decode = JSON.parse }
    local U = require("src.core.util")
    local pc = {
      TILE_XFLIP = 0x10000000,
      TILE_YFLIP = 0x20000000,
      TILE_DFLIP = 0x40000000,
      tile = function(ti, flags)
        return ti | flags
      end,
      tileI = function(value)
        return value & 0x1fffffff
      end,
      tileF = function(value)
        return value & 0xe0000000
      end,
      rgba = function(r, g, b, a)
        return r | (g << 8) | (b << 16) | (a << 24)
      end,
      rgbaA = function(c)
        return (c >> 24) & 0xff
      end,
    }
    app = {
      pixelColor = pc,
      transaction = function(_, fn)
        fn()
      end,
    }
    Image = function(w, h, _)
      local pixels = {}
      return {
        width = w,
        height = h,
        bytes = string.rep("\0", w * h * 4),
        getPixel = function(_, x, y)
          return pixels[x .. ":" .. y] or 0xffffffff
        end,
        drawPixel = function(_, x, y, c)
          pixels[x .. ":" .. y] = c
        end,
      }
    end
    ColorMode = { RGB = 1 }
    package.loaded["src.document.profile"] = nil
    package.loaded["src.document.transforms"] = nil
    local Profile = require("src.document.profile")
    local function withProps(t, initial)
      local stored = initial or {}
      t.properties = function(namespace, value)
        assert(namespace == "asemode")
        if value then
          stored = value
        end
        return stored
      end
      return setmetatable(t, {
        __len = function(self)
          return (self.tiles and #self.tiles or 0) + 1
        end,
      })
    end

    local paintTileset = withProps({
      true,
      tiles = {},
      name = "paint",
    }, { schemaVersion = 1, fontProfileId = "p1", role = "paint" })
    function paintTileset:tile(i)
      return self.tiles[i]
    end

    local maskTile = withProps({
      image = Image(8, 8, 1),
    }, {
      schemaVersion = 1,
      glyphKey = "E",
      imageHash = U.hash(string.rep("\0", 8 * 8 * 4)),
      fontProfileId = "p1",
    })

    local masksTileset = withProps({
      true,
      true,
      tiles = { [1] = maskTile },
      name = "masks",
    }, {
      schemaVersion = 1,
      fontProfileId = "p1",
      role = "masks",
      profileJson = '{"cellWidth":8,"cellHeight":8,"name":"Test"}',
    })
    function masksTileset:tile(i)
      return self.tiles[i]
    end

    local sprite = {
      tilesets = {
        masksTileset,
        paintTileset,
      },
      newTile = function(_, ts)
        table.insert(ts, true)
        local t = withProps({ index = #ts.tiles + 1 })
        ts.tiles[t.index] = t
        return t
      end,
    }

    local flags = pc.TILE_XFLIP
    local tileVal = Profile.orientedTile(sprite, "p1", "E", "#ffffffff", "#000000ff", flags)
    assert(tileVal == 1, "expected first variant at index 1 with 0 native flags")
    local createdTile = paintTileset:tile(1)
    local Base = require("src.document.base")
    local createdMeta = Base.meta(createdTile)
    assert(createdMeta and createdMeta.schemaVersion == 2, "tile must have schemaVersion 2")
    assert(createdMeta.orientation == flags, "tile must have orientation recorded in metadata")

    local layer = { tileset = paintTileset }
    local decodedMeta, decodedFlags = Profile.decode(layer, tileVal)
    assert(decodedMeta and decodedMeta.glyphKey == "E")
    assert(decodedFlags == flags, "decoded orientation flags must match baked orientation")

    package.loaded["src.document.profile"], package.loaded["src.document.transforms"] =
      oldProfile, oldTransforms
    app, Image, ColorMode, json = oldApp, oldImage, oldColorMode, oldJson
  end)
end
