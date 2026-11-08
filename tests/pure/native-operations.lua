return function(test)
  local names = { "src.document.model", "src.document.flatten", "src.session.native_operations" }
  local saved = {}
  for _, name in ipairs(names) do
    saved[name] = package.loaded[name]
  end
  local sprite = {}
  local group = { parent = sprite, isVisible = true }
  local textLayer = { parent = group, marked = true, isVisible = false, isTilemap = true }
  local regular = { parent = sprite, isImage = true }
  local tilemap = { parent = sprite, isTilemap = true }
  sprite.layers = { regular, textLayer }
  package.loaded["src.document.model"] = {
    hasMarkedLayers = function(value)
      if not value then
        return false
      end
      for _, item in ipairs(value.layers) do
        if item.marked then
          return true
        end
      end
      return false
    end,
    layers = function(value)
      return value.layers
    end,
    markedLayer = function(_, layer)
      return layer and layer.marked or false
    end,
  }
  package.loaded["src.document.flatten"] = nil
  package.loaded["src.session.native_operations"] = nil
  local policy = require("src.session.native_operations")
  local context = { sprite = sprite, layer = regular, range = { isEmpty = true, layers = {} } }
  local function action(name, params)
    return policy.classify(name, params, context).action
  end

  test("native operation policy protects all pixel filters in mixed sprites", function()
    for _, name in ipairs({
      "ReplaceColor",
      "InvertColor",
      "BrightnessContrast",
      "HueSaturation",
      "ColorCurve",
      "Outline",
      "ConvolutionMatrix",
      "Despeckle",
    }) do
      local result = policy.classify(name, nil, context)
      assert(result.action == "block" and result.message[1]:find("tile pixels", 1, true))
      assert(result.message[2]:find("separate pixel-art sprite", 1, true))
      context.sprite = { layers = { regular } }
      assert(action(name) == "allow", name .. " blocked a regular sprite")
      context.sprite = nil
      assert(action(name) == "allow", name .. " blocked without a sprite")
      context.sprite = sprite
    end
    assert(action("Fill") == "allow" and action("Undo") == "allow")
  end)

  test("insert text protects only the active Asemode layer", function()
    assert(action("PasteText") == "allow", "regular layer in a mixed sprite was blocked")
    context.layer = tilemap
    assert(action("PasteText") == "allow", "regular tilemap in a mixed sprite was blocked")
    context.layer = textLayer
    local result = policy.classify("PasteText", nil, context)
    assert(result.action == "block" and result.message[1]:find("Insert Text", 1, true))
    context.layer = regular
  end)

  test("native paste protects only the active Asemode layer", function()
    assert(action("Paste") == "allow", "regular pixel layer was blocked")
    context.layer = tilemap
    assert(action("Paste") == "allow", "regular tilemap was blocked")
    context.layer = textLayer
    local result = policy.classify("Paste", nil, context)
    assert(result.action == "block" and #result.message == 2)
    assert(result.message[1]:find("Native Paste", 1, true))
    assert(result.message[2]:find("Selection > Copy and Paste", 1, true))
    assert(action("Copy") == "allow" and action("CopyMerged") == "allow")
    context.layer = regular
  end)

  test("native operations allow sprites with ordinary pixel and tilemap layers", function()
    local originalSprite, originalLayer = context.sprite, context.layer
    context.sprite = { layers = { regular, tilemap } }
    context.range = { isEmpty = true, layers = {} }
    for _, layer in ipairs({ regular, tilemap }) do
      context.layer = layer
      for _, command in ipairs({
        "SpriteSize",
        "CanvasSize",
        "ChangePixelFormat",
        "FlattenLayers",
        "ConvertLayer",
        "PasteText",
        "Paste",
        "ReplaceColor",
        "InvertColor",
        "BrightnessContrast",
        "HueSaturation",
        "ColorCurve",
        "Outline",
        "ConvolutionMatrix",
        "Despeckle",
      }) do
        assert(action(command) == "allow", command .. " blocked an ordinary layer")
      end
      assert(action("Rotate", { target = "sprite", angle = "90" }) == "allow")
    end
    context.sprite, context.layer = originalSprite, originalLayer
  end)

  test("native operation policy preserves existing protection scopes", function()
    assert(action("SpriteSize") == "block" and action("CanvasSize") == "block")
    assert(action("ChangePixelFormat", { format = "rgb" }) == "allow")
    assert(action("ChangePixelFormat", { format = "rgb", ui = "true" }) == "block")
    assert(action("ChangePixelFormat") == "block")
    assert(action("ConvertLayer", { to = "layer" }) == "allow")
    context.layer = textLayer
    assert(action("ConvertLayer", { to = "layer" }) == "block")
    assert(action("ConvertLayer", { to = "tilemap" }) == "allow")
    context.layer = regular
    assert(action("FlattenLayers") == "block")
    assert(action("FlattenLayers", { visibleOnly = "true" }) == "block")
    group.isVisible = false
    assert(action("FlattenLayers", { visibleOnly = "true" }) == "allow")
    group.isVisible = true
    local rotation = policy.classify("Rotate", { target = "sprite", angle = "-90" }, context)
    assert(
      rotation.action == "replace" and rotation.operation == "rotate" and rotation.angle == -90
    )
    assert(action("Rotate", { target = "mask", angle = "90" }) == "allow")
    assert(action("Rotate", { target = "sprite", angle = "45" }) == "allow")
  end)

  for _, name in ipairs(names) do
    package.loaded[name] = saved[name]
  end
end
