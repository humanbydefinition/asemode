local Model = require("src.document.model")
local Flatten = require("src.document.flatten")
local M = {}
local allow = { action = "allow" }

local filters = {
  ReplaceColor = true,
  InvertColor = true,
  BrightnessContrast = true,
  HueSaturation = true,
  ColorCurve = true,
  Outline = true,
  ConvolutionMatrix = true,
  Despeckle = true,
}

---Construct a decision table that blocks a command with an explanation message.
---@param message string|string[] User-facing warning message.
---@return table decision Block decision record.
local function block(message)
  return { action = "block", message = message }
end

---Classify a native operation without changing the document or showing UI.
---@param name string Command identifier.
---@param params table? Host-supplied command parameters.
---@param context table Active sprite, layer, and timeline range.
---@return table decision Allow, block, or replace the command.
function M.classify(name, params, context)
  params = params or {}
  local sprite = context.sprite
  if filters[name] then
    if Model.hasMarkedLayers(sprite) then
      return block({
        "This effect can change Asemode tile pixels.",
        "Apply it to a separate pixel-art sprite instead.",
      })
    end
  elseif name == "ChangePixelFormat" and sprite then
    local format = params.colorMode or params.format
    local ui = params.ui == true or params.ui == 1 or params.ui == "true" or params.ui == "1"
    local explicitRGB = type(format) == "string" and format:lower() == "rgb" and not ui
    if not explicitRGB and Model.hasMarkedLayers(sprite) then
      return block({
        "Asemode layers require RGB color mode.",
        "Grayscale, Indexed, and More Options are unavailable for this sprite.",
      })
    end
  elseif name == "FlattenLayers" and sprite then
    local visible = params.visibleOnly
    local visibleOnly = visible == true or visible == "true" or visible == "1" or visible == 1
    if Flatten.affectsTextLayers(sprite, context.range, visibleOnly) then
      return block({
        "Flattening these layers would discard Asemode textmode cell data.",
        "Asemode layers must remain tilemap layers.",
      })
    end
  elseif name == "ConvertLayer" then
    if params.to ~= "tilemap" and Model.markedLayer(sprite, context.layer) then
      return block({
        "Converting this Asemode layer would discard its textmode cell data.",
        "Asemode layers must remain tilemap layers.",
      })
    end
  elseif name == "Paste" then
    if Model.markedLayer(sprite, context.layer) then
      return block({
        "Native Paste cannot preserve Asemode cell data.",
        "Use Sprite > Asemode > Selection > Copy and Paste instead.",
      })
    end
  elseif name == "PasteText" then
    if Model.markedLayer(sprite, context.layer) then
      return block({
        "Insert Text is not supported on Asemode layers.",
        "Select glyphs in the Asemode panel to draw textmode cells.",
      })
    end
  elseif name == "Rotate" and sprite and params.target ~= "mask" then
    local angle = tonumber(params.angle)
    if (angle == 90 or angle == -90 or angle == 180) and Model.hasMarkedLayers(sprite) then
      return { action = "replace", operation = "rotate", angle = angle }
    end
  elseif (name == "SpriteSize" or name == "CanvasSize") and Model.hasMarkedLayers(sprite) then
    return block(name == "SpriteSize" and {
      "Sprite Size cannot safely scale Asemode layers.",
      "Use Sprite > Asemode > Grid to change the grid or cell size.",
    } or {
      "Canvas Size can move Asemode layers out of alignment.",
      "Use Sprite > Asemode > Grid to change the grid size.",
    })
  end
  return allow
end

return M
