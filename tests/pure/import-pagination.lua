return function(test)
  test("import options page layers without losing selections or font overrides", function()
    local names = {
      "src.ui.portable",
      "src.document.portable_import",
      "src.document.portable_export",
      "src.document.model",
      "src.document.profile",
    }
    local saved = {}
    for _, name in ipairs(names) do
      saved[name] = package.loaded[name]
    end
    local oldApp = app
    app = { isUIAvailable = false, sprite = nil }
    local chosen
    local layers = {}
    for i = 1, 5 do
      layers[i] =
        { id = "Layer " .. i, grid = { cols = 1, rows = 1, cellWidth = 8, cellHeight = 8 } }
    end
    local document = { frames = { { layers = layers } } }
    local import = {
      read = function()
        return {
          ok = true,
          document = document,
          warnings = {},
          invalidFonts = { [3] = { id = "bad" } },
        }
      end,
      captureTarget = function()
        return { mode = "new" }
      end,
      prepareImport = function(_, options, target)
        chosen = options
        return {
          target = target,
          layers = {},
          layerVariants = {},
          fonts = {},
          frames = { 100 },
          maxCols = 1,
          maxRows = 1,
          geometry = { cellWidth = 8, cellHeight = 8 },
          diagnostics = {},
        }
      end,
    }
    package.loaded["src.document.portable_import"] = import
    package.loaded["src.document.portable_export"] = {}
    package.loaded["src.document.model"] = {}
    package.loaded["src.document.profile"] = {}
    package.loaded["src.ui.portable"] = nil
    local fonts = {
      { id = "a", kind = "bundled", name = "ATASCII", label = "ATASCII" },
      { id = "b", kind = "bundled", name = "BESCII", label = "BESCII" },
    }
    local dialogs = {}
    local function dialog(title)
      local d = { title = title, data = {}, widgets = {}, shown = {} }
      local function add(self, spec)
        if spec.id then
          self.widgets[spec.id] = spec
          if spec.option ~= nil then
            self.data[spec.id] = spec.option
          end
          if spec.selected ~= nil then
            self.data[spec.id] = spec.selected
          end
          if spec.text ~= nil and (spec.id == "page" or spec.id == "file") then
            self.data[spec.id] = spec.text
          end
        end
        return self
      end

      function d:file(spec)
        return add(self, spec)
      end

      function d:number(spec)
        local result = add(self, spec)
        self.data[spec.id] = tonumber(spec.text)
        return result
      end

      function d:label(spec)
        return add(self, spec)
      end

      function d:separator(spec)
        return add(self, spec)
      end

      function d:button(spec)
        return add(self, spec)
      end

      function d:check(spec)
        return add(self, spec)
      end

      function d:combobox(spec)
        return add(self, spec)
      end

      function d:samerow()
        return self
      end

      function d:newrow()
        return self
      end

      function d:show(spec)
        self.shown = spec
        return self
      end

      function d:close()
        self.closed = true
      end

      function d:modify(spec)
        local widget = assert(self.widgets[spec.id], "Unknown widget " .. tostring(spec.id))
        for key, value in pairs(spec) do
          widget[key] = value
        end
        if spec.selected ~= nil then
          self.data[spec.id] = spec.selected
        end
        if spec.option ~= nil then
          self.data[spec.id] = spec.option
        end
        if
          spec.text ~= nil and (spec.id == "page" or spec.id == "width" or spec.id == "height")
        then
          self.data[spec.id] = tonumber(spec.text)
        end
        return self
      end
      dialogs[#dialogs + 1] = d
      return d
    end
    local library = {
      revision = 1,
      catalog = function()
        return fonts
      end,
      portableReference = function()
        return nil
      end,
      job = function(_, font)
        return { font = font }
      end,
    }
    local controls = {
      setNumericEnabled = require("src.ui.controls").new().setNumericEnabled,
      addFontSizeInput = function(_, d)
        d:number({ id = "size", text = "8" })
        d:button({ id = "sizeIncrease" })
        d:button({ id = "sizeDecrease" })
      end,
      addNumericInput = function(_, d, id, _, value)
        d:number({ id = id, text = value })
        d:button({ id = id .. "Increase" })
        d:button({ id = id .. "Decrease" })
      end,
    }
    local deps = {
      dialog = dialog,
      library = library,
      controls = controls,
      guard = function(fn)
        return fn
      end,
      drawing = { flush = function() end, flushDeferred = function() end },
      tasks = {
        isActive = function()
          return false
        end,
        start = function(_, task, callbacks)
          callbacks.complete(task:finish())
          return { cancel = function() end }
        end,
      },
    }
    local ok, err = xpcall(function()
      require("src.ui.portable").new(deps):importDocument()
      local open = dialogs[1]
      open.data.file = "tests/test-documents/many-frames-and-layers.textmode.json"
      open.widgets.read.onclick()
      local d = dialogs[2]
      assert(d.data.page == 1)
      assert(
        not d.widgets.prepare.enabled,
        "An unresolved font on another page must prevent preparation"
      )
      d.widgets.previousPage.onclick()
      assert(d.data.page == 3, "Previous must wrap to the last page")
      d.widgets.nextPage.onclick()
      assert(d.data.page == 1, "Next must wrap to the first page")

      d.data.font1 = "BESCII"
      d.widgets.font1.onchange()
      d.data.source2 = false
      d.widgets.source2.onclick()
      d.widgets.nextPage.onclick()
      assert(d.data.page == 2 and d.data.font1 == "Choose a font")
      d.data.font1 = "ATASCII"
      d.widgets.font1.onchange()
      assert(d.widgets.prepare.enabled, "Choosing the missing font must enable preparation")
      d.widgets.previousPage.onclick()
      assert(d.data.page == 1 and d.data.font1 == "BESCII" and d.data.source2 == false)
      d.data.page = 3
      d.widgets.page.onchange()
      assert(d.data.page == 3)
      d.widgets.prepare.onclick()
      assert(
        chosen
          and chosen.selected[1]
          and not chosen.selected[2]
          and chosen.selected[3]
          and chosen.selected[5]
      )
      assert(
        chosen.jobs[1].font.id == "b" and chosen.jobs[3].font.id == "a" and chosen.substitutes[3]
      )
      document = { frames = { { layers = { layers[1] } } } }
      require("src.ui.portable").new(deps):importDocument()
      dialogs[4].data.file = "tests/test-documents/many-frames-and-layers.textmode.json"
      dialogs[4].widgets.read.onclick()
      local single = dialogs[5]
      assert(single.widgets.prepare.enabled)
    end, debug.traceback)
    for _, name in ipairs(names) do
      package.loaded[name] = saved[name]
    end
    app = oldApp
    assert(ok, err)
  end)
end
