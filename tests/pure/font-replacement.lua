return function(test)
  local saved = {}
  local modules = {
    "src.document.model",
    "src.document.profile",
    "src.fonts.loader",
    "src.document.edit",
    "src.document.validate",
    "src.document.rotate",
    "src.document.flatten",
    "src.core.task",
    "src.ui.font_workflow",
    "src.session.drawing",
    "src.session.native_operations",
    "src.actions.stamps",
    "src.document.stamp_state",
  }
  for _, name in ipairs(modules) do
    saved[name] = package.loaded[name]
  end
  local oldApp, oldMouse, oldTilemap, oldColor = app, MouseButton, TilemapMode, Color
  local sprite = {
    width = 8,
    height = 8,
    isValid = true,
    events = {
      on = function()
        return 1
      end,
    },
  }
  local layer = { meta = { fontProfileId = "old" }, tiles = {} }
  layer.sprite = sprite
  app = {
    sprite = sprite,
    layer = layer,
    fgTile = 99,
    bgTile = 98,
    pixelColor = {
      TILE_XFLIP = 0x10000000,
      TILE_YFLIP = 0x20000000,
      TILE_DFLIP = 0x40000000,
      tile = function(ti, flags)
        return ti | (flags or 0)
      end,
      tileI = function(value)
        return value & 0xffff
      end,
      tileF = function(value)
        return value & 0x70000000
      end,
    },
    isUIAvailable = false,
    site = { tilemapMode = 1 },
    preferences = {
      document = function()
        return { grid = { snap = false } }
      end,
    },
    transaction = function(_, fn)
      fn()
    end,
  }
  MouseButton, TilemapMode = { LEFT = 1, RIGHT = 2 }, { TILES = 1 }
  Color = function(value)
    return value
  end
  local model = {
    layers = function()
      return { layer }
    end,
    textLayer = function()
      return true
    end,
    managed = function()
      return true
    end,
    coverage = function()
      return { columns = 1, rows = 1 }
    end,
    geometry = function()
      return { cellWidth = 8, cellHeight = 8 }
    end,
    meta = function(value)
      return value.meta
    end,
    setMeta = function(value, meta)
      value.meta = meta
    end,
    requireEligible = function() end,
    editable = function() end,
  }
  local tileColors = {}
  local profile = {
    defaultStamps = function(input)
      if input.glyphs then
        return "0", "1"
      end
      local supported = {}
      for _, glyph in ipairs(input) do
        if not glyph.renderFallback then
          supported[#supported + 1] = glyph.glyphKey
        end
      end
      return supported[1] or input[1].glyphKey, supported[2] or supported[1] or input[1].glyphKey
    end,
    invalidate = function() end,
    index = function()
      return {
        id = "old",
        profile = { pixelSize = 8, cellWidth = 8, cellHeight = 8 },
        glyphs = { ["0"] = { meta = {} }, ["1"] = { meta = {} } },
        variants = {
          ["0\0#ffffffff#000000ff:0"] = 10,
          ["1\0#ffffffff#000000ff:0"] = 11,
        },
      }
    end,
    install = function()
      return "new"
    end,
    orientedTile = function(_, _, glyph, fg, bg, flags)
      local ti = glyph == "0" and 10 or 11
      if fg and bg then
        tileColors[ti] = { fg = fg, bg = bg }
      end
      return ti | (flags or 0)
    end,
    decode = function(_, tile)
      local ti = tile & 0xffff
      local flags = tile & 0x70000000
      if ti == 0 then
        return nil, flags
      end
      assert(ti == 10 or ti == 11, "old tile is outside the new tileset")
      local colors = tileColors[ti] or { fg = "#ffffffff", bg = "#000000ff" }
      return {
        fontProfileId = "old",
        glyphKey = ti == 10 and "0" or "1",
        imageHash = "12345678",
        foregroundRGBA = colors.fg,
        backgroundRGBA = colors.bg,
      },
        flags
    end,
  }
  function model.hasMarkedLayers(value)
    if not value or not model.markedLayer then
      return false
    end
    for _, candidate in ipairs(model.layers(value)) do
      if model.markedLayer(value, candidate) then
        return true
      end
    end
    return false
  end
  package.loaded["src.document.model"] = model
  package.loaded["src.document.profile"] = profile
  package.loaded["src.fonts.loader"] = {
    ensureCharacters = function() end,
    inspect = function(path)
      return { path = path, name = "Uploaded", extractedAuthor = "Font Designer" }
    end,
  }
  package.loaded["src.document.edit"] = {
    characters = function()
      return {}
    end,
    layerSignature = function()
      return "unchanged"
    end,
    replaceFont = function()
      layer.meta.fontProfileId = "new"
    end,
  }
  package.loaded["src.document.validate"] = { requireValid = function() end }
  package.loaded["src.core.task"] = {
    new = function(fn)
      return fn
    end,
  }
  package.loaded["src.session.drawing"] = nil
  package.loaded["src.session.native_operations"] = nil
  package.loaded["src.document.rotate"] = nil
  package.loaded["src.document.flatten"] = nil
  package.loaded["src.actions.stamps"] = nil
  package.loaded["src.document.stamp_state"] = nil
  package.loaded["src.ui.font_workflow"] = nil
  local drawing = require("src.session.drawing").new({
    changed = function() end,
    guard = function(fn)
      return fn
    end,
    blocksDrawing = function()
      return false
    end,
    remember = function() end,
  })
  local buttons, lastDialog = {}, nil
  local function dialog()
    local d = {
      data = { size = "8", aa = false, source = "library", clip = false },
      modified = {},
      controls = {},
      labels = {},
    }
    lastDialog = d
    setmetatable(d, {
      __index = function(_, name)
        return function(self, arg)
          if name == "label" and arg and arg.id then
            self.labels[arg.id] = arg
          end
          if name == "label" and arg and arg.label then
            self.labels[arg.label] = arg
          end
          if name == "canvas" then
            self.canvas = arg
          end
          if name == "button" then
            buttons[arg.text] = arg.onclick
          end
          if name == "file" then
            self.controls[arg.id] = arg
          end
          if name == "combobox" then
            self.data[arg.id] = arg.option
          end
          if name == "modify" and arg.option then
            self.data[arg.id] = arg.option
          end
          if name == "modify" then
            self.modified[arg.id] = arg
          end
          return self
        end
      end,
    })
    return d
  end
  local job = {
    glyphs = { { glyphKey = "0" }, { glyphKey = "1" } },
    masks = {},
    profile = {
      name = "new",
      cellWidth = 8,
      cellHeight = 8,
      baseline = 1,
      naturalWidth = 8,
      naturalHeight = 8,
      clippedGlyphs = 0,
    },
  }
  local library = {
    author = function(_, entry)
      return entry.author or "Unknown"
    end,
    authorForCandidate = function(_, candidate)
      return candidate.extractedAuthor or "Unknown"
    end,
    catalog = function()
      return { { id = "atascii", kind = "bundled", label = "Font", author = "Curated" } }
    end,
    job = function()
      return job
    end,
  }
  local workflow = require("src.ui.font_workflow").new({
    library = library,
    drawing = drawing,
    dialog = dialog,
    guard = function(fn)
      return fn
    end,
    controls = {
      setNumericEnabled = require("src.ui.controls").new().setNumericEnabled,
      addFontSizeInput = function(_, d)
        return d
      end,
    },
    tasks = {
      isActive = function()
        return false
      end,
      start = function(_, _, options)
        options.complete()
      end,
    },
    invalidate = function() end,
    isDialogOpen = function()
      return true
    end,
  })
  test("unclipped font preview uses the original canvas size", function()
    workflow:preview(job, function() end)
    assert(lastDialog.canvas.width == 180 and lastDialog.canvas.height == 70)
    assert(lastDialog.labels.Key == nil)
  end)
  test("font preview connects clipping diagnostics to the canvas and confirmation", function()
    local oldRectangle, previousColor = Rectangle, Color
    local preview = require("src.ui.font_preview")
    local oldPrepare = preview.prepare
    rawset(preview, "prepare", function()
      return { left = 0, right = 0, top = 0, bottom = 0 }
    end)
    Rectangle = function(x, y, width, height)
      return { x = x, y = y, width = width, height = height }
    end
    Color = function()
      return "outline"
    end
    local clippedJob = {
      profile = {
        name = "Clipped",
        kind = "truetype",
        cellWidth = 8,
        cellHeight = 8,
        naturalWidth = 9,
        naturalHeight = 8,
        baseline = 6,
        originX = 0,
        scale = 1,
        clippedGlyphs = 1,
      },
      glyphs = {
        { glyphKey = "A", contours = { {} }, xMin = 0, xMax = 9, yMin = -2, yMax = 6 },
      },
      masks = { {} },
    }
    local confirmed
    workflow:preview(clippedJob, function(result, allowClipping)
      confirmed = result == clippedJob and allowClipping
    end)
    assert(lastDialog.canvas.width == 180 and lastDialog.canvas.height == 100)
    assert(lastDialog.labels.Fit.text == "1 glyph(s) may clip")
    assert(lastDialog.labels.Key == nil and lastDialog.labels.Preview == nil)
    local gc = {
      width = 180,
      height = 70,
      theme = {
        color = { editor_face = "surface", selected = "warning", button_selected_text = "text" },
      },
    }
    local bars = 0
    function gc:drawThemeRect() end
    function gc:drawImage() end
    function gc:strokeRect() end
    function gc:fillRect()
      if self.color == "warning" then
        bars = bars + 1
      end
    end
    lastDialog.canvas.onpaint({ context = gc })
    assert(bars == 0)
    buttons["Use font"]()
    assert(confirmed)
    rawset(preview, "prepare", oldPrepare)
    Rectangle, Color = oldRectangle, previousColor
  end)

  test("replacing a font selects readable stamps from the new tileset", function()
    workflow:importFont(false)
    buttons["Replace layer font.."]()
    buttons["Use font"]()
    drawing:tick(true)
    assert(app.fgTile == 10 and app.bgTile == 11, "font replacement retained old stamp indices")
    local snapshot = drawing:snapshot()
    assert(snapshot.glyph == "0" and snapshot.bgGlyph == "1")
  end)

  test(
    "imported stamps retain drawing colors when sprite activation queues a color change",
    function()
      drawing:setColors(nil, "#ffffffff", "#000000ff")
      app.fgColor = { red = 0, green = 0, blue = 0, alpha = 0 }
      app.bgColor = { red = 0, green = 0, blue = 0, alpha = 0 }
      drawing:queueColorCommit("external")
      drawing:setImportedStamps("0", "1", { destination = "new" })
      drawing:prepareBoth()
      local snapshot = drawing:snapshot()
      assert(snapshot.fg == "#ffffffff" and snapshot.bg == "#000000ff", "import lost stamp colors")
      assert(app.fgTile == 10 and app.bgTile == 11)
    end
  )

  test("prepared stamps synchronize native buttons when tile preferences are unchanged", function()
    local stored = { fgTile = 10, bgTile = 11 }
    local native = { fgTile = nil, bgTile = nil }
    app.fgTile, app.bgTile = nil, nil
    setmetatable(app, {
      __index = function(_, key)
        return stored[key]
      end,
      __newindex = function(target, key, value)
        if key == "fgTile" or key == "bgTile" then
          if stored[key] ~= value then
            stored[key], native[key] = value, value
          end
        else
          rawset(target, key, value)
        end
      end,
    })
    drawing:setImportedStamps("0", "1", { destination = "new" })
    drawing:prepareBoth()
    assert(native.fgTile == 10 and native.bgTile == 11, "native tile buttons were not updated")
    native.fgTile, native.bgTile = nil, nil
    workflow:importFont(false)
    buttons["Replace layer font.."]()
    buttons["Use font"]()
    assert(native.fgTile == 10 and native.bgTile == 11, "font replacement buttons were not updated")
    stored.fgTile, stored.bgTile = 0, 0
    native.fgTile, native.bgTile = nil, nil
    drawing:setImportedStamps("0", "1", { destination = "existing", paintCount = 1 })
    assert(native.fgTile == 0 and native.bgTile == 0, "empty imported stamps were not updated")
    setmetatable(app, nil)
    app.fgTile, app.bgTile = stored.fgTile, stored.bgTile
  end)

  test("tile decode failures are logged once until selection changes", function()
    local previousPrint, messages = print, {}
    print = function(message)
      messages[#messages + 1] = message
    end
    app.fgTile, app.bgTile = 99, 98
    drawing:tick(true)
    drawing:tick(true)
    app.fgTile, app.bgTile = 10, 11
    drawing:tick(true)
    print = previousPrint
    assert(#messages == 2, "expected one error per unreadable tile")
    assert(messages[1]:find("primary tile error", 1, true))
    assert(messages[2]:find("secondary tile error", 1, true))
    assert(messages[1]:find("old tile is outside the new tileset", 1, true))
    assert(messages[2]:find("old tile is outside the new tileset", 1, true))
  end)

  test("switching sprites repairs stale primary and secondary tile indices", function()
    local nextSprite = {
      isValid = true,
      events = {
        on = function()
          return 1
        end,
        off = function() end,
      },
    }
    sprite.events.off = function() end
    local nextLayer = { meta = { fontProfileId = "next" }, tileset = {} }
    nextLayer.sprite = nextSprite
    for i = 1, 12 do
      nextLayer.tileset[i] = {}
    end
    local oldPixelColor, oldDecode = app.pixelColor, profile.decode
    profile.decode = function(targetLayer, tile)
      if targetLayer == nextLayer and tile >= #nextLayer.tileset then
        error("Tile reference is out of range")
      end
      return oldDecode(targetLayer, tile)
    end
    drawing:setImportedStamps("0", "1")
    app.sprite, app.layer, app.fgTile, app.bgTile = sprite, layer, 99, 98
    drawing:panelOpened(true)
    app.sprite, app.layer = nextSprite, nextLayer
    local previousPrint, messages = print, {}
    print = function(message)
      messages[#messages + 1] = message
    end
    drawing:tick(true)
    print = previousPrint
    app.sprite, app.layer = sprite, layer
    app.pixelColor, profile.decode = oldPixelColor, oldDecode
    assert(#messages == 0, "switch logged stale tile errors")
    assert(app.fgTile == 10 and app.bgTile == 11, "switch did not repair both stamps")
  end)

  test("restoring missing stamps does not modify the sprite", function()
    local oldIndex, oldTransaction = profile.index, app.transaction
    local transactions = 0
    profile.index = function(...)
      local index = oldIndex(...)
      index.variants = {}
      return index
    end
    app.transaction = function(_, fn)
      transactions = transactions + 1
      fn()
    end
    drawing:invalidateStamps()
    drawing:ensureActive()
    local snapshot = drawing:snapshot()
    assert(snapshot.missingPrimary and snapshot.missingSecondary)
    assert(transactions == 0, "restoration changed the document")
    assert(app.fgTile == 0 and app.bgTile == 0)
    profile.index, app.transaction = oldIndex, oldTransaction
  end)

  test("drawing modes are restored after leaving through a regular layer", function()
    local oldUI, oldCommand, oldSite, oldPreferences =
      app.isUIAvailable, app.command, app.site, app.preferences
    local oldTextLayer, oldTileset = model.textLayer, TilesetMode
    local prefs = { grid = { snap = true }, show = { grid = false } }
    app.isUIAvailable = true
    app.site = { tilemapMode = 0, tilesetMode = 1 }
    TilesetMode = { MANUAL = 0, AUTO = 1, STACK = 2 }
    app.preferences = {
      document = function()
        return prefs
      end,
    }
    app.command = {
      TilesetMode = function(options)
        app.site.tilesetMode = options.mode == "manual" and 0
          or (options.mode == "stack" and 2 or 1)
      end,
      ToggleTilesMode = function()
        app.site.tilemapMode = app.site.tilemapMode == 1 and 0 or 1
      end,
    }
    local regular = { isTilemap = false }
    layer.isTilemap = true
    model.textLayer = function(_, candidate)
      return candidate == layer
    end
    app.layer = layer
    drawing:tick(true)
    assert(app.site.tilemapMode == 1 and app.site.tilesetMode == 0)
    assert(prefs.grid.snap == false and prefs.show.grid == false)
    app.layer = regular
    app.site.tilemapMode, app.site.tilesetMode = 0, 0
    drawing:tick(true)
    assert(prefs.grid.snap and not prefs.show.grid)
    regular.isTilemap = true
    app.site.tilemapMode, app.site.tilesetMode = 1, 0
    drawing:tick(true)
    assert(app.site.tilemapMode == 0 and app.site.tilesetMode == 1)
    app.layer = layer
    layer.isTilemap = nil
    app.isUIAvailable, app.command, app.site, app.preferences =
      oldUI, oldCommand, oldSite, oldPreferences
    model.textLayer, TilesetMode = oldTextLayer, oldTileset
  end)

  test("native sprite resize is stopped for projects with Asemode layers", function()
    local oldEvents, oldMarked = app.events, model.markedLayer
    local listeners, canceled = {}, false
    app.events = {
      on = function(_, name, fn)
        listeners[name] = fn
        return name
      end,
      off = function() end,
    }
    rawset(model, "markedLayer", function(_, candidate)
      return candidate == layer
    end)
    drawing:start()
    local activeLayer = app.layer
    app.layer = {}
    listeners.beforecommand({
      name = "SpriteSize",
      stopPropagation = function()
        canceled = true
      end,
    })
    assert(canceled, "native resize was allowed to alter Asemode tiles")
    canceled = false
    listeners.beforecommand({
      name = "CanvasSize",
      stopPropagation = function()
        canceled = true
      end,
    })
    assert(canceled, "native canvas resize was allowed to move Asemode cels off the grid")
    local oldUI, oldAlert = app.isUIAvailable, app.alert
    app.isUIAvailable = true
    rawset(app, "alert", function()
      canceled = false -- A nested host command resets Aseprite's cancellation flag.
    end)
    listeners.beforecommand({
      name = "CanvasSize",
      stopPropagation = function()
        canceled = true
      end,
    })
    assert(canceled, "the alert lost the host command cancellation")
    app.isUIAvailable = oldUI
    rawset(app, "alert", oldAlert)
    app.layer = activeLayer
    canceled = false
    rawset(model, "markedLayer", function()
      return false
    end)
    listeners.beforecommand({
      name = "SpriteSize",
      stopPropagation = function()
        canceled = true
      end,
    })
    assert(not canceled, "native resize was blocked for a regular sprite")
    canceled = false
    listeners.beforecommand({
      name = "CanvasSize",
      stopPropagation = function()
        canceled = true
      end,
    })
    assert(not canceled, "native canvas resize was blocked for a regular sprite")
    drawing:close()
    app.events = oldEvents
    rawset(model, "markedLayer", oldMarked)
  end)

  test("color mode protects Asemode projects and allows RGB recovery", function()
    local oldEvents, oldMarked, oldUI, oldAlert, oldLayer =
      app.events, model.markedLayer, app.isUIAvailable, app.alert, app.layer
    local listeners, canceled, warning = {}, false, nil
    app.events = {
      on = function(_, name, fn)
        listeners[name] = fn
        return name
      end,
      off = function() end,
    }
    rawset(model, "markedLayer", function(_, candidate)
      return candidate == layer
    end)
    app.isUIAvailable = false
    drawing:start()
    app.isUIAvailable, app.layer = true, {}
    rawset(app, "alert", function(details)
      warning, canceled = details, false
    end)
    local function change(params)
      canceled, warning = false, nil
      listeners.beforecommand({
        name = "ChangePixelFormat",
        params = params,
        stopPropagation = function()
          canceled = true
        end,
      })
    end
    for _, params in ipairs({
      { format = "grayscale" },
      { format = "indexed" },
      {},
      { format = "rgb", ui = "true" },
    }) do
      change(params)
      assert(canceled and warning and warning.title == "Asemode")
      assert(table.concat(warning.text, " "):find("RGB", 1, true))
    end
    change(nil)
    assert(canceled and warning, "missing parameters bypassed protection")
    change({ format = "rgb" })
    assert(not canceled and not warning, "RGB recovery was blocked")
    change({ colorMode = "RGB" })
    assert(not canceled and not warning)
    rawset(model, "markedLayer", function()
      return false
    end)
    change({ format = "indexed" })
    assert(not canceled and not warning, "regular sprite was blocked")
    change({})
    assert(not canceled and not warning, "regular sprite options were blocked")
    app.isUIAvailable = false
    drawing:close()
    app.events, app.isUIAvailable, app.layer = oldEvents, oldUI, oldLayer
    rawset(app, "alert", oldAlert)
    rawset(model, "markedLayer", oldMarked)
  end)

  test("filter protection handles nested and failed warnings", function()
    local oldEvents, oldMarked, oldUI, oldAlert =
      app.events, model.markedLayer, app.isUIAvailable, app.alert
    local listeners, warnings, canceled = {}, 0, false
    app.events = {
      on = function(_, name, fn)
        listeners[name] = fn
        return name
      end,
      off = function(_, name)
        listeners[name] = nil
      end,
    }
    rawset(model, "markedLayer", function(_, candidate)
      return candidate == layer
    end)
    app.isUIAvailable = false
    drawing:start()
    app.isUIAvailable = true
    local function attempt()
      listeners.beforecommand({
        name = "Outline",
        stopPropagation = function()
          canceled = true
        end,
      })
    end
    rawset(app, "alert", function()
      warnings = warnings + 1
      canceled = false
      attempt()
      assert(canceled, "nested operation was not canceled")
      canceled = false
    end)
    attempt()
    assert(warnings == 1 and canceled, "warning re-entry or host cancellation failed")
    canceled = false
    rawset(app, "alert", function()
      error("alert failed")
    end)
    attempt()
    assert(canceled, "alert failure allowed the operation")
    canceled = false
    drawing:withSuppression(attempt)
    assert(not canceled, "suppressed command was intercepted")
    app.isUIAvailable = false
    drawing:close()
    assert(not next(listeners), "command listeners were not removed")
    app.events, app.isUIAvailable = oldEvents, oldUI
    rawset(app, "alert", oldAlert)
    rawset(model, "markedLayer", oldMarked)
  end)

  test("native paste remains canceled after nested or failed warnings", function()
    local oldEvents, oldMarked, oldUI, oldAlert, oldLayer =
      app.events, model.markedLayer, app.isUIAvailable, app.alert, app.layer
    local listeners, canceled, warnings = {}, false, 0
    app.events = {
      on = function(_, name, fn)
        listeners[name] = fn
        return name
      end,
      off = function() end,
    }
    rawset(model, "markedLayer", function(_, candidate)
      return candidate == layer
    end)
    app.isUIAvailable, app.layer = false, layer
    drawing:start()
    app.isUIAvailable = true
    local function paste()
      listeners.beforecommand({
        name = "Paste",
        stopPropagation = function()
          canceled = true
        end,
      })
    end
    rawset(app, "alert", function()
      warnings, canceled = warnings + 1, false
      paste()
      assert(canceled, "nested paste was not canceled")
      canceled = false
    end)
    paste()
    assert(warnings == 1 and canceled, "warning lost paste cancellation")
    canceled = false
    rawset(app, "alert", function()
      error("alert failed")
    end)
    paste()
    assert(canceled, "failed warning allowed paste")
    app.isUIAvailable = false
    drawing:close()
    app.events, app.isUIAvailable, app.layer = oldEvents, oldUI, oldLayer
    rawset(app, "alert", oldAlert)
    rawset(model, "markedLayer", oldMarked)
  end)

  test("native layer conversion protects only the active Asemode layer", function()
    local oldEvents, oldMarked, oldUI, oldAlert, oldLayer =
      app.events, model.markedLayer, app.isUIAvailable, app.alert, app.layer
    local listeners, canceled, warning = {}, false, nil
    app.events = {
      on = function(_, name, fn)
        listeners[name] = fn
        return name
      end,
      off = function() end,
    }
    rawset(model, "markedLayer", function(_, candidate)
      return candidate == layer
    end)
    app.isUIAvailable = false
    drawing:start()
    app.isUIAvailable = true
    rawset(app, "alert", function(details)
      warning = details
      canceled = false -- A nested command can reset Aseprite's cancellation flag.
    end)
    local function convert(target)
      canceled, warning = false, nil
      listeners.beforecommand({
        name = "ConvertLayer",
        params = { to = target },
        stopPropagation = function()
          canceled = true
        end,
      })
    end
    app.layer = layer
    for _, target in ipairs({ "layer", "background" }) do
      convert(target)
      assert(canceled and warning and warning.title == "Asemode")
      assert(table.concat(warning.text, " "):find("textmode", 1, true))
    end
    canceled, warning = false, nil
    listeners.beforecommand({
      name = "ConvertLayer",
      params = {},
      stopPropagation = function()
        canceled = true
      end,
    })
    assert(canceled and warning, "missing host parameters bypassed layer protection")
    convert("tilemap")
    assert(not canceled and not warning)
    app.layer = {}
    convert("layer")
    assert(not canceled and not warning)
    app.isUIAvailable = false
    drawing:close()
    app.events, app.isUIAvailable, app.layer = oldEvents, oldUI, oldLayer
    rawset(app, "alert", oldAlert)
    rawset(model, "markedLayer", oldMarked)
  end)

  test(
    "selecting a new glyph preserves primary orientation and aligns secondary stamp with grid display",
    function()
      local xflip = app.pixelColor.TILE_XFLIP
      local yflip = app.pixelColor.TILE_YFLIP
      local recordedFlags = {}
      local oldOrientedTile = profile.orientedTile
      profile.orientedTile = function(s, id, glyph, fg, bg, flags)
        table.insert(recordedFlags, { glyph = glyph, flags = flags })
        return oldOrientedTile(s, id, glyph, fg, bg, flags)
      end

      drawing:setImportedStamps("0", "1")
      drawing:prepare(MouseButton.LEFT, "0", xflip)
      drawing:prepare(MouseButton.RIGHT, "1", yflip)
      local before = drawing:snapshot()
      assert(before.flags == xflip, "initial primary flags not set")
      assert(before.bgFlags == yflip, "initial secondary flags not set")

      recordedFlags = {}
      drawing:selectGlyph(MouseButton.LEFT, "1")
      local afterPrimary = drawing:snapshot()
      assert(afterPrimary.glyph == "1", "primary glyph was not updated")
      assert(afterPrimary.flags == xflip, "primary orientation flags were reset on glyph selection")
      assert(
        afterPrimary.bgFlags == yflip,
        "secondary flags were altered on primary glyph selection"
      )
      assert(
        #recordedFlags == 1 and recordedFlags[1].glyph == "1" and recordedFlags[1].flags == xflip,
        "orientedTile did not receive preserved primary flags"
      )

      recordedFlags = {}
      -- Selecting secondary glyph in the Asemode panel adopts the displayed grid flags (state.flags)
      drawing:selectGlyph(MouseButton.RIGHT, "0")
      local afterSecondary = drawing:snapshot()
      assert(afterSecondary.bgGlyph == "0", "secondary glyph was not updated")
      assert(
        afterSecondary.bgFlags == xflip,
        "secondary orientation flags did not adopt displayed primary flags"
      )
      assert(
        afterSecondary.flags == xflip,
        "primary flags were altered on secondary glyph selection"
      )
      assert(
        #recordedFlags == 1 and recordedFlags[1].glyph == "0" and recordedFlags[1].flags == xflip,
        "orientedTile did not receive adopted displayed grid flags"
      )

      profile.orientedTile = oldOrientedTile
    end
  )

  test(
    "stamp action transforms can target the secondary stamp exclusively via right-click",
    function()
      local Stamps = require("src.actions.stamps")
      local xflip = app.pixelColor.TILE_XFLIP

      drawing:setImportedStamps("0", "1")
      drawing:prepare(MouseButton.LEFT, "0", 0)
      drawing:prepare(MouseButton.RIGHT, "1", 0)

      -- Verify right-clicking flipHorizontal transforms only secondary stamp
      local captured = Stamps.read("flipHorizontal", false)
      local result = Stamps.apply(captured, nil, MouseButton.RIGHT)
      assert(result.primary.flags == 0, "primary stamp flags were altered by right-click action")
      assert(
        result.secondary.flags == xflip,
        "secondary stamp flags were not flipped by right-click action"
      )

      -- Verify left-clicking flipHorizontal transforms only the primary stamp
      captured = Stamps.read("flipHorizontal", false)
      result = Stamps.apply(captured, nil, MouseButton.LEFT)
      assert(result.primary.flags == xflip, "primary stamp was not flipped by left-click action")
      assert(
        result.secondary.flags == xflip,
        "secondary stamp flags were modified by left-click action"
      )

      -- Verify transforming "both" respects different prior orientations
      -- Currently: primary has xflip, secondary has xflip
      -- Let's rotate clockwise for "both":
      captured = Stamps.read("rotateClockwise", false)
      result = Stamps.apply(captured, nil, "both")
      local Transforms = require("src.document.transforms")
      local expectedFlags = Transforms.rotate(xflip, true)
      assert(
        result.primary.flags == expectedFlags,
        "primary stamp did not apply clockwise rotation on both"
      )
      assert(
        result.secondary.flags == expectedFlags,
        "secondary stamp did not apply clockwise rotation on both"
      )

      -- Verify resetting orientation for "both" resets both stamps to 0
      captured = Stamps.read("resetOrientation", false)
      result = Stamps.apply(captured, nil, "both")
      assert(result.primary.flags == 0, "primary stamp was not reset by both reset")
      assert(result.secondary.flags == 0, "secondary stamp was not reset by both reset")

      -- Verify canRunAction enablement for primary, secondary, and both
      assert(drawing:canRunAction("flipHorizontal", MouseButton.LEFT) == true)
      assert(drawing:canRunAction("flipHorizontal", MouseButton.RIGHT) == true)
      assert(drawing:canRunAction("flipHorizontal", "both") == true)

      -- Verify controller stamp click target preferences
      local Controller = require("src.ui.controller")
      local prefs = {}
      local c = Controller.new({ preferences = prefs })
      assert(c:getStampClickTarget() == "primary")
      c:setStampClickTarget("both")
      assert(prefs.stampClickTarget == "both")
      assert(c:getStampClickTarget() == "both")
      c:setStampClickTarget("primary")
      assert(prefs.stampClickTarget == "primary")
      assert(c:getStampClickTarget() == "primary")
    end
  )

  test("secondary stamp actions work when primary stamp is empty", function()
    local xflip = app.pixelColor.TILE_XFLIP

    drawing:setImportedStamps("0", "1")
    drawing:prepare(MouseButton.LEFT, "0", 0)
    drawing:prepare(MouseButton.RIGHT, "1", 0)

    -- Select empty tile for primary (e.g. eraser mode)
    app.fgTile = 0
    drawing:syncNative()
    assert(drawing:snapshot().primaryEmpty == true, "primary should be empty")

    -- Check canRunAction
    assert(drawing:canRunAction("flipHorizontal", MouseButton.LEFT) == false)
    assert(drawing:canRunAction("flipHorizontal", "both") == false)
    assert(drawing:canRunAction("flipHorizontal", MouseButton.RIGHT) == true)
    assert(drawing:canRunAction("flipHorizontal", "secondary") == true)

    -- Run action on secondary
    drawing:runAction("flipHorizontal", "secondary")
    assert(app.fgTile == 0, "app.fgTile was modified from empty tile 0")
    local snap = drawing:snapshot()
    assert(snap.primaryEmpty == true, "primary should remain empty")
    assert(snap.bgFlags == xflip, "secondary flags were not updated")

    -- Run swapColors on secondary
    drawing:runAction("swapColors", "secondary")
    assert(app.fgTile == 0, "app.fgTile was modified by secondary swapColors")
  end)

  test(
    "swapColors resolves pending colors for every target and keeps independent colors",
    function()
      local red, blue, green = "#ff0000ff", "#0000ffff", "#00ff00ff"
      local white, black = "#ffffffff", "#000000ff"

      -- Primary: red ink on blue. Secondary: green ink on white.
      local function setup()
        drawing:ensureActive()
        drawing:setImportedStamps("0", "1")
        drawing:setColors(nil, green, white)
        drawing:prepare(MouseButton.RIGHT, "1", 0)
        drawing:setColors(nil, red, blue)
        drawing:prepare(MouseButton.LEFT, "0", 0)
      end

      -- Queue an external white-on-black color change that is still in its debounce.
      local function queuePending()
        app.fgColor = { red = 255, green = 255, blue = 255, alpha = 255 }
        app.bgColor = { red = 0, green = 0, blue = 0, alpha = 255 }
        drawing:queueColorCommit("external")
      end

      local function expect(label, fg, bg, secondaryFg, secondaryBg)
        local snap = drawing:snapshot()
        assert(
          snap.fg == fg and snap.bg == bg,
          label .. ": primary colors are " .. snap.fg .. "/" .. snap.bg
        )
        assert(
          snap.secondaryFg == secondaryFg and snap.secondaryBg == secondaryBg,
          label .. ": secondary colors are " .. snap.secondaryFg .. "/" .. snap.secondaryBg
        )
        assert(snap.pendingColors == nil, label .. ": pending colors were not resolved")
      end

      -- Both stamps, pending colors: both swap the pending colors.
      setup()
      queuePending()
      drawing:runAction("swapColors", "both")
      expect("both with pending", black, white, black, white)

      -- Both stamps, no pending colors: each stamp swaps its own colors.
      setup()
      drawing:runAction("swapColors", "both")
      expect("both without pending", blue, red, white, green)

      -- Primary only, pending colors: the secondary receives the pending colors unswapped.
      setup()
      queuePending()
      drawing:runAction("swapColors", MouseButton.LEFT)
      expect("primary with pending", black, white, white, black)

      -- Primary only, no pending colors: the secondary is unchanged.
      setup()
      drawing:runAction("swapColors", MouseButton.LEFT)
      expect("primary without pending", blue, red, green, white)

      -- Secondary only, pending colors: the primary receives the pending colors unswapped.
      setup()
      queuePending()
      drawing:runAction("swapColors", "secondary")
      expect("secondary with pending", white, black, black, white)
    end
  )

  test("legacy square-cell stamp orientation is preserved on document restore", function()
    local xflip = app.pixelColor.TILE_XFLIP
    local StampState = require("src.document.stamp_state")
    local U = require("src.core.util")

    local savedState = {
      primary = { glyph = "0", fg = "#ffffffff", bg = "#000000ff", flags = xflip },
      secondary = { glyph = "1", fg = "#ffffffff", bg = "#000000ff", flags = 0 },
    }
    StampState.write(sprite, layer, savedState)

    local oldIndex = profile.index
    profile.index = function(...)
      local idx = oldIndex(...)
      local legacyKey = U.key("0", "#ffffffff", "#000000ff", 0)
      local bakedKey = U.key("0", "#ffffffff", "#000000ff", xflip)
      idx.variants[bakedKey] = nil
      assert(idx.variants[legacyKey] ~= nil, "base variant must exist in mock")
      return idx
    end

    local messages = {}
    local previousPrint = print
    print = function(message)
      messages[#messages + 1] = message
    end

    drawing:invalidateStamps()
    drawing:ensureActive()

    print = previousPrint
    profile.index = oldIndex

    local snap = drawing:snapshot()
    assert(not snap.missingPrimary, "legacy stamp was falsely marked as missing")
    assert(
      #messages == 0,
      "legacy stamp logged missing stamp warning: " .. table.concat(messages, "; ")
    )
    assert(app.fgTile ~= 0, "app.fgTile was reset to 0 for legacy stamp")
    assert(snap.flags == xflip, "legacy orientation flags were lost")
  end)

  test("missing rectangular-cell stamp variants are reported, not rebuilt on restore", function()
    local xflip = app.pixelColor.TILE_XFLIP
    local StampState = require("src.document.stamp_state")

    StampState.write(sprite, layer, {
      primary = { glyph = "0", fg = "#ffffffff", bg = "#000000ff", flags = xflip },
      secondary = { glyph = "1", fg = "#ffffffff", bg = "#000000ff", flags = 0 },
    })

    local oldIndex, oldOrientedTile = profile.index, profile.orientedTile
    profile.index = function(...)
      local idx = oldIndex(...)
      idx.profile = { pixelSize = 8, cellWidth = 8, cellHeight = 16 }
      return idx
    end
    local rebuilt = false
    profile.orientedTile = function(s, id, glyph, fg, bg, flags)
      if glyph == "0" and flags ~= 0 then
        rebuilt = true
      end
      return oldOrientedTile(s, id, glyph, fg, bg, flags)
    end
    local messages = {}
    local previousPrint = print
    print = function(message)
      messages[#messages + 1] = message
    end

    drawing:invalidateStamps()
    drawing:ensureActive()

    print = previousPrint
    profile.index, profile.orientedTile = oldIndex, oldOrientedTile

    local snap = drawing:snapshot()
    assert(snap.missingPrimary, "missing rectangular-cell variant was not reported")
    assert(not rebuilt, "missing rectangular-cell variant was rebuilt during restore")
    assert(#messages == 1, "missing stamp warning was not logged")
  end)

  -- Teardown: restore loaded modules and globals
  for _, name in ipairs(modules) do
    package.loaded[name] = saved[name]
  end
  app, MouseButton, TilemapMode, Color = oldApp, oldMouse, oldTilemap, oldColor
end
