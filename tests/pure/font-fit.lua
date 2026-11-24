return function(test)
  local Metrics = require("src.core.metrics")
  local Loader = require("src.fonts.loader")

  local function glyph(key, width, height)
    return {
      glyphKey = key,
      advance = 8,
      xMin = 0,
      xMax = width,
      yMin = 0,
      yMax = height,
      contours = { {} },
    }
  end

  test("font fitting preserves aspect ratio and prioritizes used glyphs", function()
    local font = { unitsPerEm = 8, ascender = 8, descender = 0 }
    local glyphs = { glyph("A", 6, 8), glyph("Z", 12, 8) }
    local function fit(width, height, preferred, primary)
      return Metrics.fit(font, glyphs, {
        pixelSize = preferred,
        cellWidth = width,
        cellHeight = height,
      }, primary)
    end
    local p, clipped = fit(8, 8, 8, { A = true })
    assert(p.pixelSize == 8 and clipped == 0 and p.clippedGlyphs == 1)
    p, clipped = fit(8, 8, 8, { Z = true })
    assert(p.pixelSize < 8 and clipped == 0)
    p = fit(8, 16, 8, { A = true })
    assert(p.pixelSize == 8)
    p = fit(3, 8, 8, { A = true })
    assert(p.pixelSize < 8)
    p, clipped = fit(1, 1, 8, { Z = true })
    assert(p.pixelSize == 1 and clipped > 0)
  end)

  test("automatic fit prepares required characters and preserves missing glyphs", function()
    local missing = utf8.char(0x10ffff)
    local control = utf8.char(0x80)
    local job = Loader.bundled("unscii-8", {
      pixelSize = 8,
      cellWidth = 8,
      cellHeight = 8,
      fit = { characters = { "A", control, missing } },
    })
    local found = {}
    for _, item in ipairs(job.glyphs) do
      found[item.glyphKey] = item
    end
    assert(found[control] and not found[control].renderFallback)
    assert(found[missing] and found[missing].renderFallback)
    assert(job.fit.primarySupported > 0)
    assert(job.fit.primaryClipped == 0)
    local empty = Loader.bundled("atascii", {
      pixelSize = 8,
      cellWidth = 8,
      cellHeight = 8,
      fit = { characters = {} },
    })
    assert(empty.profile.pixelSize == 8)
    local unsupported = Loader.bundled("atascii", {
      pixelSize = 8,
      cellWidth = 8,
      cellHeight = 8,
      fit = { characters = { missing } },
    })
    assert(unsupported.fit.primarySupported == 0 and unsupported.fit.primaryClipped == 0)
    assert(unsupported.profile.pixelSize == 8)
  end)

  test("automatic fit handles a font with no printable ASCII outlines", function()
    local font = { unitsPerEm = 8, ascender = 8, descender = 0, displayName = "Sample" }
    function font:characters()
      return { glyph("é", 6, 8) }
    end
    local job = Loader.candidate(
      { bytes = "", font = font, sourceHash = "0" },
      "Sample",
      { pixelSize = 8, cellWidth = 8, cellHeight = 8, fit = { characters = {} } },
      { kind = "bundled", id = "atascii" }
    )
    assert(job.fit.primarySupported == 0)
    assert(job.fit.primaryClipped == 0 and job.profile.pixelSize == 8)
  end)
end
