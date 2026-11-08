-- Suite: Portable JSON Import & Export
return function(ctx)
  local harness, controller, fixtures = ctx.harness, ctx.controller, ctx.fixtures

  local importJson = harness:open(function()
    controller.portable:importDocument()
  end)
  importJson:capture("import-json")
  importJson:set("file", fixtures.exportJsonPath)
  local importLayers = importJson:clickAndOpen("read", {
    loading = { "loading-read-json", "loading-match-fonts" },
  })
  importLayers:capture("import-layers")
  local reviewImport = importLayers:clickAndOpen("prepare", {
    loading = "loading-prepare-import",
  })
  reviewImport:capture("review-import"):close()

  local blankJson = harness:open(function()
    controller.portable:importDocument()
  end)
  blankJson:set("file", fixtures.blankJsonPath)
  local blankLayers = blankJson:clickAndOpen("read")
  blankLayers:capture("import-layers-blank"):close()

  local warnJson = harness:open(function()
    controller.portable:importDocument()
  end)
  warnJson:set("file", fixtures.warningsJsonPath)
  local warnLayers = warnJson:clickAndOpen("read")
  warnLayers:capture("import-layers-paginated-recovery")
  warnLayers:set("font1", "ATASCII"):set("size", "12"):set("width", "6")
  local reviewWarn = warnLayers:clickAndOpen("prepare")
  reviewWarn:capture("review-import-warnings"):close()

  local legacyJson = harness:open(function()
    controller.portable:importDocument()
  end)
  legacyJson:set("file", fixtures.legacyJsonPath)
  local needsChanges = legacyJson:clickAndOpen("read")
  needsChanges:capture("import-needs-changes"):close()
  legacyJson:close()

  local missingJson = harness:open(function()
    controller.portable:importDocument()
  end)
  missingJson:set("file", fixtures.missingJsonPath)
  local needsChangesAccess = missingJson:clickAndOpen("read")
  needsChangesAccess:capture("import-needs-changes-access"):close()
  missingJson:close()

  local reviewExport = harness:open(function()
    controller.portable:exportDocument(
      fixtures.sprite,
      fixtures.layer,
      app.frame,
      { target = "all", frames = "all" },
      fixtures:path("unused.json")
    )
  end, { loading = "loading-prepare-export" })
  reviewExport:capture("review-export"):close()

  local exportNativeLayer = fixtures.sprite:newLayer()
  app.layer = fixtures.layer
  fixtures.cel.position = Point(-8, 0)
  local reviewExportWarn = harness:open(function()
    controller.portable:exportDocument(
      fixtures.sprite,
      fixtures.layer,
      app.frame,
      { target = "all", frames = "all" },
      fixtures:path("unused-warnings.json")
    )
  end)
  reviewExportWarn:capture("review-export-warnings"):close()
  fixtures.cel.position = Point(0, 0)
  fixtures.sprite:deleteLayer(exportNativeLayer)
  app.layer = fixtures.layer
end
