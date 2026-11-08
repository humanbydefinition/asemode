local M = {}
local planes = {}
local labelRanges = require("src.unicode.name-label-ranges")
-- Aseprite restores package.path after plugin initialization. Capture this
-- module's directory now so lazy lookups also work from dialog/timer callbacks.
local dataDirectory = app.fs.joinPath(app.fs.filePath(debug.getinfo(1, "S").source:sub(2)), "names")

local function labelType(codepoint)
  local first, last = 1, #labelRanges
  while first <= last do
    local middle = (first + last) // 2
    local range = labelRanges[middle]
    if codepoint < range[1] then
      last = middle - 1
    elseif codepoint > range[2] then
      first = middle + 1
    else
      return range[3]
    end
  end
end

---Look up a Unicode name or generated label, loading its plane on demand.
---@param codepoint integer Unicode code point.
---@return string? name Name or label, or nil if none is available.
function M.name(codepoint)
  if type(codepoint) ~= "number" or codepoint % 1 ~= 0 or codepoint < 0 or codepoint > 0x10ffff then
    return nil
  end

  local plane = codepoint >> 16
  local names = planes[plane]
  if not names then
    local path = app.fs.joinPath(dataDirectory, string.format("plane_%02x.lua", plane))
    local chunk, err = loadfile(path, "t")
    if chunk then
      names = chunk()
      if type(names) ~= "table" then
        error("Invalid Unicode name data: " .. path, 2)
      end
    else
      local file = io.open(path, "rb")
      if file then
        file:close()
        error("Cannot load Unicode name data: " .. tostring(err), 2)
      end
      names = {}
    end
    planes[plane] = names
  end

  local name = names[codepoint]
  if name then
    return name
  end

  local kind = labelType(codepoint)
  if kind then
    return string.format("<%s-%04X>", kind:lower(), codepoint)
  end
  return nil
end

---Check whether a Unicode name contains a case-insensitive search string.
---@param codepoint integer Unicode code point.
---@param query string Search text; an empty string matches all code points.
---@return boolean matches Whether the name matches.
function M.matches(codepoint, query)
  query = type(query) == "string" and query:lower() or ""
  if query == "" then
    return true
  end
  local name = M.name(codepoint)
  return name ~= nil and name:lower():find(query, 1, true) ~= nil
end

return M
