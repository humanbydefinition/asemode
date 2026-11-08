local JSON = require("src.portable.json")
local M = { format = "textmode.document", version = "4.0.0", maxBytes = 64 * 1024 * 1024 }
local SAFE = 9007199254740991
local defaults = {
  maxCells = 4000000,
  maxLayers = 256,
  maxFrames = 65536,
  maxTotalLayers = 65536,
  maxLayerIdLength = 1024,
  maxCharacterLength = 64,
  maxMetadataStringLength = 4096,
  maxDepth = 128,
  maxBytes = M.maxBytes,
}

---Raise a structured codec validation error.
---@param code string Machine-readable error code.
---@param message string Human-readable error description.
---@param path? string JSONPath-like location of the offending field.
local function fail(code, message, path)
  error({ code = code, message = message, path = path }, 0)
end

---Assert that a condition holds, failing with INVALID_DOCUMENT otherwise.
---@param test any Condition expression to verify.
---@param message string Error description if assertion fails.
---@param path? string JSONPath-like location.
local function need(test, message, path)
  if not test then
    fail("INVALID_DOCUMENT", message, path)
  end
end

---Validate that a value is a JSON object table.
---@param value any Value to inspect.
---@param path string JSONPath-like location.
---@return table record Validated object table.
local function record(value, path)
  need(JSON.isObject(value), "Expected an object", path)
  return value
end

---Validate that a value is a JSON array table.
---@param value any Value to inspect.
---@param path string JSONPath-like location.
---@return table array Validated array table.
local function array(value, path)
  need(JSON.isArray(value), "Expected an array", path)
  return value
end

---Validate that a value is a finite number.
---@param value any Value to inspect.
---@param path string JSONPath-like location.
---@return number num Validated finite number.
local function number(value, path)
  need(
    type(value) == "number" and value == value and math.abs(value) < math.huge,
    "Expected a finite number",
    path
  )
  return value
end

---Validate that a value is an integer within safe double integer bounds.
---@param value any Value to inspect.
---@param path string JSONPath-like location.
---@param positive? boolean Whether the integer must be strictly positive.
---@return integer int Validated safe integer.
local function integer(value, path, positive)
  need(
    type(value) == "number" and math.abs(value) <= SAFE and value == math.floor(value),
    "Expected a safe integer",
    path
  )
  need(not positive or value > 0, "Expected a positive safe integer", path)
  return value
end

---Compute the product of two positive factors while checking against safe overflow.
---@param a number First factor.
---@param b number Second factor.
---@param path string JSONPath-like location.
---@return number product Computed product.
local function product(a, b, path)
  if a > SAFE / b then
    fail("LIMIT_EXCEEDED", "Unsafe dimension product", path)
  end
  return a * b
end

---Validate that a value is a boolean.
---@param value any Value to inspect.
---@param path string JSONPath-like location.
---@return boolean bool Validated boolean value.
local function boolean(value, path)
  need(type(value) == "boolean", "Expected a boolean", path)
  return value
end

---Validate that a value is non-empty UTF-8 text within length limits.
---@param value any Value to inspect.
---@param path string JSONPath-like location.
---@param limit number Maximum allowed character count.
---@param glyph? boolean Whether lone surrogates are disallowed for glyphs.
---@return string text Validated UTF-8 string.
local function text(value, path, limit, glyph)
  need(type(value) == "string" and #value > 0, "Expected a non-empty string", path)
  need(utf8.len(value, 1, -1, true) ~= nil, "Invalid UTF-8 string", path)
  local count = 0
  for _, cp in utf8.codes(value, true) do
    if glyph then
      need(cp < 0xd800 or cp > 0xdfff, "Glyph contains an unpaired surrogate", path)
    end
    count = count + (not glyph and cp > 0xffff and 2 or 1)
  end
  if count > limit then
    fail("LIMIT_EXCEEDED", "String exceeds the configured limit", path)
  end
  return value
end

---Validate and normalize a color definition into RGBA integer components.
---@param value any Color hex string or RGBA table.
---@param path string JSONPath-like location.
---@return table color Table with numeric r, g, b, a channels in [0, 255].
local function color(value, path)
  if type(value) == "string" then
    need(
      (#value == 7 or #value == 9) and value:match("^#%x+$"),
      "Expected #RRGGBB or #RRGGBBAA",
      path
    )
    return {
      r = tonumber(value:sub(2, 3), 16),
      g = tonumber(value:sub(4, 5), 16),
      b = tonumber(value:sub(6, 7), 16),
      a = #value == 9 and tonumber(value:sub(8, 9), 16) or 255,
    }
  end
  record(value, path)
  local result = {}
  for _, key in ipairs({ "r", "g", "b", "a" }) do
    result[key] = integer(value[key], path .. "." .. key)
    need(result[key] >= 0 and result[key] <= 255, "Expected a color byte", path .. "." .. key)
  end
  return result
end

---Validate an RFC 3339 uppercase timestamp string with timezone.
---@param value string Timestamp string.
---@param path string JSONPath-like location.
---@return string timestamp Validated timestamp string.
local function timestamp(value, path)
  local year, month, day, hour, minute, second, tail =
    value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
  need(year ~= nil, "Expected an uppercase RFC 3339 timestamp", path)
  year, month, day, hour, minute, second =
    tonumber(year),
    tonumber(month),
    tonumber(day),
    tonumber(hour),
    tonumber(minute),
    tonumber(second)
  tail = tail:gsub("^%.%d+", "")
  local zoneHour, zoneMinute = tail:match("^[+-](%d%d):(%d%d)$")
  need(
    tail == "Z" or (zoneHour and tonumber(zoneHour) <= 23 and tonumber(zoneMinute) <= 59),
    "Expected a timezone",
    path
  )
  local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
  local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  need(
    month >= 1
      and month <= 12
      and day >= 1
      and day <= (days[month] or 0)
      and hour <= 23
      and minute <= 59
      and second <= 59,
    "Invalid calendar date or time",
    path
  )
  return value
end

---Resolve and validate decoding resource limits against defaults.
---@param options? table Optional user limit overrides.
---@return table limits Resolved limit table.
local function limits(options)
  local result = {}
  for key, fallback in pairs(defaults) do
    local v = options and options[key]
    if v == nil then
      v = fallback
    end
    assert(
      type(v) == "number" and v > 0 and v <= SAFE and v == math.floor(v),
      key .. " must be a positive safe integer"
    )
    result[key] = v
  end
  return result
end

-- Integer durations are common and fit safely in Lua's 64-bit integers.
-- Fractional durations need exact binary accumulation: even the smallest
-- positive tail must not disappear when the total is near SAFE.
---Create an accumulator for frame durations that prevents precision loss near 2^53 - 1.
---@return fun(value: number): boolean add Adds a duration and returns false if safe range is exceeded.
local function durationAccumulator()
  local total, limbs, maximum = 0, nil, nil

  ---Initialize multi-limb representation for IEEE 754 precision tracking.
  local function initialize()
    limbs, maximum = {}, {}
    for i = 1, 36 do
      limbs[i], maximum[i] = 0, 0
    end
    for bit = 1074, 1126 do
      local index = bit // 32 + 1
      maximum[index] = maximum[index] | (1 << (bit % 32))
    end
  end

  ---Add a 32-bit chunk into limbs with carry propagation.
  ---@param index integer Limb index.
  ---@param value integer Chunk value.
  ---@return boolean ok True if carry remained within limb count.
  local function add(index, value)
    while value ~= 0 do
      if index > #limbs then
        return false
      end
      local sum = limbs[index] + value
      limbs[index] = sum & 0xffffffff
      value, index = sum >> 32, index + 1
    end
    return true
  end

  ---Add an exact floating-point value decomposed into binary limbs.
  ---@param value number Float value to accumulate.
  ---@return boolean ok True if total did not exceed safe maximum.
  local function addBinary(value)
    local high, low = string.unpack(">I4I4", string.pack(">d", value))
    local exponent = (high >> 20) & 0x7ff
    local upper, shift = high & 0xfffff, 0
    if exponent ~= 0 then
      upper, shift = upper | 0x100000, exponent - 1
    end
    local offset, bits = shift // 32 + 1, shift % 32
    if not add(offset, low << bits) or not add(offset + 1, upper << bits) then
      return false
    end
    for i = #limbs, 1, -1 do
      if limbs[i] ~= maximum[i] then
        return limbs[i] < maximum[i]
      end
    end
    return true
  end
  return function(value)
    local integer = math.tointeger(value)
    if not limbs and integer then
      if integer > SAFE - total then
        return false
      end
      total = total + integer
      return true
    end
    if not limbs then
      initialize()
      if total > 0 then
        addBinary(total)
      end
    end
    return addBinary(value)
  end
end

---Validate and normalize raw decoded JSON data into canonical portable document structure.
---@param root table Raw JSON object root.
---@param budget table Configured decoding limits.
---@param checkpoint? fun() Periodic cooperativity checkpoint.
---@param recoverFont? fun(id: any, sourceIndex: integer, name: any) Callback for font recovery.
---@return table result Normalized document container with ok flag and warnings.
local function canonical(root, budget, checkpoint, recoverFont)
  record(root, "$")
  need(type(root.format) == "string", "Expected a string", "$.format")
  if root.format ~= M.format then
    fail("UNSUPPORTED_FORMAT", "Expected textmode.document artwork (not an atlas)", "$.format")
  end
  need(type(root.formatVersion) == "string", "Expected a string", "$.formatVersion")
  local major, minor, patch = root.formatVersion:match("^(%d+)%.(%d+)%.(%d+)$")
  if
    not major
    or #major > 1 and major:sub(1, 1) == "0"
    or #minor > 1 and minor:sub(1, 1) == "0"
    or #patch > 1 and patch:sub(1, 1) == "0"
    or tonumber(major) < 4
  then
    fail("UNSUPPORTED_VERSION", "Expected document version 4.0.0 or later", "$.formatVersion")
  end
  for _, key in ipairs({ "layers", "target", "layer", "grid", "canvas" }) do
    need(root[key] == nil, "Obsolete root field", "$." .. key)
  end
  local result = { format = M.format, formatVersion = M.version, frames = JSON.array() }
  if root.metadata ~= nil then
    local meta = record(root.metadata, "$.metadata")
    local gen = record(meta.generator, "$.metadata.generator")
    result.metadata = {
      createdAt = timestamp(
        text(meta.createdAt, "$.metadata.createdAt", budget.maxMetadataStringLength),
        "$.metadata.createdAt"
      ),
      generator = {
        name = text(gen.name, "$.metadata.generator.name", budget.maxMetadataStringLength),
        version = text(gen.version, "$.metadata.generator.version", budget.maxMetadataStringLength),
      },
    }
  end
  local frames = JSON.array()
  do
    local inputFrames = array(root.frames, "$.frames")
    need(#inputFrames > 0, "Expected at least one frame", "$.frames")
    if #inputFrames > budget.maxFrames then
      fail("LIMIT_EXCEEDED", "Frame count exceeds the configured limit", "$.frames")
    end
    local totalLayers, addDuration = 0, durationAccumulator()
    for i, inputFrame in ipairs(inputFrames) do
      local framePath = "$.frames[" .. (i - 1) .. "]"
      record(inputFrame, framePath)
      local duration = number(inputFrame.durationMs, framePath .. ".durationMs")
      need(duration > 0 and duration <= SAFE, "Invalid frame duration", framePath .. ".durationMs")
      if not addDuration(duration) then
        fail("LIMIT_EXCEEDED", "Cumulative duration exceeds safe range", framePath .. ".durationMs")
      end
      local values = array(inputFrame.layers, framePath .. ".layers")
      if #values > budget.maxLayers then
        fail("LIMIT_EXCEEDED", "Layer count exceeds the configured limit", framePath .. ".layers")
      end
      totalLayers = totalLayers + #values
      if totalLayers > budget.maxTotalLayers then
        fail(
          "LIMIT_EXCEEDED",
          "Total layer count exceeds the configured limit",
          framePath .. ".layers"
        )
      end
      local ids = {}
      for j, value in ipairs(values) do
        local path = framePath .. ".layers[" .. (j - 1) .. "]"
        record(value, path)
        local id = text(value.id, path .. ".id", budget.maxLayerIdLength)
        need(not ids[id], "Duplicate layer ID", path .. ".id")
        ids[id] = true
      end
      frames[i] = { values = values, path = framePath .. ".layers", durationMs = duration }
    end
  end
  local remaining, sourceIndex = budget.maxCells, 0
  for frameIndex, frame in ipairs(frames) do
    local outputFrame = { durationMs = frame.durationMs, layers = JSON.array() }
    result.frames[frameIndex] = outputFrame
    for i, value in ipairs(frame.values) do
      sourceIndex = sourceIndex + 1
      if checkpoint then
        checkpoint()
      end
      local path = frame.path .. "[" .. (i - 1) .. "]"
      record(value, path)
      local gridPath = path .. ".grid"
      local sourceGrid = record(value.grid, gridPath)
      local grid = {}
      for _, key in ipairs({ "cols", "rows", "cellWidth", "cellHeight" }) do
        grid[key] = integer(sourceGrid[key], gridPath .. "." .. key, true)
      end
      product(grid.cols, grid.cellWidth, gridPath .. ".cellWidth")
      product(grid.rows, grid.cellHeight, gridPath .. ".cellHeight")
      local count = product(grid.cols, grid.rows, path .. ".cells.rows")
      if count > remaining then
        fail("LIMIT_EXCEEDED", "Cumulative cell budget exceeded", path .. ".cells.rows")
      end
      remaining = remaining - count
      local layer = {
        id = text(value.id, path .. ".id", budget.maxLayerIdLength),
        grid = grid,
        visible = true,
        opacity = 1,
        blendMode = "normal",
        offsetX = 0,
        offsetY = 0,
        rotationZ = 0,
        cells = { encoding = "object-rows-v1", rows = JSON.array() },
      }
      do
        layer.visible = boolean(value.visible, path .. ".visible")
        layer.opacity = number(value.opacity, path .. ".opacity")
        need(
          layer.opacity >= 0 and layer.opacity <= 1,
          "Expected opacity from 0 through 1",
          path .. ".opacity"
        )
        layer.blendMode =
          text(value.blendMode, path .. ".blendMode", budget.maxMetadataStringLength)
        for _, key in ipairs({ "offsetX", "offsetY", "rotationZ" }) do
          layer[key] = number(value[key], path .. "." .. key)
        end
      end
      if value.font ~= nil then
        local sourceFont = record(value.font, path .. ".font")
        local rawId = sourceFont.id
        local recoverable = recoverFont
          and type(rawId) == "string"
          and #rawId <= 4096
          and not (#rawId == 79 and rawId:match("^sfnt%-v1%-sha256:[0-9a-f]+$"))
        local id
        if not recoverable then
          id = text(rawId, path .. ".font.id", 79)
          need(
            #id == 79 and id:match("^sfnt%-v1%-sha256:[0-9a-f]+$"),
            "Expected a complete sfnt-v1-sha256 identity",
            path .. ".font.id"
          )
        end
        local name
        if sourceFont.name ~= nil then
          name = text(sourceFont.name, path .. ".font.name", budget.maxMetadataStringLength)
        end
        if recoverable then
          recoverFont(rawId, sourceIndex, name)
        else
          layer.font = { id = id, name = name }
        end
      end
      local collection = record(value.cells, path .. ".cells")
      need(type(collection.encoding) == "string", "Expected a string", path .. ".cells.encoding")
      if collection.encoding ~= "object-rows-v1" then
        fail("UNSUPPORTED_ENCODING", "Unsupported cell encoding", path .. ".cells.encoding")
      end
      local rows = array(collection.rows, path .. ".cells.rows")
      need(#rows == grid.rows, "Cell rows disagree with the grid", path .. ".cells.rows")
      for y, sourceRow in ipairs(rows) do
        if checkpoint then
          checkpoint()
        end
        local rowPath = path .. ".cells.rows[" .. (y - 1) .. "]"
        array(sourceRow, rowPath)
        need(#sourceRow == grid.cols, "Cell columns disagree with the grid", rowPath)
        local row = JSON.array()
        for x, sourceCell in ipairs(sourceRow) do
          local cellPath = rowPath .. "[" .. (x - 1) .. "]"
          local cell = record(sourceCell, cellPath)
          local cx, cy = integer(cell.x, cellPath .. ".x"), integer(cell.y, cellPath .. ".y")
          need(
            cx == x - 1 and cy == y - 1,
            "Cell coordinates disagree with their row position",
            cellPath
          )
          local tr = record(cell.transform, cellPath .. ".transform")
          local rotation = number(tr.rotation, cellPath .. ".transform.rotation")
          row[x] = {
            x = cx,
            y = cy,
            character = text(
              cell.character,
              cellPath .. ".character",
              budget.maxCharacterLength,
              true
            ),
            foreground = color(cell.foreground, cellPath .. ".foreground"),
            background = color(cell.background, cellPath .. ".background"),
            transform = {
              invert = boolean(tr.invert, cellPath .. ".transform.invert"),
              flipX = boolean(tr.flipX, cellPath .. ".transform.flipX"),
              flipY = boolean(tr.flipY, cellPath .. ".transform.flipY"),
              rotation = ((rotation % 360) + 360) % 360,
            },
          }
        end
        layer.cells.rows[y] = row
      end
      outputFrame.layers[i] = layer
    end
  end
  return { ok = true, document = result, warnings = {} }
end

---Execute a protected decode block, converting structured errors to status tables.
---@param run fun(): any Function to execute.
---@return table result Success table or normalized error structure.
local function attempt(run)
  local ok, result = pcall(run)
  if ok then
    return result
  end
  if type(result) == "table" and result.code then
    return { ok = false, error = result }
  end
  error(result, 0)
end

---Validate and normalize a decoded portable document.
---@param value any Parsed document value.
---@param options table? Resource limits and optional checkpoint.
---@return table result Normalized document or structured error.
function M.decodeValue(value, options)
  local budget = limits(options)
  return attempt(function()
    return canonical(value, budget, options and options.checkpoint)
  end)
end

---Parse JSON text and convert it to a canonical portable document.
---@param textValue string Raw JSON text.
---@param options? table Optional decoding limits and checkpoint.
---@param recoverFont? fun(id: any, sourceIndex: integer, name: any) Optional font recovery callback.
---@return table result Normalized document or structured error.
local function decode(textValue, options, recoverFont)
  local budget = limits(options)
  return attempt(function()
    need(type(textValue) == "string", "Expected JSON text", "$")
    if #textValue > budget.maxBytes then
      fail("LIMIT_EXCEEDED", "JSON file exceeds the byte budget", "$")
    end
    return canonical(
      JSON.parse(
        textValue,
        { maxDepth = budget.maxDepth, checkpoint = options and options.checkpoint }
      ),
      budget,
      options and options.checkpoint,
      recoverFont
    )
  end)
end

---Parse and validate portable document JSON.
---@param textValue string JSON input.
---@param options table? Resource limits and optional checkpoint.
---@return table result Normalized document or structured error.
function M.decode(textValue, options)
  return decode(textValue, options)
end

-- Import-only recovery is opt-in; strict decode and encode never call this.
---Decode JSON while reporting invalid font identities to an import callback.
---@param textValue string JSON input.
---@param options table? Resource limits and optional checkpoint.
---@param recoverFont fun(id: any, sourceIndex: integer, name: any) Receives each recoverable font identity.
---@return table result Normalized document or structured error.
function M.decodeWithFontRecovery(textValue, options, recoverFont)
  assert(type(recoverFont) == "function", "Font recovery callback is required")
  return decode(textValue, options, recoverFont)
end

---Validate a portable document and serialize it as JSON.
---@param document table Document to encode.
---@param options table? Resource limits, color mode, and optional checkpoint.
---@return table result JSON text or structured error.
function M.encode(document, options)
  local validationOptions = {}
  for key, value in pairs(options or {}) do
    validationOptions[key] = value
  end
  -- Reader budget overrides never relax the published writer schema.
  validationOptions.maxCharacterLength = math.min(limits(options).maxCharacterLength, 64)
  validationOptions.maxMetadataStringLength =
    math.min(limits(options).maxMetadataStringLength, 4096)
  local result = M.decodeValue(document, validationOptions)
  if not result.ok then
    return result
  end
  if not options or options.colorMode ~= "rgba" then
    for _, frame in ipairs(result.document.frames) do
      for _, layer in ipairs(frame.layers) do
        for _, row in ipairs(layer.cells.rows) do
          if options and options.checkpoint then
            options.checkpoint()
          end
          for _, cell in ipairs(row) do
            for _, key in ipairs({ "foreground", "background" }) do
              local c = cell[key]
              cell[key] = string.format("#%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
            end
          end
        end
      end
    end
  end
  local serialOptions = {}
  for key, value in pairs(options or {}) do
    serialOptions[key] = value
  end
  serialOptions.maxBytes = limits(options).maxBytes
  return attempt(function()
    return { ok = true, text = JSON.stringify(result.document, serialOptions) }
  end)
end

---Format a portable-document error for display.
---@param result table Error or result containing an error.
---@return string message Error code, optional path, and message.
function M.message(result)
  local err = result.error or result
  return (err.code or "IMPORT_ERROR")
    .. (err.path and " at " .. err.path or "")
    .. ": "
    .. err.message
end

return M
