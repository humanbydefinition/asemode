local U = require("src.core.util")
local Settings = require("src.core.settings")
local Controls = require("src.ui.controls")
local M = {}
local GRID_CELL_SIZES, GRID_CELL_DEFAULT = Settings.GRID_CELL_SIZES, Settings.GRID_CELL_DEFAULT

---Open the Asemode settings dialog using the controller services.
function M.open(self)
  if self.focusDialog and self:focusDialog("settings") then
    return
  end
  local options = {}
  for _, size in ipairs(GRID_CELL_SIZES) do
    options[#options + 1] = tostring(size)
  end
  local defaults = Settings.read(self.plugin.preferences, self.library)
  local controls = Controls.new()
  local catalog, ready = nil, false
  local errors, errorOrder = {}, {}
  local d
  d = self:dialog("Asemode Settings", {
    singleton = "settings",
    onclose = function()
      if not ready then
        return
      end
      local current = Settings.read(self.plugin.preferences, self.library)
      local fallback = Settings.defaults()

      local finalCols =
        controls:clampInt(d.data.defaultColumns, 1, 1024, current.columns or fallback.columns)
      local finalRows =
        controls:clampInt(d.data.defaultRows, 1, 1024, current.rows or fallback.rows)
      local finalSize = controls:clampInt(d.data.size, 8, 128, current.size or fallback.size)

      if finalCols * finalRows > 4 * 1024 * 1024 then
        finalCols, finalRows = current.columns, current.rows
      end

      Settings.update(self.plugin.preferences, self.library, "columns", finalCols)
      Settings.update(self.plugin.preferences, self.library, "rows", finalRows)
      Settings.update(self.plugin.preferences, self.library, "size", finalSize)
    end,
  })
  local saveDefault = self:guard(function(field, value)
    if not ready then
      return
    end
    local ok, message = Settings.update(self.plugin.preferences, self.library, field, value)
    local values = {
      columns = d.data.defaultColumns,
      rows = d.data.defaultRows,
      size = d.data.size,
      font = catalog and catalog.selected(),
      backgroundColor = d.data.defaultBackgroundColor and U.colorHex(d.data.defaultBackgroundColor)
        or defaults.backgroundColor,
    }
    for _, key in ipairs({ "columns", "rows", "size", "font", "backgroundColor" }) do
      local valid, reason = ok, message
      if key ~= field then
        valid, reason = Settings.validate(self.plugin.preferences, self.library, key, values[key])
      end
      if key == "columns" or key == "rows" or key == "size" then
        if reason == "Document dimensions exceed the supported limits" then
          errors[key] = reason
          for i = #errorOrder, 1, -1 do
            if errorOrder[i] == key then
              table.remove(errorOrder, i)
            end
          end
          errorOrder[#errorOrder + 1] = key
        else
          errors[key] = nil
        end
      elseif valid then
        errors[key] = nil
      elseif not errors[key] or key == field then
        errors[key] = reason
        for i = #errorOrder, 1, -1 do
          if errorOrder[i] == key then
            table.remove(errorOrder, i)
          end
        end
        errorOrder[#errorOrder + 1] = key
      else
        errors[key] = reason
      end
    end
    local displayed
    for i = #errorOrder, 1, -1 do
      if errors[errorOrder[i]] then
        displayed = errors[errorOrder[i]]
        break
      end
      table.remove(errorOrder, i)
    end
    d:modify({ id = "settingsError", text = displayed or "", visible = displayed ~= nil })
  end)
  d:separator({ text = "New Textmode Sprite defaults" })
  controls:addNumericInput(d, "defaultColumns", "Columns", tostring(defaults.columns), {
    min = 1,
    max = 1024,
    onchange = function()
      saveDefault("columns", d.data.defaultColumns)
    end,
  })
  controls:addNumericInput(d, "defaultRows", "Rows", tostring(defaults.rows), {
    min = 1,
    max = 1024,
    onchange = function()
      saveDefault("rows", d.data.defaultRows)
    end,
  })
  catalog = self.font:libraryControl(
    d,
    "defaultFont",
    nil,
    { id = defaults.fontId, kind = defaults.fontKind },
    function()
      if catalog then
        saveDefault("font", catalog.selected())
      end
    end
  )
  controls:addFontSizeInput(d, tostring(defaults.size), {
    min = 8,
    max = 128,
    onchange = function()
      saveDefault("size", d.data.size)
    end,
  })
  controls:addBackgroundInput(d, defaults.backgroundColor, {
    id = "defaultBackgroundColor",
    onchange = function(ev)
      local bg = (ev and ev.color) or d.data.defaultBackgroundColor
      saveDefault("backgroundColor", bg and U.colorHex(bg) or nil)
    end,
  })
  ready = true
  d:label({ id = "settingsError", text = "", visible = false })
  d:separator({ text = "Asemode Panel defaults" })
  d:combobox({
    id = "glyphGridSize",
    label = "Glyph tile size",
    options = options,
    option = tostring(self.browser:cellSize()),
    onchange = function()
      self:setGlyphGridSize(d.data.glyphGridSize)
    end,
  })
  d:newrow()
  local targetLabels = {
    primary = "Primary stamp only",
    both = "Both stamps",
  }
  local targetValues = {
    ["Primary stamp only"] = "primary",
    ["Both stamps"] = "both",
  }
  d:combobox({
    id = "stampClickTarget",
    label = "Stamp action click",
    options = { "Primary stamp only", "Both stamps" },
    option = targetLabels[self:getStampClickTarget()] or targetLabels.primary,
    onchange = function()
      local chosen = targetValues[d.data.stampClickTarget] or "primary"
      self:setStampClickTarget(chosen)
    end,
  })

  d:newrow()
  d:button({
    text = "Reset defaults",
    onclick = self:guard(function()
      ready = false
      local reset = Settings.defaults()
      Settings.reset(self.plugin.preferences)
      errors, errorOrder = {}, {}
      d:modify({ id = "settingsError", text = "", visible = false })
      d:modify({ id = "defaultColumns", text = tostring(reset.columns) })
      d:modify({ id = "defaultRows", text = tostring(reset.rows) })
      d:modify({ id = "size", text = tostring(reset.size) })
      d:modify({ id = "defaultFont", option = "ATASCII" })
      d:modify({ id = "defaultBackgroundColor", color = U.color(reset.backgroundColor) })
      self:setGlyphGridSize(GRID_CELL_DEFAULT)
      d:modify({ id = "glyphGridSize", option = tostring(GRID_CELL_DEFAULT) })
      self:setStampClickTarget(Settings.STAMP_CLICK_DEFAULT)
      d:modify({ id = "stampClickTarget", option = targetLabels[Settings.STAMP_CLICK_DEFAULT] })
      ready = true
    end),
  })
  d:newrow()
  d:button({
    text = "Keyboard Shortcuts...",
    onclick = self:guard(function()
      self:keyboardShortcuts()
    end),
  }):show({ wait = false })
end

return M
