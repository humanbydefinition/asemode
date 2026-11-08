return function(test)
  local oldApp, oldImage, oldColorMode, oldColor, oldMouse, oldJson =
    app, Image, ColorMode, Color, MouseButton, json
  local oldProfile = package.loaded["src.document.profile"]
  local oldStamps = package.loaded["src.actions.stamps"]

  local JSON = require("src.portable.json")
  json = { encode = JSON.stringify, decode = JSON.parse }
  local U = require("src.core.util")

  local pc = {
    TILE_XFLIP = 0x10000000,
    TILE_YFLIP = 0x20000000,
    TILE_DFLIP = 0x40000000,
    tile = function(ti, flags)
      return (ti or 0) | (flags or 0)
    end,
    tileI = function(value)
      return value & 0x1fffffff
    end,
    tileF = function(value)
      return value & 0xe0000000
    end,
    rgba = function(r, g, b, a)
      return (r & 0xff) | ((g & 0xff) << 8) | ((b & 0xff) << 16) | ((a & 0xff) << 24)
    end,
    rgbaR = function(c)
      return c & 0xff
    end,
    rgbaG = function(c)
      return (c >> 8) & 0xff
    end,
    rgbaB = function(c)
      return (c >> 16) & 0xff
    end,
    rgbaA = function(c)
      return (c >> 24) & 0xff
    end,
  }

  ColorMode = { RGB = 1 }
  MouseButton = { LEFT = 1, RIGHT = 2 }
  Color = function(r, g, b, a)
    if type(r) == "number" then
      return { red = r, green = g, blue = b, alpha = a }
    end
    return r
  end

  Image = function(w, h, _)
    local pixels = {}
    return {
      width = w,
      height = h,
      bytes = string.rep("\0", w * h * 4),
      clear = function(_, c)
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            pixels[x .. ":" .. y] = c
          end
        end
      end,
      getPixel = function(_, x, y)
        return pixels[x .. ":" .. y] or 0
      end,
      drawPixel = function(_, x, y, c)
        pixels[x .. ":" .. y] = c
      end,
    }
  end

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

  app = {
    pixelColor = pc,
    transaction = function(_, fn)
      fn()
    end,
  }

  package.loaded["src.document.profile"] = nil
  local Profile = require("src.document.profile")

  test(
    "Profile.colorize generates 4-way circle and 8-way square outlines with transparent background",
    function()
      -- Create an 8x8 mask with a single opaque pixel at (3, 3)
      local mask = Image(8, 8, ColorMode.RGB)
      mask:clear(pc.rgba(0, 0, 0, 0))
      mask:drawPixel(3, 3, pc.rgba(255, 255, 255, 255))

      local fg = "#ffffffff" -- White glyph
      local bg = "#ff0000ff" -- Red outline

      -- Test 4-way circle outline
      local circleImg = Profile.colorize(mask, fg, bg, "circle")
      assert(circleImg.width == 8 and circleImg.height == 8)
      -- Center must be white (foreground)
      local center = circleImg:getPixel(3, 3)
      assert(
        pc.rgbaR(center) == 255
          and pc.rgbaG(center) == 255
          and pc.rgbaB(center) == 255
          and pc.rgbaA(center) == 255
      )
      -- 4 orthogonal neighbors must be red outline (background)
      for _, offset in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local p = circleImg:getPixel(3 + offset[1], 3 + offset[2])
        assert(
          pc.rgbaR(p) == 255 and pc.rgbaG(p) == 0 and pc.rgbaB(p) == 0 and pc.rgbaA(p) == 255,
          "circle neighbor must be red"
        )
      end
      -- Diagonals must be transparent in circle mode
      for _, offset in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        local p = circleImg:getPixel(3 + offset[1], 3 + offset[2])
        assert(pc.rgbaA(p) == 0, "circle diagonal must be transparent")
      end
      -- Distant pixel (0, 0) must be transparent
      assert(pc.rgbaA(circleImg:getPixel(0, 0)) == 0)

      -- Test 8-way square outline
      local squareImg = Profile.colorize(mask, fg, bg, "square")
      -- Center must be white
      center = squareImg:getPixel(3, 3)
      assert(pc.rgbaR(center) == 255 and pc.rgbaG(center) == 255 and pc.rgbaB(center) == 255)
      -- All 8 neighbors must be red outline
      for _, offset in ipairs({
        { -1, 0 },
        { 1, 0 },
        { 0, -1 },
        { 0, 1 },
        { -1, -1 },
        { 1, -1 },
        { -1, 1 },
        { 1, 1 },
      }) do
        local p = squareImg:getPixel(3 + offset[1], 3 + offset[2])
        assert(
          pc.rgbaR(p) == 255 and pc.rgbaG(p) == 0 and pc.rgbaB(p) == 0 and pc.rgbaA(p) == 255,
          "square neighbor must be red"
        )
      end
      -- Distant pixel (0, 0) must be transparent
      assert(pc.rgbaA(squareImg:getPixel(0, 0)) == 0)

      -- Test standard non-outlined colorize
      local plainImg = Profile.colorize(mask, fg, bg, "none")
      -- Distant pixel (0, 0) must have solid background (red)
      local distant = plainImg:getPixel(0, 0)
      assert(
        pc.rgbaR(distant) == 255
          and pc.rgbaG(distant) == 0
          and pc.rgbaB(distant) == 0
          and pc.rgbaA(distant) == 255
      )
    end
  )

  test(
    "Profile.variant and Profile.decode handle outlined tile variants with schemaVersion 3",
    function()
      local Base = require("src.document.base")
      local paintTiles = {}
      local paintTileset = withProps({
        name = "Asemode paint: TestFont",
        tile = function(self, index)
          return paintTiles[index]
        end,
        tiles = paintTiles,
      })
      local maskTile = withProps({
        image = Image(8, 8, ColorMode.RGB),
      })
      maskTile.image:clear(pc.rgba(255, 255, 255, 255))
      local maskTileset = withProps({
        name = "Asemode masks: TestFont",
        tile = function(self, index)
          return maskTile
        end,
        tiles = { maskTile },
      })

      Base.setMeta(maskTileset, {
        schemaVersion = 1,
        fontProfileId = "test_profile",
        role = "masks",
        profileJson = '{"cellWidth":8,"cellHeight":8,"name":"TestFont"}',
      })
      Base.setMeta(
        paintTileset,
        { schemaVersion = 1, fontProfileId = "test_profile", role = "paint" }
      )
      Base.setMeta(maskTile, { glyphKey = "A", imageHash = U.hash(maskTile.image.bytes) })

      local sprite = {
        tilesets = { maskTileset, paintTileset },
        newTile = function(self, ts)
          local newIdx = #paintTiles + 1
          local newT = withProps({
            index = newIdx,
            image = Image(8, 8, ColorMode.RGB),
          })
          paintTiles[newIdx] = newT
          return newT
        end,
      }

      Profile.invalidate()
      local idxPlain =
        Profile.variant(sprite, "test_profile", "A", "#ffffffff", "#000000ff", 0, "none")
      local idxCircle =
        Profile.variant(sprite, "test_profile", "A", "#ffffffff", "#000000ff", 0, "circle")
      local idxSquare =
        Profile.variant(sprite, "test_profile", "A", "#ffffffff", "#000000ff", 0, "square")

      assert(idxPlain ~= idxCircle, "plain and circle must produce distinct tile indices")
      assert(idxCircle ~= idxSquare, "circle and square must produce distinct tile indices")

      -- Test decoding
      local layer = { tileset = paintTileset }
      local metaPlain = Profile.decode(layer, idxPlain)
      assert(metaPlain.schemaVersion == 1)
      assert(metaPlain.outline == nil)

      local metaCircle = Profile.decode(layer, idxCircle)
      assert(metaCircle.schemaVersion == 3)
      assert(metaCircle.outline == "circle")

      local metaSquare = Profile.decode(layer, idxSquare)
      assert(metaSquare.schemaVersion == 3)
      assert(metaSquare.outline == "square")
    end
  )

  test("Stamps toggleOutline action cycles outline mode and supports targeting", function()
    package.loaded["src.actions.stamps"] = nil
    local Stamps = require("src.actions.stamps")
    local Base = require("src.document.base")

    local paintTiles = {}
    local paintTileset = withProps({
      name = "Asemode paint: TestFont",
      tile = function(self, index)
        return paintTiles[index]
      end,
      tiles = paintTiles,
    })
    local maskTile = withProps({ image = Image(8, 8, ColorMode.RGB) })
    maskTile.image:clear(pc.rgba(255, 255, 255, 255))
    local maskTileset = withProps({
      name = "Asemode masks: TestFont",
      tile = function()
        return maskTile
      end,
      tiles = { maskTile },
    })
    Base.setMeta(maskTileset, {
      schemaVersion = 1,
      fontProfileId = "test_profile",
      role = "masks",
      profileJson = '{"cellWidth":8,"cellHeight":8,"name":"TestFont"}',
    })
    Base.setMeta(
      paintTileset,
      { schemaVersion = 1, fontProfileId = "test_profile", role = "paint" }
    )
    Base.setMeta(maskTile, { glyphKey = "0", imageHash = U.hash(maskTile.image.bytes) })

    local sprite = withProps({
      width = 8,
      height = 8,
      isValid = true,
      colorMode = ColorMode.RGB,
      tilesets = { maskTileset, paintTileset },
      newTile = function(self, ts)
        local newIdx = #paintTiles + 1
        local newT = withProps({ index = newIdx, image = Image(8, 8, ColorMode.RGB) })
        paintTiles[newIdx] = newT
        return newT
      end,
      events = {
        on = function()
          return 1
        end,
      },
    })
    Base.setMeta(
      sprite,
      { schemaVersion = 1, cellWidth = 8, cellHeight = 8, originX = 0, originY = 0 }
    )

    local layer = withProps({
      isTilemap = true,
      sprite = sprite,
      tileset = paintTileset,
      isEditable = true,
      isVisible = true,
      parent = sprite,
    })
    Base.setMeta(layer, { schemaVersion = 1, fontProfileId = "test_profile" })

    app.sprite = sprite
    app.layer = layer
    app.fgTile = 0
    app.bgTile = 0
    app.fgColor = Color(255, 255, 255, 255)
    app.bgColor = Color(0, 0, 0, 255)

    Profile.invalidate()
    local tilePlain = Profile.orientedTile(sprite, "test_profile", "0", "#ffffffff", "#000000ff", 0)
    app.fgTile = tilePlain
    app.bgTile = tilePlain

    -- Test 1: toggleOutline on primary: none -> circle
    local cap = Stamps.read("toggleOutline", false)
    local res = Stamps.apply(cap, nil, MouseButton.LEFT)
    assert(res.primary.meta.outline == "circle", "primary should transition from none to circle")
    assert(res.secondary.meta.outline == nil, "secondary should remain unaffected")

    -- Test 2: toggleOutline on primary: circle -> square
    cap = Stamps.read("toggleOutline", false)
    res = Stamps.apply(cap, nil, MouseButton.LEFT)
    assert(res.primary.meta.outline == "square", "primary should transition from circle to square")

    -- Test 3: toggleOutline on primary: square -> none
    cap = Stamps.read("toggleOutline", false)
    res = Stamps.apply(cap, nil, MouseButton.LEFT)
    assert(res.primary.meta.outline == nil, "primary should transition from square to none")

    -- Test 4: toggleOutline on secondary (right-click)
    cap = Stamps.read("toggleOutline", false)
    res = Stamps.apply(cap, nil, MouseButton.RIGHT)
    assert(res.secondary.meta.outline == "circle", "secondary should transition to circle")
    assert(res.primary.meta.outline == nil, "primary should remain unaffected")

    -- Test 5: toggleOutline on both
    cap = Stamps.read("toggleOutline", false)
    res = Stamps.apply(cap, nil, "both")
    assert(res.primary.meta.outline == "circle", "both target should set primary to circle")
    assert(
      res.secondary.meta.outline == "square",
      "both target should cycle secondary from circle to square"
    )
  end)

  test("drawing session setOutline and snapshot expose outline mode correctly", function()
    package.loaded["src.session.drawing"] = nil
    local Drawing = require("src.session.drawing")
    local changedCount = 0
    local session = Drawing.new({
      changed = function()
        changedCount = changedCount + 1
      end,
      blocksDrawing = function()
        return false
      end,
      remember = function() end,
    })

    local snap = session:snapshot()
    assert(snap.outline == "none")
    assert(snap.bgOutline == "none")

    session:setOutline("circle", MouseButton.LEFT)
    assert(session:snapshot().outline == "circle")
    assert(session:snapshot().bgOutline == "none")

    session:setOutline("square", MouseButton.RIGHT)
    assert(session:snapshot().outline == "circle")
    assert(session:snapshot().bgOutline == "square")

    session:setOutline("none", "both")
    assert(session:snapshot().outline == "none")
    assert(session:snapshot().bgOutline == "none")
  end)

  -- Cleanup
  app, Image, ColorMode, Color, MouseButton, json =
    oldApp, oldImage, oldColorMode, oldColor, oldMouse, oldJson
  package.loaded["src.document.profile"] = oldProfile
  package.loaded["src.actions.stamps"] = oldStamps
end
