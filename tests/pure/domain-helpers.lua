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
end
