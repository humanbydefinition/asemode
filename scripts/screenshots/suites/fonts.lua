-- Suite: Font Library, Glyph Masks & Previews
local Loader = require("src.fonts.loader")

return function(ctx)
  local harness, controller, fixtures = ctx.harness, ctx.controller, ctx.fixtures

  local fontLib = harness:open(function()
    controller.font:importFont()
  end)
  fontLib:capture("font"):close()

  local fontUpload = harness:open(function()
    controller.font:importFont()
  end, { tab = "upload" })
  fontUpload:capture("font-upload"):close()

  local fontsForManage = harness:open(function()
    controller.font:importFont()
  end)
  local manageEmpty = fontsForManage:clickAndOpen("manageUserFonts")
  manageEmpty:capture("manage-user-fonts"):close()
  fontsForManage:close()

  local addLayer = harness:open(function()
    controller.font:addLayer()
  end)
  addLayer:capture("add-layer"):close()

  local previewClean = harness:open(function()
    controller.font:preview(fixtures.job, function() end, fixtures.sprite)
  end)
  previewClean:capture("font-metrics-preview"):close()

  fixtures:refreshTiles()
  fixtures.cel.image:putPixel(0, 0, fixtures.tileMissing)
  local fontsUploadFlow = harness:open(function()
    controller.font:importFont()
  end, { tab = "upload" })
  fontsUploadFlow:set("path", fixtures.sampleFontPath)
  fontsUploadFlow:set("displayName", "Custom ATASCII")
  fontsUploadFlow:set("size", "16")
  local previewClipping = fontsUploadFlow:clickAndOpen("replaceLayerFont", {
    loading = "loading-build-glyph-masks",
  })
  previewClipping:capture("font-metrics-preview-clipping"):close()
  fixtures:refreshTiles()
  fixtures.cel.image:putPixel(0, 0, fixtures.tileA)

  local candidate = Loader.inspect(fixtures.sampleFontPath)
  local staged = controller.library:stage(candidate, "Custom ATASCII")
  controller.library:commit(staged)

  local previewDup = fontsUploadFlow:clickAndOpen("addLayer", {
    alert = { id = "alert-duplicate-user-font", result = 1 },
  })
  previewDup:close()
  fontsUploadFlow:close()

  local fontsPopulated = harness:open(function()
    controller.font:importFont()
  end)
  local managePopulated = fontsPopulated:clickAndOpen("manageUserFonts")
  managePopulated:capture("manage-user-fonts-populated")
  managePopulated:click("remove", {
    alert = { id = "alert-remove-user-font", result = 2 },
  })
  managePopulated:close()
  fontsPopulated:close()

  controller.library.error =
    "Saved font library could not be read: Invalid user font library payload"
  local fontsError = harness:open(function()
    controller.font:importFont()
  end)
  fontsError:capture("font-library-error")
  local manageCorrupt = fontsError:clickAndOpen("manageUserFonts")
  manageCorrupt:capture("manage-user-fonts-corrupt")
  manageCorrupt:click("resetUserLibrary", {
    alert = { id = "alert-reset-user-library", result = 1 },
  })
  manageCorrupt:close()
  fontsError:close()
end
