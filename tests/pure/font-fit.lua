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

  test("font measurement keeps fractional bounds without adding empty pixels", function()
    for _, size in ipairs({ 8, 12, 14, 16, 28 }) do
      local p = Loader.bundled("atascii", { pixelSize = size }).profile
      assert(p.cellWidth == size and p.cellHeight == size and p.clippedGlyphs == 0)
    end
    local square = Loader.bundled("atascii", { pixelSize = 12 }).profile
    assert(square.baseline == 10.5)
    for _, size in ipairs({ 8, 12, 16, 24 }) do
      local p = Loader.bundled("bescii", { pixelSize = size }).profile
      assert(p.cellWidth == size and p.cellHeight == size and p.clippedGlyphs == 0)
    end
  end)

  test("zero-advance glyphs use their outline position without inflating the cell", function()
    local font = { unitsPerEm = 8, ascender = 8, descender = 0 }
    local base, within, negative = glyph("A", 8, 8), glyph("B", 3, 6), glyph("C", -1, 6)
    within.advance, within.xMin, within.xMax = 0, 1, 3
    negative.advance, negative.xMin, negative.xMax = 0, -3, -1
    local p = Metrics.measure(font, { base, within, negative }, { pixelSize = 8 })
    assert(p.cellWidth == 8 and p.cellHeight == 8 and p.clippedGlyphs == 0)
    assert(within.offsetX == 0 and negative.offsetX == 6)
    assert(within.advance == 0 and negative.advance == 0)
    local onlyMark = Metrics.measure(font, { within }, { pixelSize = 8 })
    assert(
      onlyMark.advance == 8 and onlyMark.cellWidth == 8 and not Metrics.isClipped(onlyMark, within)
    )
  end)

  test("font measurement preserves real overhangs and fractional origins", function()
    local font = { unitsPerEm = 8, ascender = 7, descender = -1 }
    local overhang = glyph("A", 8, 7)
    overhang.xMin, overhang.xMax, overhang.yMin = -1, 8.00001, -1
    local p = Metrics.measure(font, { overhang }, { pixelSize = 12 })
    assert(p.cellWidth == 14 and p.cellHeight == 12)
    assert(p.originX == 1.5 and p.baseline == 10.5 and p.clippedGlyphs == 0)
    local limited = Metrics.measure(font, { overhang }, { pixelSize = 12, cellWidth = 13 })
    assert(limited.clippedGlyphs == 1)
  end)

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
