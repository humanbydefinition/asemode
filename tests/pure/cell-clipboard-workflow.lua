return function(test)
  test("copy requires an active Asemode selection", function()
    local oldApp = app
    local model = require("src.document.model")
    local oldTextLayer = model.textLayer
    local sprite, layer = { selection = { isEmpty = true } }, {}
    app = {
      sprite = sprite,
      layer = layer,
      isUIAvailable = true,
      command = { DeselectMask = { enabled = false }, ReselectMask = { enabled = false } },
    }
    rawset(model, "textLayer", function(s, l)
      return s == sprite and l == layer
    end)
    local document = require("src.ui.document_workflow").new({ drawing = {}, library = {} })
    assert(not document:canCopyCells())
    sprite.selection.isEmpty = false
    assert(document:canCopyCells())
    sprite.selection.isEmpty = true
    assert(not document:canCopyCells(), "empty selection enabled copy")
    sprite.selection.isEmpty = false
    app.layer = {}
    assert(not document:canCopyCells(), "ordinary layer enabled copy")
    rawset(model, "textLayer", oldTextLayer)
    app = oldApp
  end)

  test("cell paste confirms missing glyphs before changing the document", function()
    local oldApp = app
    local sprite, layer, selection = {}, {}, {}
    sprite.selection = selection
    local confirm, applied = 2, 0
    app = {
      pixelColor = {},
      isUIAvailable = true,
      frame = 1,
      command = { DeselectMask = { enabled = true }, ReselectMask = { enabled = false } },
      alert = function()
        return confirm
      end,
      tip = function() end,
      refresh = function() end,
    }
    local workflow = require("src.ui.document_workflow")
    local clipboard = require("src.document.clipboard")
    local oldCopy, oldPrepare, oldApply = clipboard.copy, clipboard.prepare, clipboard.apply
    rawset(clipboard, "copy", function()
      return { cells = { {}, {} } }
    end)
    rawset(clipboard, "prepare", function(_, _, _, selected, copied)
      assert(selected == selection and #copied.cells == 2)
      return { missing = 2 }
    end)
    rawset(clipboard, "apply", function()
      applied = applied + 1
    end)
    local drawing = {
      target = function()
        return sprite, layer
      end,
      ensureActive = function() end,
      flush = function() end,
      withSuppression = function(_, fn)
        fn()
      end,
    }
    local document = workflow.new({ drawing = drawing, library = {}, invalidate = function() end })
    document:copyCells()
    document:pasteCells()
    assert(applied == 0, "cancel changed the document")
    confirm = 1
    document:pasteCells()
    assert(applied == 1, "confirmed paste was not applied")
    clipboard.copy, clipboard.prepare, clipboard.apply = oldCopy, oldPrepare, oldApply
    app = oldApp
  end)
end
