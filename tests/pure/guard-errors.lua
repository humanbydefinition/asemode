return function(test)
  local previousApp = app
  app = {
    pixelColor = { TILE_XFLIP = 0x10000000, TILE_YFLIP = 0x20000000, TILE_DFLIP = 0x40000000 },
    fs = {
      filePath = require("tests.pure.filesystem").filePath,
      joinPath = require("tests.pure.filesystem").joinPath,
    },
  }
  local Controller = require("src.ui.controller")
  local controller = Controller.new({ preferences = {} })

  test("guarded errors still reach the console and alert", function()
    local previousPrint, logged, alert = print, nil, nil
    print = function(message)
      logged = message
    end
    app.isUIAvailable = true
    app.alert = function(details)
      alert = details
    end
    controller:guard(function()
      error("example failure")
    end)()
    print = previousPrint
    assert(logged and logged:find("[Asemode error]", 1, true))
    assert(logged:find("example failure", 1, true))
    assert(alert and alert.title == "Asemode")
    assert(table.concat(alert.text, " "):find("example failure", 1, true))
  end)

  test("a timer failure cannot open nested error alerts", function()
    local previousPrint, alerts, callback = print, 0
    print = function() end
    app.isUIAvailable = true
    app.alert = function()
      alerts = alerts + 1
      if alerts < 5 then
        callback()
      end
    end
    callback = controller:guard(function()
      error("document is locked")
    end)
    callback()
    print = previousPrint
    assert(alerts == 1, "timer errors opened nested alerts: " .. alerts)
  end)

  test("background failures are logged once and never open an alert", function()
    local previousPrint, logs, alerts, failing = print, 0, 0, true
    print = function()
      logs = logs + 1
    end
    app.isUIAvailable = true
    app.alert = function()
      alerts = alerts + 1
    end
    local callback = controller:backgroundGuard(function()
      if failing then
        error("document is locked")
      end
    end)
    callback()
    callback()
    failing = false
    callback()
    failing = true
    callback()
    print = previousPrint
    assert(logs == 2 and alerts == 0)
  end)

  app = previousApp
end
