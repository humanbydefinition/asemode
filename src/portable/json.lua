-- Typed JSON for portable documents. The host bridge truncates embedded NULs.
local M = {}
local arrayTag, objectTag = {}, {}
M.null = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

---Mark a table as a JSON array, preserving the supplied table.
---@param value? table Table to mark; defaults to a new table.
---@return table array Tagged array.
function M.array(value)
  return setmetatable(value or {}, arrayTag)
end

---Mark a table as a JSON object, preserving the supplied table.
---@param value? table Table to mark; defaults to a new table.
---@return table object Tagged object.
function M.object(value)
  return setmetatable(value or {}, objectTag)
end

---Check whether a value carries the JSON array tag.
---@param value any Value to inspect.
---@return boolean isArray Whether the value is a tagged array.
function M.isArray(value)
  return type(value) == "table" and getmetatable(value) == arrayTag
end

---Check whether a value is a JSON object table.
---@param value any Value to inspect.
---@return boolean isObject Whether the value is an object.
function M.isObject(value)
  return type(value) == "table" and value ~= M.null and not M.isArray(value)
end

---Parse JSON into tagged tables and the JSON null sentinel.
---@param text string JSON input.
---@param options table? Maximum depth and optional checkpoint.
---@return any value Parsed JSON value.
function M.parse(text, options)
  options = options or {}
  local position, operations = 1, 0

  ---Raise a JSON parsing syntax error with byte position.
  ---@param message string Error description.
  local function fail(message)
    error({ code = "INVALID_JSON", message = message .. " at byte " .. position }, 0)
  end

  ---Increment operation counter and trigger periodic cooperativity checkpoint.
  local function tick()
    operations = operations + 1
    if operations % 256 == 0 and options.checkpoint then
      options.checkpoint()
    end
  end

  ---Advance position past any ASCII whitespace.
  local function space()
    local _, last = text:find("^[ \t\r\n]*", position)
    position = (last or position - 1) + 1
  end

  local escapes =
    { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

  ---Parse a quoted string token and handle escape sequences.
  ---@return string str Parsed UTF-8 string.
  local function stringValue()
    position = position + 1
    local output, start = {}, position
    while position <= #text do
      tick()
      local byte = text:byte(position)
      if byte == 34 or byte == 92 then
        output[#output + 1] = text:sub(start, position - 1)
        position = position + 1
        if byte == 34 then
          local result = table.concat(output)
          if not utf8.len(result, 1, -1, true) then
            fail("Invalid UTF-8 string")
          end
          return result
        end
        local escape = text:sub(position, position)
        if escape == "u" then
          local hex = text:sub(position + 1, position + 4)
          if #hex ~= 4 or not hex:match("^%x+$") then
            fail("Invalid Unicode escape")
          end
          local cp = tonumber(hex, 16)
          position = position + 5
          if cp >= 0xd800 and cp <= 0xdbff and text:sub(position, position + 1) == "\\u" then
            local lowHex = text:sub(position + 2, position + 5)
            local low = #lowHex == 4 and lowHex:match("^%x+$") and tonumber(lowHex, 16)
            if low and low >= 0xdc00 and low <= 0xdfff then
              cp = 0x10000 + (cp - 0xd800) * 1024 + low - 0xdc00
              position = position + 6
            end
          end
          output[#output + 1] = utf8.char(cp)
        else
          if not escapes[escape] then
            fail("Invalid string escape")
          end
          output[#output + 1] = escapes[escape]
          position = position + 1
        end
        start = position
      elseif byte < 32 then
        fail("Unescaped control character")
      else
        position = position + 1
      end
    end
    fail("Unterminated string")
  end
  local value
  value = function(depth)
    tick()
    space()
    if depth > (options.maxDepth or 128) then
      error({ code = "LIMIT_EXCEEDED", message = "JSON nesting limit exceeded", path = "$" }, 0)
    end
    local char = text:sub(position, position)
    if char == '"' then
      return stringValue()
    end
    if char == "{" or char == "[" then
      local isArray, closing = char == "[", char == "[" and "]" or "}"
      local result = isArray and M.array() or M.object()
      position = position + 1
      space()
      if text:sub(position, position) == closing then
        position = position + 1
        return result
      end
      while true do
        local key
        if isArray then
          key = #result + 1
        else
          if text:sub(position, position) ~= '"' then
            fail("Expected an object key")
          end
          key = stringValue()
          space()
          if text:sub(position, position) ~= ":" then
            fail("Expected a colon")
          end
          position = position + 1
        end
        result[key] = value(depth + 1)
        space()
        char = text:sub(position, position)
        position = position + 1
        if char == closing then
          return result
        end
        if char ~= "," then
          fail("Expected a comma or closing delimiter")
        end
        space()
      end
    end
    for literal, result in pairs({ ["true"] = true, ["false"] = false, ["null"] = M.null }) do
      if text:sub(position, position + #literal - 1) == literal then
        position = position + #literal
        return result
      end
    end
    if char == "-" or char:match("%d") then
      local start = position
      if char == "-" then
        position = position + 1
      end
      if text:sub(position, position) == "0" then
        position = position + 1
      else
        local _, last = text:find("^[1-9]%d*", position)
        if not last then
          fail("Invalid number")
        end
        position = last + 1
      end
      if text:sub(position, position) == "." then
        local _, last = text:find("^%.%d+", position)
        if not last then
          fail("Invalid fraction")
        end
        position = last + 1
      end
      if text:sub(position, position):match("[eE]") then
        local _, last = text:find("^[eE][+-]?%d+", position)
        if not last then
          fail("Invalid exponent")
        end
        position = last + 1
      end
      return tonumber(text:sub(start, position - 1))
    end
    fail("Expected a JSON value")
  end
  local result = value(0)
  space()
  if position <= #text then
    fail("Unexpected trailing input")
  end
  return result
end

---Encode a string with standard JSON escape sequences and UTF-16 surrogate preservation.
---@param text string String to escape.
---@return string quoted Quoted and escaped JSON string literal.
local function quoted(text)
  local output = { '"' }
  for _, cp in utf8.codes(text, true) do
    if cp == 34 then
      output[#output + 1] = '\\"'
    elseif cp == 92 then
      output[#output + 1] = "\\\\"
    elseif cp < 32 or (cp >= 0xd800 and cp <= 0xdfff) then
      output[#output + 1] = string.format("\\u%04x", cp)
    else
      output[#output + 1] = utf8.char(cp)
    end
  end
  output[#output + 1] = '"'
  return table.concat(output)
end

---Serialize a JSON value with deterministic object key order.
---@param value any Value to serialize.
---@param options table? Pretty printing, byte limit, and optional checkpoint.
---@return string text Serialized JSON.
function M.stringify(value, options)
  options = options or {}
  local pretty, output, operations = options.pretty ~= false, {}, 0
  local chunk, bytes = {}, 0

  ---Append serialized snippet to chunks, enforcing byte limit.
  ---@param text string Serialized text segment.
  local function append(text)
    bytes = bytes + #text
    if options.maxBytes and bytes > options.maxBytes then
      error(
        { code = "LIMIT_EXCEEDED", message = "Serialized JSON exceeds the byte budget", path = "$" },
        0
      )
    end
    chunk[#chunk + 1] = text
    if #chunk == 1024 then
      output[#output + 1] = table.concat(chunk)
      chunk = {}
    end
  end

  ---Emit newline and 2-space indentation based on nesting depth.
  ---@param depth integer Current indentation nesting level.
  local function line(depth)
    if pretty then
      append("\n" .. string.rep("  ", depth))
    end
  end
  local write
  write = function(item, depth)
    operations = operations + 1
    if operations % 256 == 0 and options.checkpoint then
      options.checkpoint()
    end
    if item == M.null then
      append("null")
    elseif type(item) == "string" then
      append(quoted(item))
    elseif type(item) == "boolean" then
      append(item and "true" or "false")
    elseif type(item) == "number" then
      assert(item == item and math.abs(item) < math.huge, "Cannot encode non-finite JSON number")
      append(string.format("%.17g", item == 0 and 0 or item))
    elseif type(item) == "table" then
      local array, keys = M.isArray(item), {}
      if array then
        for i = 1, #item do
          keys[i] = i
        end
      else
        for key in pairs(item) do
          assert(type(key) == "string")
          keys[#keys + 1] = key
        end
        table.sort(keys)
      end
      append(array and "[" or "{")
      for i, key in ipairs(keys) do
        if i > 1 then
          append(",")
        end
        line(depth + 1)
        if not array then
          append(quoted(key))
          append(pretty and ": " or ":")
        end
        write(item[key], depth + 1)
      end
      if #keys > 0 then
        line(depth)
      end
      append(array and "]" or "}")
    else
      error("Unsupported JSON value: " .. type(item))
    end
  end
  write(value, 0)
  if pretty then
    append("\n")
  end
  output[#output + 1] = table.concat(chunk)
  return table.concat(output)
end

return M
