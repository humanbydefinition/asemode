return function(test)
  -- Setup: mock model layer detection
  local savedModel = package.loaded["src.document.model"]
  local savedProjects = package.loaded["src.session.projects"]
  package.loaded["src.document.model"] = {
    hasMarkedLayers = function(sprite)
      for _, layer in ipairs(sprite.layers) do
        if sprite.supported and layer.valid then
          return true
        end
      end
      return false
    end,
    layers = function(sprite)
      return sprite.layers
    end,
    markedLayer = function(sprite, layer)
      return sprite.supported and layer.valid
    end,
  }
  package.loaded["src.session.projects"] = nil
  local Projects = require("src.session.projects")

  local function sprite(id, supported, layers)
    local listeners = {}
    local result = { id = id, isValid = true, supported = supported, layers = layers }
    result.events = {
      on = function(_, _, fn)
        listeners[1] = fn
        return 1
      end,
      off = function(_, code)
        listeners[code] = nil
      end,
    }
    function result:change()
      if listeners[1] then
        listeners[1]()
      end
    end
    function result:listening()
      return listeners[1] ~= nil
    end
    return result
  end

  test("project panel opens once and respects dismissal until close", function()
    local tracker = Projects.new()
    local a = sprite(1, true, { { valid = true } })
    local b = sprite(2, true, { { valid = true } })
    assert(tracker:check(a, { a }, false))
    assert(not tracker:check(a, { a }, false))
    tracker:dismiss(a)
    a:change()
    assert(not tracker:check(a, { a, b }, false))
    assert(tracker:check(b, { a, b }, false))
    assert(not tracker:check(a, { a, b }, false))
    tracker:check(nil, { b }, false)
    assert(not a:listening())
    local reopened = sprite(3, true, { { valid = true } })
    assert(tracker:check(reopened, { b, reopened }, false))
    tracker:close()
    assert(not b:listening() and not reopened:listening())
  end)

  test("project detection waits for valid layers and avoids repeat scans", function()
    local tracker = Projects.new()
    local a = sprite(4, true, { { valid = false } })
    assert(not tracker:check(a, { a }, false))
    a.layers[1].valid = true
    assert(not tracker:check(a, { a }, false))
    a:change()
    assert(not tracker:check(a, { a }, true))
    assert(not tracker:check(a, { a }, false))
    tracker:close()
  end)

  -- Teardown: restore model modules
  package.loaded["src.document.model"] = savedModel
  package.loaded["src.session.projects"] = savedProjects
end
