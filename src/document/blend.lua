local U = require("src.core.util")
local M = {}
local blendNames = {
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
---Convert a portable blend mode name to a native Aseprite mode.
---@param name string Portable blend mode name.
---@return integer mode Native blend mode.
function M.blend(name)
  local mode = blendNames[name] and BlendMode[blendNames[name]]
  U.check(mode ~= nil, "UNSUPPORTED_BLEND_MODE: " .. tostring(name))
  return mode
end

---Convert a native blend mode to its portable name.
---@param mode integer Native blend mode.
---@return string name Portable blend mode name.
function M.blendName(mode)
  for name in pairs(blendNames) do
    if M.blend(name) == mode then
      return name
    end
  end
  error("UNSUPPORTED_BLEND_MODE: native blend mode " .. tostring(mode), 0)
end
return M
