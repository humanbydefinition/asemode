local M = {}
local LEFT_SIDEBAR_WIDTH, TOP_CHROME_HEIGHT, PANEL_MAX_HEIGHT_RATIO = 110, 52, 0.65

function M.atLeftSidebar(bounds)
  local scale = app.uiScale or 1
  local x = math.floor(LEFT_SIDEBAR_WIDTH * scale)
  local y = math.floor(TOP_CHROME_HEIGHT * scale)
  local bottomMargin = math.floor(8 * scale)
  local availableHeight = math.max(1, app.window.height - y - bottomMargin)
  local maxHeight = math.floor(availableHeight * PANEL_MAX_HEIGHT_RATIO)
  return Rectangle(x, y, bounds.width, math.min(bounds.height, maxHeight))
end

function M.fromPreferences(value)
  local valueType = type(value)
  if valueType ~= "table" and valueType ~= "userdata" then
    return nil
  end
  local x, y, width, height = value.x, value.y, value.width, value.height
  if
    type(x) ~= "number"
    or type(y) ~= "number"
    or type(width) ~= "number"
    or type(height) ~= "number"
    or x ~= x
    or y ~= y
    or width ~= width
    or height ~= height
    or math.abs(x) > 100000
    or math.abs(y) > 100000
    or width < 1
    or width > 100000
    or height < 1
    or height > 100000
  then
    return nil
  end
  return Rectangle(math.floor(x), math.floor(y), math.floor(width), math.floor(height))
end

function M.keepOnscreen(bounds)
  local window = app.window
  if not (bounds and window and window.width and window.height) then
    return bounds
  end
  local width, height = math.max(1, window.width), math.max(1, window.height)
  local panelWidth = math.min(bounds.width, width)
  local panelHeight = math.min(bounds.height, height)
  local x = math.max(0, math.min(bounds.x, width - panelWidth))
  local y = math.max(0, math.min(bounds.y, height - panelHeight))
  return Rectangle(x, y, panelWidth, panelHeight)
end

return M
