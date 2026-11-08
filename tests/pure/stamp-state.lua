return function(test)
  -- Setup: mock app and model meta operations
  local oldApp = app
  local savedModel = package.loaded["src.document.model"]
  local savedState = package.loaded["src.document.stamp_state"]
  local layer = { meta = { schemaVersion = 1, fontProfileId = "font", unrelated = "kept" } }
  local sprite = {}
  layer.sprite = sprite
  local transactions = 0
  app = {
    sprite = sprite,
    layer = layer,
    pixelColor = { TILE_XFLIP = 0x10000000, TILE_YFLIP = 0x20000000, TILE_DFLIP = 0x40000000 },
    transaction = function(_, fn)
      transactions = transactions + 1
      fn()
    end,
  }
  package.loaded["src.document.model"] = {
    meta = function(value)
      local copy = {}
      for key, entry in pairs(value.meta) do
        copy[key] = entry
      end
      return copy
    end,
    setMeta = function(value, meta)
      value.meta = meta
    end,
  }
  package.loaded["src.document.stamp_state"] = nil
  local State = require("src.document.stamp_state")
  local value = {
    primary = { glyph = "A", fg = "#123456ff", bg = "#789abc80", flags = 0x10000000 },
    secondary = { glyph = "Ω", fg = "#abcdef12", bg = "#012345ff", flags = 0x60000000 },
  }

  test("stamp state preserves semantic values and other layer metadata", function()
    assert(State.write(sprite, layer, value))
    assert(not State.write(sprite, layer, value))
    assert(transactions == 1 and layer.meta.unrelated == "kept")
    local restored = assert(State.read(layer))
    assert(restored.primary.glyph == "A" and restored.primary.flags == 0x10000000)
    assert(restored.secondary.glyph == "Ω" and restored.secondary.fg == "#abcdef12")
    local withoutSecondary = { primary = value.primary }
    assert(State.write(sprite, layer, withoutSecondary))
    assert(State.read(layer).secondary == nil)
  end)

  test("stamp state rejects malformed data and never writes to an inactive layer", function()
    local invalid = {
      '{"version":2,"primary":{}}',
      '{"version":1,"primary":{"glyph":"AB","fg":"#123456ff","bg":"#123456ff","flags":0},"secondary":null}',
      '{"version":1,"primary":{"glyph":"A","fg":"bad","bg":"#123456ff","flags":0},"secondary":null}',
      '{"version":1,"primary":{"glyph":"A","fg":"#123456ff","bg":"#123456ff","flags":8},"secondary":null}',
      "not json",
    }
    for _, raw in ipairs(invalid) do
      layer.meta.stampStateJson = raw
      local result, problem = State.read(layer)
      assert(result == nil and problem)
    end
    app.sprite = {}
    assert(not pcall(State.write, sprite, layer, value))
    app.sprite = sprite
  end)

  -- Teardown: restore app and model modules
  package.loaded["src.document.model"] = savedModel
  package.loaded["src.document.stamp_state"] = savedState
  app = oldApp
end
