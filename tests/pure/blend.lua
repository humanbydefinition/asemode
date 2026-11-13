return function(test)
  test("portable blend names round-trip and reject internal modes", function()
    local oldBlendMode = BlendMode
    local names = {
      normal = "NORMAL",
      additive = "ADDITION",
      multiply = "MULTIPLY",
      screen = "SCREEN",
      subtract = "SUBTRACT",
      darken = "DARKEN",
      lighten = "LIGHTEN",
      overlay = "OVERLAY",
      softLight = "SOFT_LIGHT",
      hardLight = "HARD_LIGHT",
      colorDodge = "COLOR_DODGE",
      colorBurn = "COLOR_BURN",
      difference = "DIFFERENCE",
      exclusion = "EXCLUSION",
      hslHue = "HSL_HUE",
      hslSaturation = "HSL_SATURATION",
      hslColor = "HSL_COLOR",
      hslLuminosity = "HSL_LUMINOSITY",
      divide = "DIVIDE",
    }
    BlendMode = {}
    local count = 0
    for _, key in pairs(names) do
      count = count + 1
      BlendMode[key] = count
    end
    local Blend = require("src.document.blend")
    for name, key in pairs(names) do
      assert(Blend.blend(name) == BlendMode[key])
      assert(Blend.blendName(BlendMode[key]) == name)
    end
    assert(count == 19)
    local ok, err = pcall(Blend.blend, "unknown")
    assert(not ok and tostring(err):find("UNSUPPORTED_BLEND_MODE", 1, true))
    ok, err = pcall(Blend.blendName, -1)
    assert(not ok and tostring(err):find("UNSUPPORTED_BLEND_MODE", 1, true))
    BlendMode = oldBlendMode
  end)
end
