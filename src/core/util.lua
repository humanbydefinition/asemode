local JSON = require("src.portable.json")
local jsonObjectTag = getmetatable(JSON.object())
local M = {}

---Raise an error when a condition is false and otherwise return its value.
---@param value any Condition or value to check.
---@param message string Error message.
---@return any value Original truthy value.
function M.check(value, message)
  if not value then
    error(message, 2)
  end
  return value
end

---Validate an integer within an inclusive range.
---@param value number Candidate value.
---@param name string Field name for error messages.
---@param low integer Minimum value.
---@param high integer Maximum value.
---@return integer value Validated integer.
function M.integer(value, name, low, high)
  M.check(
    type(value) == "number" and value == math.floor(value) and value >= low and value <= high,
    name .. " must be an integer from " .. low .. " to " .. high
  )
  return value
end

---Read a binary file, rejecting data above the optional limit.
---@param path string File path.
---@param limit? integer Maximum number of bytes.
---@return string data File contents.
function M.read(path, limit)
  local file, err = io.open(path, "rb")
  M.check(file, err or "Cannot open file")
  local data = (limit and file:read(limit + 1) or file:read("*a")) or ""
  file:close()
  if limit then
    M.check(#data <= limit, "File exceeds the " .. limit .. " byte limit")
  end
  return data
end

---Write binary data to a file and check both write and close errors.
---@param path string Destination path.
---@param data string File contents.
function M.write(path, data)
  local file, err = io.open(path, "wb")
  M.check(
    file,
    "Cannot save '"
      .. path
      .. "': "
      .. (err or "Cannot write file")
      .. ". Choose a writable folder and try again."
  )
  local ok, writeErr = file:write(data)
  local closed, closeErr = file:close()
  M.check(ok and closed, writeErr or closeErr or "Cannot save file")
end

---Serialize a value as formatted JSON.
---@param value any Value to serialize.
---@return string json Formatted JSON with a trailing newline.
function M.prettyJson(value)
  ---Recursively tag tables as JSON arrays if dense and sequential.
  ---@param item any Value to inspect and tag.
  ---@return any tagged Tagged array or unchanged value.
  local function tagArrays(item)
    if type(item) ~= "table" or item == JSON.null then
      return item
    end
    local copy, count, array, dense = {}, 0, JSON.isArray(item), true
    for key, child in pairs(item) do
      count = count + 1
      dense = dense and math.type(key) == "integer" and key > 0
      copy[key] = tagArrays(child)
    end
    if not array and getmetatable(item) ~= jsonObjectTag and dense and #item == count then
      array = true
    end
    return array and JSON.array(copy) or copy
  end
  return JSON.stringify(tagArrays(value))
end

---Split UTF-8 text into Unicode scalar characters.
---@param text string UTF-8 text.
---@return string[] characters Characters in input order.
function M.characters(text)
  local result = {}
  for _, cp in utf8.codes(text) do
    M.check(cp < 0xd800 or cp > 0xdfff, "Surrogates are not Unicode characters")
    result[#result + 1] = utf8.char(cp)
  end
  return result
end

---Calculate the FNV-1a hash of binary data.
---@param bytes string Input bytes.
---@return string hash Eight lowercase hexadecimal digits.
function M.hash(bytes)
  local value = 2166136261
  for i = 1, #bytes do
    value = ((value ~ bytes:byte(i)) * 16777619) & 0xffffffff
  end
  return string.format("%08x", value)
end

---Format RGBA channels as a lowercase hexadecimal color.
---@param r integer Red channel.
---@param g integer Green channel.
---@param b integer Blue channel.
---@param a? integer Alpha channel; defaults to 255.
---@return string hex Color in #rrggbbaa form.
function M.hex(r, g, b, a)
  return string.format("#%02x%02x%02x%02x", r, g, b, a or 255)
end

---Parse a hexadecimal RGBA color or raise an error for invalid input.
---@param hex string Color in #rrggbbaa form.
---@return integer red Red channel.
---@return integer green Green channel.
---@return integer blue Blue channel.
---@return integer alpha Alpha channel.
function M.rgba(hex)
  M.check(M.isHexColor(hex), "Expected #rrggbbaa color")
  return tonumber(hex:sub(2, 3), 16),
    tonumber(hex:sub(4, 5), 16),
    tonumber(hex:sub(6, 7), 16),
    tonumber(hex:sub(8, 9), 16)
end

---Check whether a value is an RGBA hexadecimal color.
---@param value any Value to inspect.
---@return boolean isHex True if the value is an 8-character hex string starting with #.
function M.isHexColor(value)
  return type(value) == "string" and value:match("^#%x%x%x%x%x%x%x%x$") ~= nil
end

---Convert an RGBA hexadecimal color to a host color.
---@param hex string Color in #rrggbbaa format.
---@return Color color Aseprite Color instance.
function M.color(hex)
  return Color(M.rgba(hex))
end

---Convert a host color to an RGBA hexadecimal color.
---@param color Color Aseprite Color instance.
---@return string hex Lowercase hexadecimal color in #rrggbbaa format.
function M.colorHex(color)
  return M.hex(color.red, color.green, color.blue, color.alpha)
end

---Check whether a value is a lowercase SHA-256 digest.
---@param value any Value to inspect.
---@return boolean isSha256 True if the value is 64 hexadecimal characters.
function M.isSha256(value)
  return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
end

---Return a frame number from a number or host frame.
---@param frame Frame|integer Aseprite frame or 1-based frame index.
---@return integer frameNumber 1-based frame number.
function M.frameNumber(frame)
  return type(frame) == "number" and frame or frame.frameNumber
end

---Remove a leading Lua source location from an error.
---@param err any Error value or message string.
---@return string message Cleaned error message without file/line prefix.
function M.cleanError(err)
  local message = tostring(err)
  return message:match("^.-:%d+:%s*(.*)$") or message
end

---Build a key for a glyph and two color values.
---@param glyph string Glyph key.
---@param fg string Foreground color.
---@param bg string Background color.
---@param orientation? integer Optional orientation.
---@return string key Composite key.
function M.key(glyph, fg, bg, orientation)
  return glyph .. "\0" .. fg .. bg .. (orientation ~= nil and (":" .. tostring(orientation)) or "")
end

---Recursively copy tables and host JSON objects into Lua tables.
---@param value any Value to copy.
---@return any copy Copied table or original scalar.
function M.copy(value)
  if type(value) ~= "table" and type(value) ~= "userdata" then
    return value
  end
  local result = {}
  -- Aseprite JsonObj array pairs() yields no values; numeric indexing is reliable.
  if type(value) == "userdata" and value[1] ~= nil then
    for i = 1, #value do
      result[i] = M.copy(value[i])
    end
  else
    for k, v in pairs(value) do
      result[k] = M.copy(v)
    end
  end
  return result
end

---Decode host JSON and copy its objects into Lua tables.
---@param value string JSON input.
---@return any decoded Copied decoded value.
function M.decode(value)
  return M.copy(json.decode(value))
end

---Return the final component of a slash- or backslash-separated path.
---@param path string Input path.
---@return string basename Final path component, or the original path.
function M.basename(path)
  return (path:gsub("\\", "/"):match("([^/]+)$") or path)
end

return M
