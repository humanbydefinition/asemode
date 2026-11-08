-- Suite: About, Settings & New Sprite
local Bundled = require("src.fonts.bundled")

return function(ctx)
  local harness, controller = ctx.harness, ctx.controller

  local about = harness:open(function()
    controller:about()
  end)
  about:capture("about"):close()

  local savedBundledAvailable = Bundled[1].available
  Bundled[1].available = false
  local aboutFonts = harness:open(function()
    controller:about()
  end, { tab = "fonts" })
  aboutFonts:set("font", Bundled[1].name .. " (Not installed)")
  aboutFonts:capture("about-fonts-unavailable")
  aboutFonts:set("font", "ATASCII")
  aboutFonts:capture("about-fonts"):close()
  Bundled[1].available = savedBundledAvailable

  local settings = harness:open(function()
    controller:settings()
  end)
  settings:capture("settings"):close()

  local newSprite = harness:open(function()
    controller.document:newDocument()
  end)
  newSprite:capture("new-sprite"):close()
end
