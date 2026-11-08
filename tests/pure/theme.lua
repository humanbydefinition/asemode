return function(test)
  local Theme = require("src.ui.theme")

  test("theme signature changes with theme colors", function()
    local colors = {}
    for _, id in ipairs({
      "window_face",
      "editor_face",
      "text",
      "selected",
      "selected_text",
      "button_normal_text",
      "button_hot_text",
      "button_selected_text",
      "disabled",
    }) do
      colors[id] = { red = 1, green = 2, blue = 3, alpha = 255 }
    end
    local first = Theme.signature({ color = colors })
    assert(first == Theme.signature({ color = colors }))
    colors.selected.red = 4
    assert(first ~= Theme.signature({ color = colors }))
  end)

  test("open dialogs repaint on theme changes and stop watching after close", function()
    local previousApp, previousDialog, previousTimer = app, Dialog, Timer
    local colors = {}
    for _, id in ipairs({
      "window_face",
      "editor_face",
      "text",
      "selected",
      "selected_text",
      "button_normal_text",
      "button_hot_text",
      "button_selected_text",
      "disabled",
    }) do
      colors[id] = { red = 1, green = 2, blue = 3, alpha = 255 }
    end
    app = {
      isUIAvailable = true,
      theme = { color = colors },
      pixelColor = { TILE_XFLIP = 1, TILE_YFLIP = 2, TILE_DFLIP = 4 },
      fs = {
        filePath = require("tests.pure.filesystem").filePath,
        joinPath = require("tests.pure.filesystem").joinPath,
      },
    }
    local timer
    Timer = function(options)
      timer = { tick = options.ontick }
      function timer:start() end
      function timer:stop()
        self.stopped = true
      end
      return timer
    end
    Dialog = function(options)
      local d = { paints = 0 }
      function d:repaint()
        self.paints = self.paints + 1
      end

      function d:close()
        options.onclose()
      end
      return d
    end
    local controller = require("src.ui.controller").new({ preferences = {} })
    local first, second = controller:dialog("First"), controller:dialog("Second")
    timer.tick()
    assert(first.paints == 0 and second.paints == 0)
    colors.selected.red = 4
    timer.tick()
    assert(first.paints == 1 and second.paints == 1)
    first:close()
    colors.text.red = 5
    timer.tick()
    assert(first.paints == 1 and second.paints == 2 and not timer.stopped)
    second:close()
    assert(timer.stopped and controller.themeTimer == nil)
    app, Dialog, Timer = previousApp, previousDialog, previousTimer
  end)

  test("singleton dialogs refocus when already open and release key on close", function()
    local previousApp, previousDialog, previousTimer = app, Dialog, Timer
    app = {
      isUIAvailable = false,
      pixelColor = { TILE_XFLIP = 1, TILE_YFLIP = 2, TILE_DFLIP = 4 },
      fs = {
        filePath = require("tests.pure.filesystem").filePath,
        joinPath = require("tests.pure.filesystem").joinPath,
      },
    }
    local shows, created = 0, 0
    Dialog = function(options)
      created = created + 1
      local d = { paints = 0 }
      function d:show()
        shows = shows + 1
        return self
      end
      function d:close()
        if options.onclose then
          options.onclose()
        end
      end
      return d
    end
    Timer = function()
      return { start = function() end, stop = function() end }
    end
    local controller = require("src.ui.controller").new({ preferences = {} })
    assert(controller:focusDialog("test") == false)
    local first = controller:dialog("Test Dialog", { singleton = "test" })
    assert(controller:focusDialog("test") == true)
    assert(shows == 1)
    assert(created == 1)
    first:close()
    assert(controller:focusDialog("test") == false)
    app, Dialog, Timer = previousApp, previousDialog, previousTimer
  end)
end
