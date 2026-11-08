-- Runs only from the documentation screenshot command, inside an isolated Aseprite profile.
local root, output = app.params.root, app.params.output
local expectedTheme = app.params.theme == "dark" and "default-dark" or "default"
assert(app.preferences.theme.selected == expectedTheme, "Aseprite did not load the requested theme")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Harness = require("scripts.screenshots.lib.harness")
local Fixtures = require("scripts.screenshots.lib.fixtures")

local harness = Harness.new({
  root = root,
  output = output,
  suites = app.params.suites,
  only = app.params.only,
})

local Controller = require("src.ui.controller")
local controller = Controller.new({ preferences = { aboutAnimation = false } })
local fixtures = Fixtures.setup(controller, root, output)

local SUITE_MODULES = {
  ["panel"] = "scripts.screenshots.suites.panel",
  ["about-settings"] = "scripts.screenshots.suites.about_settings",
  ["document-grid"] = "scripts.screenshots.suites.document_grid",
  ["fonts"] = "scripts.screenshots.suites.fonts",
  ["portable"] = "scripts.screenshots.suites.portable",
  ["alerts"] = "scripts.screenshots.suites.alerts",
}

local function run()
  local ctx = {
    harness = harness,
    controller = controller,
    fixtures = fixtures,
  }
  for _, suiteName in ipairs(harness.requestedSuites) do
    local moduleName =
      assert(SUITE_MODULES[suiteName], "Unknown screenshot suite: " .. tostring(suiteName))
    harness:recordProgress("suite:" .. suiteName)
    fixtures:reset()
    local runSuite = require(moduleName)
    runSuite(ctx)
  end
  harness:verifyComplete()

  local done = assert(io.open(output .. "/done", "w"))
  done:write("ok")
  done:close()
  app.exit()
end

local co = coroutine.create(run)
local timer
local running = false
timer = Timer({
  interval = 0.05,
  ontick = function()
    if running then
      return
    end
    running = true
    local ok, err = coroutine.resume(co)
    running = false
    if not ok then
      timer:stop()
      local file = io.open(output .. "/error", "w")
      if file then
        file:write(debug.traceback(co, tostring(err)))
        file:close()
      end
      app.exit()
    elseif coroutine.status(co) == "dead" then
      timer:stop()
    end
  end,
})
timer:start()
