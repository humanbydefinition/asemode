return function(test)
  test("export summary counts layers per frame and distinct source layers", function()
    local names = {
      "src.document.portable_export",
      "src.portable.codec",
      "src.document.model",
      "src.document.profile",
      "src.fonts.loader",
      "src.document.snapshot",
      "src.document.validate",
      "src.document.blend",
    }
    local saved = {}
    for _, name in ipairs(names) do
      saved[name] = package.loaded[name]
    end
    local sprite = { frames = { { duration = 0.1 }, { duration = 0.1 }, { duration = 0.1 } } }
    local function layer(name, uuid, frames)
      local source = {
        name = name,
        uuid = uuid,
        isTilemap = true,
        isVisible = true,
        opacity = 255,
        parent = sprite,
      }
      function source:cel(number)
        return frames[number] and { opacity = 255, zIndex = self.zIndex or 0 } or nil
      end
      return source
    end
    local first = layer("First", "a", { true, false, true })
    local second = layer("Second", "b", { false, true, true })
    sprite.layers = { first, second }
    local extent = { columns = 0, rows = 0, partial = false }
    package.loaded["src.document.model"] = {
      layers = function()
        local result = {}
        local function visit(layers)
          for _, item in ipairs(layers) do
            if item.isGroup then
              visit(item.layers)
            else
              result[#result + 1] = item
            end
          end
        end
        visit(sprite.layers)
        return result
      end,
      meta = function()
        return { schemaVersion = 1, fontProfileId = 1 }
      end,
      layerManaged = function()
        return true
      end,
      geometry = function()
        return {}
      end,
      coverage = function()
        return extent
      end,
    }
    package.loaded["src.portable.codec"] = {
      format = "textmode.document",
      version = "4.0.0",
      encode = function()
        return { ok = true, text = "{}" }
      end,
    }
    package.loaded["src.document.profile"] = {
      index = function()
        return { profile = {} }
      end,
    }
    package.loaded["src.fonts.loader"] = {
      reference = function()
        return nil
      end,
    }
    package.loaded["src.document.validate"] = {
      exportContext = function()
        return {}
      end,
    }
    package.loaded["src.document.blend"] = {
      blendName = function()
        return "normal"
      end,
    }
    package.loaded["src.document.snapshot"] = {
      capture = function(_, present, frameNumber)
        local entries = {}
        for _, source in ipairs(present) do
          entries[#entries + 1] = { layer = source, cel = source:cel(frameNumber), rows = {} }
        end
        return { layers = entries, geometry = {}, extent = extent, outside = 0 }
      end,
    }
    package.loaded["src.document.portable_export"] = nil
    local ok, err = xpcall(function()
      local export = require("src.document.portable_export").export
      local all = export(sprite, first, 1, { target = "all", frames = "all" })
      assert(all.review.minLayers == 1 and all.review.maxLayers == 2 and not all.review.layerName)
      local one = export(sprite, first, 1, { target = "selected", frames = "all" })
      assert(
        one.review.minLayers == 0 and one.review.maxLayers == 1 and one.review.layerName == "First"
      )
      local active = export(sprite, first, 2, { target = "all", frames = "selected" })
      assert(
        active.review.minLayers == 1
          and active.review.maxLayers == 1
          and active.review.layerName == "Second"
      )
      local none = export(sprite, first, 2, { target = "selected", frames = "selected" })
      assert(
        none.review.minLayers == 0 and none.review.maxLayers == 0 and not none.review.layerName
      )
      -- A group occupies a stacking position even though it is not exported.
      local group =
        { name = "Group", isGroup = true, isVisible = true, parent = sprite, layers = { second } }
      second.parent, first.zIndex = group, 1
      sprite.layers = { first, group }
      local grouped = export(sprite, first, 3, { target = "all" })
      local layers = grouped.document.frames[1].layers
      assert(layers[1].id == "a" and layers[2].id == "b")
    end, debug.traceback)
    for _, name in ipairs(names) do
      package.loaded[name] = saved[name]
    end
    assert(ok, err)
  end)
end
