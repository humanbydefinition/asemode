return function(test)
  -- Setup: mock model layer hierarchy
  local savedModel, savedFlatten =
    package.loaded["src.document.model"], package.loaded["src.document.flatten"]
  package.loaded["src.document.model"] = {
    layers = function(sprite)
      return sprite.leaves
    end,
    markedLayer = function(_, layer)
      return layer.marked
    end,
  }
  package.loaded["src.document.flatten"] = nil
  local Flatten = require("src.document.flatten")
  local sprite = {}
  local group = { parent = sprite, isVisible = true }
  local nested = { parent = group, isVisible = false, marked = true }
  local hidden = { parent = sprite, isVisible = false, marked = true }
  local normal = { parent = sprite, isVisible = true, isImage = true }
  sprite.leaves = { nested, hidden, normal }

  test("flatten protects selected groups and the default all-layers action", function()
    assert(Flatten.affectsTextLayers(sprite, { isEmpty = true, layers = {} }, false))
    assert(Flatten.affectsTextLayers(sprite, { isEmpty = false, layers = { normal } }, false))
    assert(Flatten.affectsTextLayers(sprite, { isEmpty = false, layers = { group } }, false))
    assert(
      not Flatten.affectsTextLayers(sprite, { isEmpty = false, layers = { normal, {} } }, false)
    )
  end)

  test("flatten visible protects hidden text inside selected visible groups", function()
    assert(Flatten.affectsTextLayers(sprite, {}, true))
    group.isVisible = false
    assert(not Flatten.affectsTextLayers(sprite, {}, true))
    hidden.isVisible = true
    assert(Flatten.affectsTextLayers(sprite, {}, true))
  end)

  -- Teardown: restore model modules
  package.loaded["src.document.model"], package.loaded["src.document.flatten"] =
    savedModel, savedFlatten
end
