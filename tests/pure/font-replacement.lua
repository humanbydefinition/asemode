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
    pixelColor = { TILE_XFLIP = 0x10000000, TILE_YFLIP = 0x20000000, TILE_DFLIP = 0x40000000 },
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
        profile = { pixelSize = 8 },
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
    orientedTile = function(_, _, glyph)
      return glyph == "0" and 10 or 11
    end,
    decode = function(_, tile)
      assert(tile == 10 or tile == 11, "old tile is outside the new tileset")
      return {
        glyphKey = tile == 10 and "0" or "1",
        foregroundRGBA = "#ffffffff",
        backgroundRGBA = "#000000ff",
      },
        0
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

  -- Teardown: restore loaded modules and globals
  for _, name in ipairs(modules) do
    package.loaded[name] = saved[name]
  end
  app, MouseButton, TilemapMode, Color = oldApp, oldMouse, oldTilemap, oldColor
end
