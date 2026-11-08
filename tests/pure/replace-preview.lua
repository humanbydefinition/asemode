return function(test)
  local saved = {}
  local modules = {
    "src.document.model",
    "src.document.profile",
    "src.document.transforms",
    "src.document.edit",
    "src.document.validate",
    "src.ui.document_workflow",
  }
  for _, name in ipairs(modules) do
    saved[name] = package.loaded[name]
  end

  local oldApp, oldRectangle, oldColor = app, Rectangle, Color
  local refreshCalls = 0
  app = {
    frame = 1,
    refresh = function()
      refreshCalls = refreshCalls + 1
    end,
    fs = {
      filePath = require("tests.pure.filesystem").filePath,
      joinPath = require("tests.pure.filesystem").joinPath,
    },
    pixelColor = {
      TILE_XFLIP = 0x10000000,
      TILE_YFLIP = 0x20000000,
      TILE_DFLIP = 0x40000000,
      rgbaA = function()
        return 255
      end,
      rgba = function(r, g, b, a)
        return r + g + b + a
      end,
    },
  }
  Rectangle = function(x, y, width, height)
    return { x = x, y = y, width = width, height = height }
  end
  Color = function(r, g, b, a)
    if type(r) == "table" then
      return { red = r.r or 0, green = r.g or 0, blue = r.b or 0, alpha = r.a or 255 }
    end
    return { red = r, green = g, blue = b, alpha = a }
  end

  test("replace selection dialog merges tabs and applies 1, 2, or 3 settings", function()
    local sprite = { width = 16, height = 8, isValid = true, selection = { isEmpty = false } }
    local layer = { meta = { fontProfileId = "p1" } }
    local recolorCalls = {}
    local primaryStamp = { fg = "#ff0080ff", bg = "#001020ff", glyph = "Z", flags = 0x20000000 }
    package.loaded["src.document.model"] = {
      meta = function(v)
        return v.meta
      end,
    }
    package.loaded["src.document.profile"] = {
      index = function()
        return {
          profile = { cellWidth = 8, cellHeight = 8 },
          glyphs = {
            ["A"] = { meta = {}, tile = { image = {} } },
            ["Z"] = { meta = {}, tile = { image = {} } },
          },
        }
      end,
      colorize = function()
        return {}
      end,
    }
    package.loaded["src.document.edit"] = {
      selectedCells = function()
        return {
          count = 2,
          minCol = 0,
          minRow = 0,
          columns = 2,
          rows = 1,
          cells = {
            {
              col = 0,
              row = 0,
              glyphKey = "A",
              foregroundRGBA = "#111111ff",
              backgroundRGBA = "#222222ff",
              flags = 0,
            },
            {
              col = 1,
              row = 0,
              glyphKey = "A",
              foregroundRGBA = "#111111ff",
              backgroundRGBA = "#222222ff",
              flags = 0,
            },
          },
        }
      end,
      recolor = function(_, _, _, fg, bg, glyph, flags)
        recolorCalls[#recolorCalls + 1] = { fg = fg, bg = bg, glyph = glyph, flags = flags }
      end,
    }
    package.loaded["src.ui.document_workflow"] = nil
    local DocumentWorkflow = require("src.ui.document_workflow")

    local controls, modified, tabsUsed, closedCount = {}, {}, false, 0
    local d
    d = {
      data = {
        changeFg = true,
        changeBg = true,
        changeGlyph = true,
        fg = { red = 255, green = 0, blue = 128, alpha = 255 },
        bg = { red = 0, green = 16, blue = 32, alpha = 255 },
        glyph = "Z",
      },
      modify = function(_, arg)
        modified[arg.id] = arg
      end,
      repaint = function() end,
      close = function()
        closedCount = closedCount + 1
      end,
      show = function(self)
        return self
      end,
    }
    setmetatable(d, {
      __index = function(_, name)
        return function(self, arg)
          if name == "tab" or name == "endtabs" then
            tabsUsed = true
          end
          if type(arg) == "table" and arg.id then
            controls[arg.id] = arg
          end
          return self
        end
      end,
    })

    local workflow = DocumentWorkflow.new({
      drawing = {
        target = function()
          return sprite, layer
        end,
        snapshot = function()
          return primaryStamp
        end,
      },
      dialog = function()
        return d
      end,
      guard = function(fn)
        return fn
      end,
    })

    workflow:replaceSelection()
    assert(modified.applyReplace and modified.applyReplace.enabled == true)

    -- All 3 settings enabled
    local previousRefreshCalls = refreshCalls
    controls.applyReplace.onclick()
    assert(refreshCalls == previousRefreshCalls + 1, "Apply must refresh the canvas")
    assert(#recolorCalls == 1)
    assert(
      recolorCalls[1].fg == "#ff0080ff"
        and recolorCalls[1].bg == "#001020ff"
        and recolorCalls[1].glyph == "Z"
        and recolorCalls[1].flags == 0x20000000
    )

    -- 2 of 3 settings enabled (Foreground + Glyph); fg and bg stay enabled at all times
    d.data.changeBg = false
    controls.changeBg.onclick()
    assert(modified.fg == nil and modified.bg == nil)
    controls.applyReplace.onclick()
    assert(#recolorCalls == 2)
    assert(
      recolorCalls[2].fg == "#ff0080ff"
        and recolorCalls[2].bg == nil
        and recolorCalls[2].glyph == "Z"
    )

    -- 1 of 3 settings enabled (Background only); fg and bg stay enabled at all times
    d.data.changeFg = false
    d.data.changeBg = true
    d.data.changeGlyph = false
    controls.changeGlyph.onclick()
    controls.applyReplace.onclick()
    assert(#recolorCalls == 3)
    assert(
      recolorCalls[3].fg == nil
        and recolorCalls[3].bg == "#001020ff"
        and recolorCalls[3].glyph == nil
        and recolorCalls[3].flags == nil
    )

    -- Attempting to uncheck the last enabled checkbox keeps it checked
    d.data.changeFg = false
    d.data.changeBg = false
    d.data.changeGlyph = false
    controls.changeBg.onclick()
    assert(d.data.changeBg == true)
    assert(modified.changeBg and modified.changeBg.selected == true)
    assert(modified.applyReplace and modified.applyReplace.enabled == true)

    -- A changed primary stamp is used when applying again.
    d.data.changeFg = true
    d.data.changeBg = false
    d.data.changeGlyph = true
    primaryStamp = { fg = "#123456ff", bg = "#abcdef12", glyph = "A", flags = 0 }
    controls.changeGlyph.onclick()
    assert(modified.applyReplace and modified.applyReplace.enabled == true)
    controls.applyReplace.onclick()
    assert(#recolorCalls == 4)
    assert(
      recolorCalls[4].fg == "#123456ff"
        and recolorCalls[4].bg == nil
        and recolorCalls[4].glyph == "A"
        and recolorCalls[4].flags == 0
    )
    primaryStamp = { fg = "#123456ff", bg = "#abcdef12", glyph = "", primaryEmpty = true }
    controls.changeGlyph.onclick()
    assert(modified.applyReplace.enabled == false)
    assert(closedCount == 0, "Replace selection dialog should stay open after applying")
  end)

  test("replace selection dialog opens with empty selection and keeps apply disabled", function()
    local sprite = { width = 16, height = 8, isValid = true, selection = { isEmpty = true } }
    local layer = { meta = { fontProfileId = "p1" } }
    local cellsInSelection = {
      count = 0,
      minCol = 0,
      minRow = 0,
      columns = 0,
      rows = 0,
      cells = {},
    }
    package.loaded["src.document.model"] = {
      meta = function(v)
        return v.meta
      end,
    }
    package.loaded["src.document.profile"] = {
      index = function()
        return {
          profile = { cellWidth = 8, cellHeight = 8 },
          glyphs = { ["A"] = { meta = {}, tile = { image = {} } } },
        }
      end,
      colorize = function()
        return {}
      end,
    }
    package.loaded["src.document.edit"] = {
      selectedCells = function()
        return cellsInSelection
      end,
      recolor = function() end,
    }
    package.loaded["src.ui.document_workflow"] = nil
    local DocumentWorkflow = require("src.ui.document_workflow")

    local controls, modified = {}, {}
    local d
    d = {
      data = {
        changeFg = true,
        changeBg = true,
        changeGlyph = true,
        fg = { red = 255, green = 0, blue = 128, alpha = 255 },
        bg = { red = 0, green = 16, blue = 32, alpha = 255 },
        glyph = "A",
      },
      modify = function(_, arg)
        modified[arg.id] = arg
      end,
      repaint = function() end,
      close = function() end,
      show = function(self)
        return self
      end,
    }
    setmetatable(d, {
      __index = function(_, name)
        return function(self, arg)
          if type(arg) == "table" and arg.id then
            controls[arg.id] = arg
          end
          return self
        end
      end,
    })

    local workflow = DocumentWorkflow.new({
      drawing = {
        target = function()
          return sprite, layer
        end,
        snapshot = function()
          return { fg = "#ffffffff", bg = "#000000ff", glyph = "A" }
        end,
      },
      dialog = function()
        return d
      end,
      guard = function(fn)
        return fn
      end,
    })

    workflow:replaceSelection()
    assert(controls.applyReplace and controls.applyReplace.enabled == false)
    assert(
      modified.glyphPreviewInfo
        and modified.glyphPreviewInfo.text == "No occupied cells in the selection."
    )

    -- Making a selection updates preview and enables Apply automatically on tick
    cellsInSelection = {
      count = 1,
      minCol = 0,
      minRow = 0,
      columns = 1,
      rows = 1,
      cells = {
        {
          col = 0,
          row = 0,
          glyphKey = "A",
          foregroundRGBA = "#111111ff",
          backgroundRGBA = "#222222ff",
          flags = 0,
        },
      },
    }
    workflow.tick()
    assert(modified.applyReplace and modified.applyReplace.enabled == true)
    assert(
      modified.glyphPreviewInfo and modified.glyphPreviewInfo.text:find("1 selected cell", 1, true)
    )

    -- Clearing selection via tick updates preview and disables Apply
    cellsInSelection = { count = 0, columns = 0, rows = 0, cells = {} }
    workflow.tick()
    assert(modified.applyReplace and modified.applyReplace.enabled == false)
    assert(
      modified.glyphPreviewInfo
        and modified.glyphPreviewInfo.text == "No occupied cells in the selection."
    )
  end)

  test("replace selection timer updates preview dynamically and stops on close", function()
    local sprite = { width = 16, height = 8, isValid = true, selection = { isEmpty = true } }
    local layer = { meta = { fontProfileId = "p1" } }
    local cellsInSelection = { count = 0, columns = 0, rows = 0, cells = {} }
    local timerTick, timerStopped, onclose = nil, false, nil
    local primaryStamp = { fg = "#ffffffff", bg = "#000000ff", glyph = "A" }
    local controls, modified = {}, {}
    local d
    d = {
      data = {
        changeFg = true,
        changeBg = true,
        changeGlyph = true,
        fg = { red = 255, green = 0, blue = 128, alpha = 255 },
        bg = { red = 0, green = 16, blue = 32, alpha = 255 },
        glyph = "A",
      },
      modify = function(_, arg)
        modified[arg.id] = arg
      end,
      repaint = function() end,
      close = function()
        onclose()
      end,
      show = function(self)
        return self
      end,
    }
    setmetatable(d, {
      __index = function(_, name)
        return function(self, arg)
          if type(arg) == "table" and arg.id then
            controls[arg.id] = arg
          end
          return self
        end
      end,
    })

    package.loaded["src.document.model"] = {
      meta = function(v)
        return v.meta
      end,
    }
    package.loaded["src.document.profile"] = {
      index = function()
        return {
          profile = { cellWidth = 8, cellHeight = 8 },
          glyphs = { ["A"] = { meta = {}, tile = { image = {} } } },
        }
      end,
      colorize = function()
        return {}
      end,
    }
    package.loaded["src.document.edit"] = {
      selectedCells = function()
        return cellsInSelection
      end,
      recolor = function() end,
    }
    package.loaded["src.ui.document_workflow"] = nil
    local DocumentWorkflow = require("src.ui.document_workflow")

    local workflow = DocumentWorkflow.new({
      drawing = {
        target = function()
          return sprite, layer
        end,
        snapshot = function()
          return primaryStamp
        end,
      },
      dialog = function(_, options)
        onclose = options.onclose
        return d
      end,
      timer = function(opts)
        timerTick = opts.ontick
        return {
          start = function() end,
          stop = function()
            timerStopped = true
          end,
        }
      end,
      guard = function(fn)
        return fn
      end,
    })

    workflow:replaceSelection()
    assert(type(timerTick) == "function", "Timer should be initialized")
    assert(controls.applyReplace and controls.applyReplace.enabled == false)

    -- Selecting cells while dialog is open triggers dynamic update via timer
    cellsInSelection = {
      count = 2,
      minCol = 0,
      minRow = 0,
      columns = 2,
      rows = 1,
      cells = {
        {
          col = 0,
          row = 0,
          glyphKey = "A",
          foregroundRGBA = "#111111ff",
          backgroundRGBA = "#222222ff",
          flags = 0,
        },
        {
          col = 1,
          row = 0,
          glyphKey = "B",
          foregroundRGBA = "#333333ff",
          backgroundRGBA = "#444444ff",
          flags = 0,
        },
      },
    }
    timerTick()
    assert(modified.applyReplace and modified.applyReplace.enabled == true)
    assert(
      modified.glyphPreviewInfo and modified.glyphPreviewInfo.text:find("2 selected cells", 1, true)
    )
    modified.glyphPreviewInfo = nil
    primaryStamp = { fg = "#123456ff", bg = "#000000ff", glyph = "A" }
    timerTick()
    assert(modified.glyphPreviewInfo, "Changing the primary stamp must refresh the preview")

    -- Closing dialog stops timer
    d:close()
    assert(timerStopped == true)
  end)

  test("replace preview avoids repeat scans and preserves hidden selections", function()
    local oldSelection, oldSprite, oldLayer, oldCommand, oldEvents, oldUI =
      Selection, app.sprite, app.layer, app.command, app.events, app.isUIAvailable
    local bounds = { x = 0, y = 0, width = 16, height = 8 }
    local maskMeta = {
      __eq = function(a, b)
        return a.shape == b.shape
      end,
    }
    local live = setmetatable({ bounds = bounds, shape = 1 }, maskMeta)
    Selection = function()
      return setmetatable({
        add = function(self, other)
          self.shape = other.shape
        end,
      }, maskMeta)
    end
    local callbacks, spriteCallbacks, stopped, closeCallback = {}, {}, false, nil
    local sprite = { isValid = true, selection = live, events = {} }
    function sprite.events:on(name, fn)
      spriteCallbacks[name] = fn
      return name
    end
    function sprite.events:off(name)
      spriteCallbacks[name] = nil
    end
    local layer = { meta = { fontProfileId = "p1" } }
    app.sprite, app.layer, app.isUIAvailable = sprite, layer, true
    app.command = { DeselectMask = { enabled = true }, ReselectMask = { enabled = false } }
    app.events = {
      on = function(_, name, fn)
        callbacks[name] = fn
        return name
      end,
      off = function(_, name)
        callbacks[name] = nil
      end,
    }
    package.loaded["src.document.model"] = {
      meta = function(value)
        return value.meta
      end,
    }
    package.loaded["src.document.profile"] = {
      index = function()
        return { profile = { cellWidth = 8, cellHeight = 8 }, glyphs = { A = { meta = {} } } }
      end,
      colorize = function()
        return {}
      end,
    }
    local scans, validations, failing, pause, resumed = 0, 0, false, false, false
    package.loaded["src.document.edit"] = {
      selectedCells = function(_, _, _, options)
        assert(options.selection and not rawequal(options.selection, live))
        scans = scans + 1
        if pause then
          coroutine.yield()
          resumed = true
        end
        if failing then
          error("invalid text layer")
        end
        if not options.validated then
          validations = validations + 1
        end
        options.validationComplete = true
        return {
          count = 1,
          minCol = 0,
          minRow = 0,
          columns = 1,
          rows = 1,
          cells = {
            {
              col = 0,
              row = 0,
              glyphKey = "A",
              foregroundRGBA = "#ffffffff",
              backgroundRGBA = "#000000ff",
              flags = 0,
            },
          },
        }
      end,
      recolor = function() end,
    }
    package.loaded["src.ui.document_workflow"] = nil
    local workflow = require("src.ui.document_workflow")
    local controls, modified, tick = {}, {}, nil
    local dialog = { data = { changeFg = true, changeBg = true, changeGlyph = true } }
    function dialog:modify(arg)
      modified[arg.id] = arg
    end
    function dialog:repaint() end
    function dialog:close()
      closeCallback()
    end
    setmetatable(dialog, {
      __index = function(_, name)
        return function(self, arg)
          if type(arg) == "table" and arg.id then
            controls[arg.id] = arg
          end
          return self
        end
      end,
    })
    local stamp = { fg = "#ffffffff", bg = "#000000ff", glyph = "A", flags = 0 }
    local instance = workflow.new({
      drawing = {
        target = function()
          return sprite, layer
        end,
        snapshot = function()
          return stamp
        end,
      },
      dialog = function(_, options)
        closeCallback = options.onclose
        return dialog
      end,
      timer = function(options)
        tick = options.ontick
        return {
          start = function() end,
          stop = function()
            stopped = true
          end,
        }
      end,
      guard = function(fn)
        return fn
      end,
    })
    instance:replaceSelection()
    assert(scans == 1 and modified.applyReplace.enabled)
    tick()
    tick()
    assert(scans == 1, "unchanged selection was rescanned")
    controls.changeFg.onclick()
    stamp.fg = "#123456ff"
    tick()
    assert(scans == 1, "preview-only changes rescanned cells")
    live.bounds = { x = 8, y = 0, width = 16, height = 8 }
    tick()
    assert(scans == 2, "moved selection was missed")
    live.shape = 2
    tick()
    assert(scans == 3, "selection shape change was missed")
    assert(validations == 1, "selection changes repeated document validation")
    live.isEmpty = true
    callbacks.aftercommand({ name = "DeselectMask" })
    tick()
    assert(scans == 3 and not modified.applyReplace.enabled)
    live.isEmpty = false
    callbacks.aftercommand({ name = "ReselectMask" })
    tick()
    assert(scans == 4 and modified.applyReplace.enabled)
    spriteCallbacks.change()
    assert(not modified.applyReplace.enabled)
    tick()
    assert(scans == 5 and modified.applyReplace.enabled)
    assert(validations == 2, "document change did not invalidate validation")
    failing = true
    spriteCallbacks.change()
    tick()
    assert(scans == 6 and not modified.applyReplace.enabled)
    assert(modified.glyphPreviewInfo.text == "Selection unavailable.")
    tick()
    assert(scans == 6, "unchanged invalid data was repeatedly rescanned")
    failing = false
    spriteCallbacks.change()
    tick()
    assert(scans == 7 and modified.applyReplace.enabled)
    pause = true
    live.shape = 3
    tick()
    assert(scans == 8 and not modified.applyReplace.enabled)
    pause = false
    live.shape = 4
    tick()
    assert(scans == 9 and modified.applyReplace.enabled and not resumed, "stale scan was resumed")
    pause = true
    live.shape = 5
    tick()
    assert(scans == 10 and not modified.applyReplace.enabled)
    dialog:close()
    assert(stopped and not next(callbacks) and not next(spriteCallbacks) and not resumed)
    Selection, app.sprite, app.layer, app.command, app.events, app.isUIAvailable =
      oldSelection, oldSprite, oldLayer, oldCommand, oldEvents, oldUI
  end)

  test("selectedCells captures occupied cells inside the selection bounding box", function()
    package.loaded["src.document.model"] = {
      editable = function() end,
      geometry = function()
        return { cellWidth = 8, cellHeight = 8 }
      end,
    }
    package.loaded["src.document.validate"] = {
      requireValid = function() end,
    }
    package.loaded["src.document.profile"] = {
      decode = function(_, tile)
        if tile == 0 then
          return nil, 0
        end
        return {
          glyphKey = tile == 1 and "A" or "B",
          foregroundRGBA = "#ffffffff",
          backgroundRGBA = "#000000ff",
        },
          tile == 2 and 0x10000000 or 0
      end,
    }
    package.loaded["src.document.edit"] = nil
    local Edit = require("src.document.edit")

    local pixels = {
      { x = 0, y = 0, value = 1 }, -- outside selection (center 4,4)
      { x = 2, y = 1, value = 2 }, -- inside selection (center 20,12)
      { x = 1, y = 1, value = 1 }, -- inside selection (center 12,12)
      { x = 1, y = 2, value = 0 }, -- inside selection, but empty (tile 0)
    }
    local cel = {
      position = { x = 0, y = 0 },
      image = {
        pixels = function()
          local i = 0
          return function()
            i = i + 1
            local p = pixels[i]
            if not p then
              return nil
            end
            return setmetatable({ x = p.x, y = p.y }, {
              __call = function()
                return p.value
              end,
            })
          end
        end,
      },
    }
    local sprite = {
      width = 32,
      height = 32,
      selection = {
        isEmpty = false,
        contains = function(_, cx, cy)
          return cx >= 8 and cx < 24 and cy >= 8 and cy < 24
        end,
      },
    }
    local layer = {
      cel = function()
        return cel
      end,
    }
    local result = Edit.selectedCells(sprite, layer, 1)
    assert(result.count == 2)
    assert(result.minCol == 1 and result.minRow == 1)
    assert(result.columns == 2 and result.rows == 1)
    assert(result.cells[1].col == 1 and result.cells[1].glyphKey == "A")
    assert(
      result.cells[2].col == 2
        and result.cells[2].glyphKey == "B"
        and result.cells[2].flags == 0x10000000
    )
  end)

  test("replacement applies primary orientation and preserves it for color-only edits", function()
    local captured
    package.loaded["src.document.model"] = {
      editable = function()
        return "font"
      end,
    }
    package.loaded["src.document.profile"] = {
      orientedTile = function(_, _, _, _, _, flags)
        captured = flags
        return 1
      end,
    }
    package.loaded["src.document.edit"] = nil
    local Edit = require("src.document.edit")
    rawset(Edit, "change", function(_, _, _, transform)
      return transform({ glyphKey = "A", foregroundRGBA = "fg", backgroundRGBA = "bg" }, 0x10000000)
    end)
    for _, flags in ipairs({ 0, 0x10000000, 0x20000000, 0x60000000 }) do
      Edit.recolor({}, {}, 1, nil, nil, "A", flags)
      assert(captured == flags)
    end
    Edit.recolor({}, {}, 1, "fg", nil, nil)
    assert(captured == 0x10000000)
  end)

  test(
    "replace selection opened without selection updates when marquee selection is made",
    function()
      local oldSelection, oldSprite, oldLayer, oldUI =
        Selection, app.sprite, app.layer, app.isUIAvailable
      local bounds = { x = 0, y = 0, width = 16, height = 8 }
      local maskMeta = {
        __eq = function(a, b)
          return a.shape == b.shape
        end,
      }
      local live = setmetatable({ bounds = bounds, shape = 1, isEmpty = true }, maskMeta)
      Selection = function()
        return setmetatable({
          add = function(self, other)
            self.shape = other.shape
          end,
        }, maskMeta)
      end
      local sprite = { isValid = true, selection = live }
      local layer = { meta = { fontProfileId = "p1" } }
      app.sprite, app.layer, app.isUIAvailable = sprite, layer, true
      package.loaded["src.document.model"] = {
        meta = function(value)
          return value.meta
        end,
      }
      package.loaded["src.document.profile"] = {
        index = function()
          return { profile = { cellWidth = 8, cellHeight = 8 }, glyphs = { A = { meta = {} } } }
        end,
        colorize = function()
          return {}
        end,
      }
      local scans = 0
      package.loaded["src.document.edit"] = {
        selectedCells = function()
          scans = scans + 1
          return {
            count = 1,
            minCol = 0,
            minRow = 0,
            columns = 1,
            rows = 1,
            cells = {
              {
                col = 0,
                row = 0,
                glyphKey = "A",
                foregroundRGBA = "#ffffffff",
                backgroundRGBA = "#000000ff",
                flags = 0,
              },
            },
          }
        end,
        recolor = function() end,
      }
      package.loaded["src.ui.document_workflow"] = nil
      local workflow = require("src.ui.document_workflow")
      local modified, tick = {}, nil
      local dialog = { data = { changeFg = true, changeBg = true, changeGlyph = true } }
      function dialog:modify(arg)
        modified[arg.id] = arg
      end
      function dialog:repaint() end
      function dialog:close() end
      setmetatable(dialog, {
        __index = function(_, name)
          return function(self, arg)
            return self
          end
        end,
      })
      local stamp = { fg = "#ffffffff", bg = "#000000ff", glyph = "A", flags = 0 }
      local instance = workflow.new({
        drawing = {
          target = function()
            return sprite, layer
          end,
          snapshot = function()
            return stamp
          end,
        },
        dialog = function()
          return dialog
        end,
        timer = function(options)
          tick = options.ontick
          return {
            start = function() end,
            stop = function() end,
          }
        end,
        guard = function(fn)
          return fn
        end,
      })
      instance:replaceSelection()
      assert(scans == 0)
      assert(not modified.applyReplace or modified.applyReplace.enabled == false)
      assert(modified.glyphPreviewInfo.text == "Select an Asemode layer and a visible selection.")

      -- Now user selects with marquee tool
      live.isEmpty = false
      tick()
      assert(scans == 1)
      assert(modified.applyReplace and modified.applyReplace.enabled == true)
      assert(modified.glyphPreviewInfo.text:find("1 selected cell", 1, true))

      -- Deselecting via marquee tool returns to suspended state
      live.isEmpty = true
      tick()
      assert(scans == 1)
      assert(modified.applyReplace.enabled == false)
      assert(modified.glyphPreviewInfo.text == "Select an Asemode layer and a visible selection.")

      Selection, app.sprite, app.layer, app.isUIAvailable = oldSelection, oldSprite, oldLayer, oldUI
    end
  )

  for _, name in ipairs(modules) do
    package.loaded[name] = saved[name]
  end
  app, Rectangle, Color = oldApp, oldRectangle, oldColor
end
