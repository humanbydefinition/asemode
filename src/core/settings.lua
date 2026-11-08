local U = require("src.core.util")
local M = { GRID_CELL_SIZES = { 12, 20, 28, 36 }, GRID_CELL_DEFAULT = 20 }

---Check whether a value is an integer dimension in the range 1 to 1024.
---@param value any Value to validate.
---@return boolean valid True if value is an integer from 1 to 1024.
local function validDimension(value)
  return type(value) == "number"
    and value == value
    and value % 1 == 0
    and value >= 1
    and value <= 1024
end

---Check whether grid dimensions stay within the maximum cell budget.
---@param columns integer Number of columns.
---@param rows integer Number of rows.
---@return boolean withinBudget True if total cell count does not exceed 4,194,304 cells.
local function validGridBudget(columns, rows)
  return columns * rows <= 4 * 1024 * 1024
end

---Check whether a value is a valid font size between 8 and 128.
---@param value any Value to validate.
---@param whole? boolean Whether the value must be an integer.
---@return boolean valid True if value is a valid font size.
local function validFontSize(value, whole)
  return type(value) == "number"
    and value == value
    and value >= 8
    and value <= 128
    and (not whole or value % 1 == 0)
end

---Check whether a value is an RGBA hexadecimal background color.
---@param value any Value to inspect.
---@return boolean valid True if value is a valid #rrggbbaa string.
local function validBackground(value)
  return U.isHexColor(value)
end

---Check whether an entry represents a valid available font choice.
---@param font any Font catalog entry to validate.
---@return boolean valid True if font is valid and available.
local function validFontChoice(font)
  return font
    and font.available ~= false
    and type(font.id) == "string"
    and (font.kind == "user" or font.kind == "bundled")
end

---Create the default settings for a new sprite.
---@return table defaults Fresh default settings.
function M.defaults()
  return {
    columns = 40,
    rows = 25,
    fontKind = "bundled",
    fontId = "atascii",
    size = 8,
    backgroundColor = "#ffffff00",
  }
end

---Read valid saved defaults and detect an unavailable saved font.
---@param preferences table Plugin preferences.
---@param library table Font library with a catalog method.
---@return table defaults Validated settings with fallback values.
---@return boolean missingFont Whether the saved font is unavailable.
function M.read(preferences, library)
  local result = M.defaults()
  local saved = preferences.newSpriteDefaults
  if type(saved) ~= "table" then
    return result, false
  end
  for _, key in ipairs({ "columns", "rows" }) do
    local value = saved[key]
    if validDimension(value) then
      result[key] = value
    end
  end
  if not validGridBudget(result.columns, result.rows) then
    result.columns, result.rows = M.defaults().columns, M.defaults().rows
  end
  local size = saved.size
  if validFontSize(size, false) then
    result.size = math.floor(size)
  end
  if validBackground(saved.backgroundColor) then
    result.backgroundColor = saved.backgroundColor:lower()
  end
  if
    type(saved.fontId) == "string" and (saved.fontKind == "bundled" or saved.fontKind == "user")
  then
    for _, entry in ipairs(library:catalog()) do
      if entry.id == saved.fontId and entry.kind == saved.fontKind and entry.available ~= false then
        result.fontId, result.fontKind = entry.id, entry.kind
        return result, false
      end
    end
    return result, true
  end
  return result, false
end

---Validate one new-sprite setting without changing preferences.
---@param preferences table Plugin preferences.
---@param library table Font library with a catalog method.
---@param field string Setting to validate.
---@param value any Proposed setting value.
---@return boolean ok Whether the value is valid.
---@return string? message Validation message on failure.
---@return table? settings Validated settings on success.
function M.validate(preferences, library, field, value)
  local current = M.read(preferences, library)
  local saved = preferences.newSpriteDefaults
  if
    type(saved) == "table"
    and type(saved.fontId) == "string"
    and (saved.fontKind == "bundled" or saved.fontKind == "user")
  then
    current.fontId, current.fontKind = saved.fontId, saved.fontKind
  end
  if field == "font" then
    if not validFontChoice(value) then
      return false, "Choose a library font"
    end
    current.fontId, current.fontKind = value.id, value.kind
  elseif field == "columns" or field == "rows" then
    if not validDimension(value) then
      return false, "Enter a whole number between 1 and 1024."
    end
    current[field] = value
  elseif field == "size" then
    if not validFontSize(value, true) then
      return false, "Font size must be a whole number between 8 and 128"
    end
    current.size = value
  elseif field == "backgroundColor" then
    if not validBackground(value) then
      return false, "Choose a background color"
    end
    current.backgroundColor = value:lower()
  else
    error("Unknown settings field: " .. tostring(field))
  end
  if not validGridBudget(current.columns, current.rows) then
    return false, "Document dimensions exceed the supported limits"
  end
  return true, nil, current
end

---Validate and save one new-sprite setting.
---@param preferences table Plugin preferences, updated on success.
---@param library table Font library with a catalog method.
---@param field string Setting to update.
---@param value any Proposed setting value.
---@return boolean ok Whether the value was saved.
---@return string? message Validation message on failure.
function M.update(preferences, library, field, value)
  local ok, message, current = M.validate(preferences, library, field, value)
  if ok then
    preferences.newSpriteDefaults = current
  end
  return ok, message
end

---Restore new-sprite defaults and the glyph grid size.
---@param preferences table Plugin preferences to update.
function M.reset(preferences)
  preferences.newSpriteDefaults = M.defaults()
  preferences.glyphGridSize = M.GRID_CELL_DEFAULT
end

---Validate and save all new-sprite defaults.
---@param preferences table Plugin preferences to update.
---@param columns integer Grid columns.
---@param rows integer Grid rows.
---@param size integer Font size in pixels.
---@param font table Selected font with id and kind.
---@param backgroundColor? string Background RGBA color.
function M.save(preferences, columns, rows, size, font, backgroundColor)
  columns = U.integer(columns, "Columns", 1, 1024)
  rows = U.integer(rows, "Rows", 1, 1024)
  U.check(validGridBudget(columns, rows), "Document dimensions exceed the supported limits")
  U.check(validFontSize(size, true), "Font size must be a whole number between 8 and 128")
  U.check(font and font.id and font.kind, "Choose a library font")
  if backgroundColor == nil then
    backgroundColor = M.defaults().backgroundColor
  else
    U.check(validBackground(backgroundColor), "Choose a background color")
    backgroundColor = backgroundColor:lower()
  end
  preferences.newSpriteDefaults = {
    columns = columns,
    rows = rows,
    size = size,
    fontId = font.id,
    fontKind = font.kind,
    backgroundColor = backgroundColor,
  }
end
return M
