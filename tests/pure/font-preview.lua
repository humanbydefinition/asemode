return function(test)
  local Preview = require("src.ui.font_preview")
  local Metrics = require("src.core.metrics")
  local profile = {
    kind = "truetype",
    cellWidth = 8,
    cellHeight = 8,
    originX = 0,
    baseline = 6,
    scale = 1,
  }
  local function glyph(key, xMax)
    return {
      glyphKey = key,
      contours = { {} },
      xMin = 0,
      xMax = xMax or 8,
      yMin = -2,
      yMax = 6,
      offsetX = 0,
    }
  end

  test("font preview prioritizes clipped outlines and representative glyphs", function()
    local glyphs = { glyph("!"), glyph("A"), glyph("g"), glyph("Z", 9) }
    local masks = { {}, {}, {}, {} }
    local job = { profile = profile, glyphs = glyphs, masks = masks }
    local sample = Preview.sample(job)
    assert(sample[1].key == "Z" and sample[1].clipped and sample[1].index == 4)
    assert(sample[2].key == "A" and sample[3].key == "g")
    assert(not sample[2].clipped and not Metrics.isClipped(profile, glyphs[2]))
    assert(job.masks == masks and job.glyphs == glyphs and glyphs[4].xMax == 9)
  end)

  test("outline fit checks every edge and ignores blank or fallback glyphs", function()
    local bounds = glyph("A")
    assert(not Metrics.isClipped(profile, bounds))
    for _, edge in ipairs({
      { "xMin", -1 },
      { "xMax", 9 },
      { "yMin", -3 },
      { "yMax", 7 },
    }) do
      local original = bounds[edge[1]]
      bounds[edge[1]] = edge[2]
      assert(Metrics.isClipped(profile, bounds))
      bounds[edge[1]] = original
    end
    bounds.xMax = 9
    bounds.renderFallback = "space"
    assert(not Metrics.isClipped(profile, bounds))
    bounds.renderFallback, bounds.contours = nil, {}
    assert(not Metrics.isClipped(profile, bounds))
  end)

  test("font preview skips missing and blank outlines and accepts bitmap glyphs", function()
    local job = {
      profile = profile,
      glyphs = {
        { glyphKey = "A", renderFallback = "space", contours = {} },
        { glyphKey = " ", contours = {} },
        { glyphKey = "B", contours = {} },
        { glyphKey = "g", sheetIndex = 0 },
      },
      masks = { {}, {}, {}, {} },
    }
    local sample = Preview.sample(job)
    assert(#sample == 1 and sample[1].key == "g" and not sample[1].clipped)
    job.glyphs[4].renderFallback = "space"
    assert(#Preview.sample(job) == 0)
  end)
end
