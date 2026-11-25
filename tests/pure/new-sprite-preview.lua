return function(test)
  test("new sprite preview follows font and grid changes before creation", function()
    local oldApp = app
    app = { pixelColor = { TILE_XFLIP = 1, TILE_YFLIP = 2, TILE_DFLIP = 4 }, isUIAvailable = true }
    local model = require("src.document.model")
    local oldCreate = model.create
    local created
    rawset(model, "create", function(job, cols, rows)
      created = { width = job.profile.cellWidth * cols, height = job.profile.cellHeight * rows }
    end)
    local timers, selected = {}, { kind = "bundled", id = "atascii" }
    local dialog, create, fontChanged, measurements, renders
    measurements, renders = 0, 0
    local library = {
      job = function(_, font, options)
        assert(font == selected)
        if font.id == "missing" then
          error("Missing font")
        end
        measurements = measurements + 1
        return {
          profile = { cellWidth = options.pixelSize, cellHeight = options.pixelSize * 2 },
          glyphs = {},
          finish = function(self)
            renders = renders + 1
            return self
          end,
        }
      end,
    }
    local function makeDialog(_, options)
      dialog = { data = {}, enabled = {} }
      for _, name in ipairs({ "label", "show" }) do
        dialog[name] = function(self)
          return self
        end
      end
      function dialog:button(arg)
        create = arg.onclick
        self.enabled[arg.id] = arg.enabled
        return self
      end
      function dialog:modify(arg)
        if arg.enabled ~= nil then
          self.enabled[arg.id] = arg.enabled
        end
        return self
      end
      function dialog:close()
        options.onclose()
      end
      return dialog
    end
    local changes = {}
    local controls = {
      addNumericInput = function(_, d, id, _, value, options)
        d.data[id], changes[id] = value, options.onchange
      end,
      addFontSizeInput = function(_, d, value, options)
        d.data.size, changes.size = value, options.onchange
      end,
      addBackgroundInput = function()
        return function()
          return "transparent"
        end
      end,
      clampInt = require("src.ui.controls").new().clampInt,
    }
    local workflow = require("src.ui.document_workflow").new({
      preferences = {},
      library = library,
      dialog = makeDialog,
      controls = controls,
      font = {
        libraryControl = function(_, _, _, _, _, onchange)
          fontChanged = onchange
          return {
            selected = function()
              return selected
            end,
          }
        end,
        defaultBrushes = function()
          return nil, nil
        end,
      },
      drawing = { setImportedStamps = function() end, prepareBoth = function() end },
      timer = function(options)
        local t = { active = false }
        function t:start()
          self.active = true
        end
        function t:stop()
          self.active = false
        end
        t.tick = options.ontick
        timers[#timers + 1] = t
        return t
      end,
      guard = function(fn)
        return fn
      end,
      positionPanel = function() end,
      openPanel = function() end,
    })
    workflow:newDocument()
    assert(not dialog.enabled.createSprite and timers[#timers].active)
    timers[#timers].tick()
    assert(dialog.enabled.createSprite and measurements == 1 and renders == 0)
    dialog.data.cols, dialog.data.rows = "3", "2"
    changes.cols()
    changes.rows()
    assert(measurements == 1, "changing the grid must reuse font measurements")
    dialog.data.size = "16"
    changes.size()
    local oldTimer = timers[#timers]
    selected = { kind = "bundled", id = "other" }
    fontChanged()
    assert(not oldTimer.active and not dialog.enabled.createSprite)
    timers[#timers].tick()
    assert(measurements == 2 and dialog.enabled.createSprite)
    dialog.data.cols = ""
    changes.cols()
    assert(not dialog.enabled.createSprite)
    dialog.data.cols, dialog.data.size = "1024", "128"
    changes.size()
    timers[#timers].tick()
    assert(not dialog.enabled.createSprite, "oversized canvas must not be created")
    selected = { kind = "bundled", id = "missing" }
    fontChanged()
    timers[#timers].tick()
    assert(not dialog.enabled.createSprite, "unavailable font must not be created")
    selected = { kind = "bundled", id = "other" }
    dialog.data.cols, dialog.data.size = "3", "16"
    fontChanged()
    timers[#timers].tick()
    create()
    assert(created.width == 48 and created.height == 64 and renders == 1)
    assert(not timers[#timers].active)
    workflow:newDocument()
    local pending = timers[#timers]
    local count = measurements
    dialog:close()
    assert(not pending.active)
    pending.tick()
    assert(measurements == count, "closed dialogs must not continue measuring")
    rawset(model, "create", oldCreate)
    app = oldApp
  end)
end
