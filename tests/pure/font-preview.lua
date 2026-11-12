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
      { "xMin", -1, "left" },
      { "xMax", 9, "right" },
      { "yMin", -3, "bottom" },
      { "yMax", 7, "top" },
    }) do
      local original = bounds[edge[1]]
      bounds[edge[1]] = edge[2]
      assert(Metrics.isClipped(profile, bounds))
      local edges = Metrics.clippedEdges(profile, bounds)
      for _, name in ipairs({ "left", "right", "top", "bottom" }) do
        assert(edges[name] == (name == edge[3]))
      end
      bounds[edge[1]] = original
    end
    bounds.xMin, bounds.yMax, bounds.offsetX = -2, 7, 1
    local edges = Metrics.clippedEdges(profile, bounds)
    assert(edges.left and edges.right and edges.top and not edges.bottom)
    bounds.xMin, bounds.yMax, bounds.offsetX = 0, 6, 0
    bounds.xMax = 9
    bounds.renderFallback = "space"
    assert(not Metrics.isClipped(profile, bounds))
    assert(not Metrics.clippedEdges(profile, bounds).right)
    bounds.renderFallback, bounds.contours = nil, {}
    assert(not Metrics.isClipped(profile, bounds))
  end)

  test("font preview limits the sample and prioritizes clipping", function()
    local glyphs, masks = {}, {}
    for i = 1, 10 do
      glyphs[i], masks[i] = glyph(tostring(i), 9), {}
    end
    local sample = Preview.sample({ profile = profile, glyphs = glyphs, masks = masks })
    assert(#sample == 8)
    for i, item in ipairs(sample) do
      assert(item.index == i and item.clipped and item.edges.right)
    end
  end)

  test("ATASCII preview marks only the edges exceeded by each sampled outline", function()
    local job = require("src.fonts.loader").bundled("atascii", {
      pixelSize = 16,
      cellWidth = 8,
      cellHeight = 8,
    })
    for i in ipairs(job.glyphs) do
      job.masks[i] = {}
    end
    local sample = Preview.sample(job)
    assert(sample[1].key == "!" and sample[1].edges.right and sample[1].edges.bottom)
    assert(sample[2].key == '"' and sample[2].edges.right and not sample[2].edges.bottom)
    assert(sample[7].key == "'" and sample[7].edges.right and not sample[7].edges.bottom)
    for _, item in ipairs(sample) do
      assert(not item.edges.left and not item.edges.top)
    end
  end)

  test("font preview isolates overflow pixels and bounds extreme geometry", function()
    local oldApp, oldImage, oldMode = app, Image, ColorMode
    local Render = require("src.fonts.render")
    local oldMask = Render.mask
    local measured
    app = {
      pixelColor = {
        rgbaA = function(pixel)
          return pixel
        end,
        rgba = function(_, _, _, alpha)
          return alpha
        end,
      },
    }
    ColorMode = { RGB = 1 }
    Image = function(width, height)
      local image = { width = width, height = height, pixels = {} }
      function image:drawPixel(x, y, pixel)
        self.pixels[y * self.width + x] = pixel
      end
      return image
    end
    rawset(Render, "mask", function(_, measuredProfile)
      measured = measuredProfile
      return {
        getPixel = function()
          return 255
        end,
      }
    end)
    local g = glyph("A", 10)
    g.xMin, g.yMax, g.yMin = -2, 7, -3
    local job = { profile = profile, glyphs = { g } }
    local sample = { { index = 1, clipped = true } }
    local extent = Preview.prepare(job, sample)
    assert(extent.left == 2 and extent.right == 2 and extent.top == 1 and extent.bottom == 1)
    assert(not extent.truncated and measured.originX == 2 and measured.baseline == 7)
    local img = sample[1].overflow
    assert(img.width == 12 and img.height == 10)
    assert(img.pixels[0] == 255 and img.pixels[1 * img.width + 2] == nil)
    assert(img.pixels[1 * img.width + 10] == 255 and img.pixels[9 * img.width + 2] == 255)
    g.xMax = 10000
    local limited = Preview.prepare(job, sample)
    assert(limited.truncated and limited.right == 128 and sample[1].overflow.width == 138)
    rawset(Render, "mask", oldMask)
    app, Image, ColorMode = oldApp, oldImage, oldMode
  end)

  test("font preview draws overflow around the original cell mask", function()
    local oldRectangle = Rectangle
    Rectangle = function(x, y, width, height)
      return { x = x, y = y, width = width, height = height }
    end
    local calls = {}
    local gc = {
      width = Preview.WIDTH,
      height = Preview.HEIGHT,
      theme = { color = { editor_face = "background", selected = "border" } },
    }
    function gc:drawThemeRect() end
    function gc:fillRect() end
    function gc:strokeRect(rect)
      calls[#calls + 1] = { kind = "border", rect = rect, color = self.color }
    end
    function gc:drawImage(image, _, rect)
      calls[#calls + 1] = { kind = image.kind, rect = rect }
    end
    local overflow = { kind = "overflow", width = 12, height = 10 }
    local mask = { kind = "cell" }
    local extent = { left = 2, right = 2, top = 1, bottom = 1 }
    Preview.paint(gc, { profile = profile, masks = { mask } }, {
      { index = 1, overflow = overflow, padding = extent },
    }, extent)
    assert(
      #calls == 3
        and calls[1].kind == "border"
        and calls[2].kind == "overflow"
        and calls[3].kind == "cell"
    )
    assert(calls[1].color == "border")
    local outer, inner = calls[2].rect, calls[3].rect
    assert(outer.x < inner.x and outer.y < inner.y)
    assert(outer.x + outer.width > inner.x + inner.width)
    assert(outer.y + outer.height > inner.y + inner.height)
    Rectangle = oldRectangle
  end)

  test("unclipped preview uses the compact layout and theme border", function()
    local oldRectangle = Rectangle
    Rectangle = function(x, y, width, height)
      return { x = x, y = y, width = width, height = height }
    end
    local borders, baseline = {}, 0
    local gc = {
      width = Preview.COMPACT_WIDTH,
      height = Preview.COMPACT_HEIGHT,
      theme = {
        color = { editor_face = "surface", selected = "selection", button_selected_text = "text" },
      },
    }
    function gc:drawThemeRect() end
    function gc:drawImage() end
    function gc:strokeRect(rect)
      borders[#borders + 1] = { color = self.color, rect = rect }
    end
    function gc:fillRect()
      if self.color == "text" then
        baseline = baseline + 1
      end
    end
    local clean = { cellWidth = 8, cellHeight = 8, baseline = 6, clippedGlyphs = 0 }
    Preview.paint(gc, { profile = clean, masks = { {} } }, { { index = 1 } })
    assert(#borders == 1 and borders[1].color == "selection")
    assert(borders[1].rect.width == 26 and borders[1].rect.height == 26 and baseline == 2)
    Rectangle = oldRectangle
  end)

  test("font preview skips missing and blank outlines and accepts bitmap glyphs", function()
    local job = {
      profile = profile,
      glyphs = {
        { glyphKey = "A", renderFallback = "space", contours = {} },
        { glyphKey = " ", contours = {} },
        { glyphKey = "B", contours = {} },
        { glyphKey = "g", sheetIndex = 0 },
        { glyphKey = " ", contours = { {} }, xMin = 0, xMax = 9, yMin = -2, yMax = 6 },
      },
      masks = { {}, {}, {}, {}, {} },
    }
    local sample = Preview.sample(job)
    assert(#sample == 2 and sample[1].index == 5 and sample[1].edges.right)
    assert(sample[2].key == "g" and not sample[2].clipped)
    job.glyphs[4].renderFallback = "space"
    assert(#Preview.sample(job) == 1)
  end)
end
