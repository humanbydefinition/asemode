-- Suite: Document, Grid & Export Workflows
return function(ctx)
  local harness, controller, fixtures = ctx.harness, ctx.controller, ctx.fixtures

  fixtures:clearCells()
  local emptyReplace = harness:open(function()
    controller.document:replaceSelection()
  end)
  emptyReplace:capture("replace-selection-empty"):close()

  fixtures:populateSampleCells()
  local populatedReplace = harness:open(function()
    controller.document:replaceSelection()
  end, { wait = 1 })
  populatedReplace:capture("replace-selection"):close()

  fixtures.cel.image:putPixel(0, 0, fixtures.tileMissing)
  controller.document:copyCells()
  harness:captureAlert("alert-paste-missing-glyphs", function()
    controller.document:pasteCells()
  end, 2)
  fixtures.cel.image:putPixel(0, 0, fixtures.tileA)

  local exportDlg = harness:open(function()
    controller.document:export()
  end)
  exportDlg:capture("export"):close()

  local gridCell = harness:open(function()
    controller.document:regrid()
  end, { tab = "cell" })
  gridCell:capture("grid"):close()

  local gridSize = harness:open(function()
    controller.document:regrid()
  end)
  gridSize:capture("grid-size"):close()

  local grid = harness:open(function()
    controller.document:regrid()
  end)
  local confirmRegrid = grid:clickAndOpen("resizeCells")
  confirmRegrid:capture("confirm-regrid")
  assert(grid:isOpen(controller), "Grid closed while the cell size confirmation was open")
  confirmRegrid:close()
  assert(grid:isOpen(controller), "Grid closed after dismissing the cell size confirmation")
  confirmRegrid = grid:clickAndOpen("resizeCells")
  confirmRegrid:click("applyRegrid")
  assert(
    not confirmRegrid:isOpen(controller),
    "Cell size confirmation remained open after applying"
  )
  assert(not grid:isOpen(controller), "Grid remained open after applying the cell size")
  harness:wait(1)
  fixtures:refreshTiles()

  local tempNative = fixtures.sprite:newLayer()
  app.layer = fixtures.layer
  fixtures.cel.image:putPixel(19, 12, fixtures.tileA)
  fixtures.cel.image:putPixel(23, 15, fixtures.tileA)
  local gridWarn = harness:open(function()
    controller.document:regrid()
  end, { tab = "cell" })
  gridWarn:set("width", "5"):set("height", "10")
  local confirmRegridWarn = gridWarn:clickAndOpen("resizeCells")
  confirmRegridWarn:capture("confirm-regrid-warnings"):close()
  gridWarn:close()
  fixtures.cel.image:putPixel(19, 12, 0)
  fixtures.cel.image:putPixel(23, 15, 0)
  fixtures.sprite:deleteLayer(tempNative)
  app.layer = fixtures.layer

  local gridCanvas = harness:open(function()
    controller.document:regrid()
  end)
  local confirmCanvas = gridCanvas:clickAndOpen("resizeGrid")
  confirmCanvas:capture("confirm-canvas-size")
  assert(gridCanvas:isOpen(controller), "Grid closed while the grid size confirmation was open")
  confirmCanvas:close()
  assert(gridCanvas:isOpen(controller), "Grid closed after dismissing the grid size confirmation")
  gridCanvas:set("columns", "12"):set("rows", "8")
  local confirmCanvasWarn = gridCanvas:clickAndOpen("resizeGrid")
  confirmCanvasWarn:capture("confirm-canvas-size-warnings"):close()
  gridCanvas:close()
end
