return function(test)
  test(
    "requested mapped control characters use real glyphs and missing characters fall back",
    function()
      local Loader = require("src.fonts.loader")
      local Metrics = require("src.core.metrics")
      local function find(job, key)
        for _, glyph in ipairs(job.glyphs) do
          if glyph.glyphKey == key then
            return glyph
          end
        end
      end
      local rook = Loader.bundled("rook", { pixelSize = 16, cellWidth = 16, cellHeight = 16 })
      local carriageReturn, unavailable = "\r", utf8.char(0x10ffff)
      assert(not find(rook, carriageReturn))
      local originalCount = #rook.glyphs
      local originalWidth, originalBaseline = rook.profile.cellWidth, rook.profile.baseline
      local existingMask = {}
      rook.masks[1], rook.position = existingMask, 1
      local missing = Loader.ensureCharacters(rook, { carriageReturn, unavailable })
      assert(#missing == 1 and missing[1] == unavailable)
      local cr = assert(find(rook, carriageReturn))
      assert(cr.glyphIndex == 1 and not cr.renderFallback and #cr.contours == 0)
      assert(find(rook, unavailable).renderFallback == "space")
      assert(#rook.glyphs == originalCount + 2)
      assert(rook.profile.cellWidth == originalWidth and rook.profile.baseline == originalBaseline)
      assert(rook.position == 1 and rook.masks[1] == existingMask)
      Loader.ensureCharacters(rook, { carriageReturn, unavailable })
      assert(#rook.glyphs == originalCount + 2)

      local unscii = Loader.bundled("unscii-8", { pixelSize = 16, cellWidth = 1, cellHeight = 1 })
      local key = utf8.char(0x80)
      assert(not find(unscii, key))
      local clippedBefore = unscii.profile.clippedGlyphs
      assert(#Loader.ensureCharacters(unscii, { key }) == 0)
      local glyph = assert(find(unscii, key))
      assert(not glyph.renderFallback and #glyph.contours > 0)
      assert(Metrics.isClipped(unscii.profile, glyph))
      assert(unscii.profile.clippedGlyphs == clippedBefore + 1)

      local bitmap = Loader.job(
        { kind = "bitmap", cellWidth = 8, cellHeight = 8, scale = 1, clippedGlyphs = 0 },
        {},
        function()
          return {}
        end
      )
      local bitmapMissing = Loader.ensureCharacters(bitmap, { "A" })
      assert(#bitmapMissing == 1 and bitmapMissing[1] == "A")
      assert(bitmap.glyphs[1].renderFallback == "space")
    end
  )

  test("import warns only when the selected font lacks a requested glyph", function()
    local Loader = require("src.fonts.loader")
    local U = require("src.core.util")
    local JSON = require("src.portable.json")
    local names = {
      "src.document.portable_import",
      "src.document.model",
      "src.document.profile",
      "src.document.transforms",
      "src.document.blend",
    }
    local saved, oldApp, oldImage, oldColorMode = {}, app, Image, ColorMode
    for _, name in ipairs(names) do
      saved[name] = package.loaded[name]
    end
    app = { pixelColor = {
      tile = function(index)
        return index
      end,
    } }
    Image = function()
      return { drawPixel = function() end }
    end
    ColorMode = { TILEMAP = 1 }
    package.loaded["src.document.model"] = {}
    package.loaded["src.document.profile"] = {
      checkVariantBudget = function()
        return true, true
      end,
      colorize = function()
        return {}
      end,
    }
    package.loaded["src.document.transforms"] = {
      portableToNative = function()
        return 0
      end,
      quantizeRotation = function(rotation)
        return rotation
      end,
    }
    package.loaded["src.document.blend"] = {
      blend = function()
        return 0
      end,
    }
    package.loaded["src.document.portable_import"] = nil
    local ok, err = xpcall(function()
      local Import = require("src.document.portable_import")
      local function prepare(fontId, character)
        local document = JSON.parse(U.read("tests/fixtures/portable/v4-single-layer.json"))
        local layer = document.frames[1].layers[1]
        local raw = Loader.bundled(fontId, { pixelSize = 8, cellWidth = 8, cellHeight = 8 })
        layer.font = { id = raw.profile.portableFont.id }
        for _, row in ipairs(layer.cells.rows) do
          for _, cell in ipairs(row) do
            cell.character = character
          end
        end
        local job = {
          profile = raw.profile,
          glyphs = raw.glyphs,
          resolveCharacters = raw.resolveCharacters,
          masks = {},
          position = 0,
        }
        function job:step()
          for i = self.position + 1, #self.glyphs do
            self.masks[i] = {}
          end
          self.position = #self.glyphs
        end
        local plan = Import.prepareImport(document, { jobs = { job } }, { mode = "new" })
        for _, diagnostic in ipairs(plan.diagnostics) do
          if diagnostic.code == "MISSING_GLYPHS_AS_SPACES" then
            return true
          end
        end
        return false
      end
      assert(not prepare("rook", "\r"))
      assert(not prepare("unscii-8", utf8.char(0x80)))
      assert(prepare("rook", utf8.char(0x10ffff)))
    end, debug.traceback)
    app, Image, ColorMode = oldApp, oldImage, oldColorMode
    for _, name in ipairs(names) do
      package.loaded[name] = saved[name]
    end
    assert(ok, err)
  end)
end
