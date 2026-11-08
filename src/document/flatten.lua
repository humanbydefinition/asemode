local Model = require("src.document.model")
local M = {}

---Check whether Aseprite's flatten command would remove an Asemode layer.
---@param sprite Sprite Active document.
---@param range Range Active layer range.
---@param visibleOnly boolean Whether Aseprite selects visible top-level layers.
---@return boolean affected Whether an Asemode layer would be flattened.
function M.affectsTextLayers(sprite, range, visibleOnly)
  local selected = not visibleOnly and range.layers or {}
  local all = not visibleOnly
    and (range.isEmpty or (#selected == 1 and (selected[1].isImage or selected[1].isTilemap)))
  for _, layer in ipairs(Model.layers(sprite)) do
    if Model.markedLayer(sprite, layer) then
      if all then
        return true
      end
      if visibleOnly then
        local root = layer
        while root.parent and root.parent ~= sprite do
          root = root.parent
        end
        if root.isVisible then
          return true
        end
      else
        local current = layer
        while current and current ~= sprite do
          for _, target in ipairs(selected) do
            if current == target then
              return true
            end
          end
          current = current.parent
        end
      end
    end
  end
  return false
end
return M
