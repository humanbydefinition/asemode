local U = require("src.core.util")
local M = {}

---Create helpers for adding and updating dialog controls.
---@return table controls Dialog control helpers.
function M.new()
  local self = {}
  ---Enable or disable numeric inputs and their increment controls.
  ---@param d Dialog Target dialog containing the controls.
  ---@param ids string[] Base identifiers for the numeric inputs.
  ---@param enabled boolean Whether the controls should be enabled.
  function self:setNumericEnabled(d, ids, enabled)
    for _, id in ipairs(ids) do
      for _, suffix in ipairs({ "", "Increase", "Decrease" }) do
        d:modify({ id = id .. suffix, enabled = enabled })
      end
    end
  end

  ---Parse and clamp an integer, using a fallback for invalid input.
  ---@param value any Raw string or numeric value.
  ---@param minVal integer Lower inclusive bound.
  ---@param maxVal integer Upper inclusive bound.
  ---@param fallback integer Default value if input is not a number.
  ---@return integer clamped Clamped integer value.
  function self:clampInt(value, minVal, maxVal, fallback)
    local number = tonumber(value)
    if not number or number ~= number then
      number = fallback
    end
    return math.max(minVal, math.min(maxVal, math.floor(number)))
  end

  ---Add a bounded numeric input with increment and decrement buttons.
  ---@param d Dialog Destination dialog.
  ---@param id string Control identifier.
  ---@param label string Input label.
  ---@param text string Initial value.
  ---@param options table? Bounds, precision, step, and change callback.
  ---@return Dialog dialog Destination dialog.
  function self:addNumericInput(d, id, label, text, options)
    options = options or {}
    local decimals = options.decimals or 0
    local minVal = options.min or 1
    local maxVal = options.max or math.huge
    local minTimer = nil

    ---Cancel and clean up any pending minimum-value timer.
    local function stopMinTimer()
      if minTimer then
        pcall(function()
          minTimer:stop()
        end)
        minTimer = nil
      end
    end

    ---Format a numeric value according to configured decimal precision.
    ---@param v number Numeric value to format.
    ---@return string formatted Formatted string without trailing zeros.
    local function formatVal(v)
      if decimals == 0 then
        return tostring(math.floor(v + 0.5))
      end
      local precision = 10 ^ decimals
      local rounded = math.floor(v * precision + 0.5) / precision
      return string.format("%." .. decimals .. "f", rounded):gsub("0+$", ""):gsub("%.$", "")
    end

    ---Clamp, format, and apply a new value to the dialog input.
    ---@param nextValue number Target value.
    local function setValue(nextValue)
      stopMinTimer()
      nextValue = math.max(minVal, math.min(maxVal, nextValue))
      local formatted = formatVal(nextValue)
      d:modify({ id = id, text = formatted })
      if options.onchange then
        options.onchange()
      end
    end

    ---Adjust current input value by direction and step increment.
    ---@param direction integer Direction multiplier (1 for increase, -1 for decrease).
    ---@param step number Step delta.
    local function changeValue(direction, step)
      setValue((tonumber(d.data[id]) or tonumber(text) or minVal) + direction * step)
    end

    ---Validate and auto-clamp numeric text on user input.
    local function handleNumberChange()
      stopMinTimer()
      local raw = d.data[id]
      local num = tonumber(raw)
      if options.max and num and num > maxVal then
        d:modify({ id = id, text = formatVal(maxVal) })
      elseif num and minVal > 0 and num < 0 then
        d:modify({ id = id, text = formatVal(minVal) })
      elseif num and minVal > 0 and minVal <= 1 and num < minVal then
        d:modify({ id = id, text = formatVal(minVal) })
      elseif num and minVal > 1 and num < minVal then
        local createTimer = type(Timer) == "function" and Timer or nil
        if createTimer and (not app or app.isUIAvailable ~= false) then
          local ok, t = pcall(createTimer, {
            interval = 0.6,
            ontick = function()
              stopMinTimer()
              local currentNum = tonumber(d.data and d.data[id])
              if currentNum and currentNum < minVal then
                pcall(function()
                  d:modify({ id = id, text = formatVal(minVal) })
                end)
                if options.onchange then
                  options.onchange()
                end
              end
            end,
          })
          if ok and t then
            minTimer = t
            pcall(function()
              minTimer:start()
            end)
          end
        end
      end
      if options.onchange then
        options.onchange()
      end
    end

    d:number({
      id = id,
      label = label,
      text = text,
      decimals = decimals,
      enabled = options.enabled ~= false,
      onchange = handleNumberChange,
    })
      :samerow()
      :button({
        id = id .. "Increase",
        text = "+",
        enabled = options.enabled ~= false,
        onclick = function()
          changeValue(1, options.step or 1)
        end,
      })
      :samerow()
      :button({
        id = id .. "Decrease",
        text = "-",
        enabled = options.enabled ~= false,
        onclick = function()
          changeValue(-1, options.step or 1)
        end,
      })
    return d
  end

  ---Add a bounded font size input.
  ---@param d Dialog Destination dialog.
  ---@param text string Initial font size.
  ---@param options table? Numeric input overrides.
  ---@return Dialog dialog Destination dialog.
  function self:addFontSizeInput(d, text, options)
    local numericOptions = { min = 1, max = 128, step = 1 }
    for key, value in pairs(options or {}) do
      numericOptions[key] = value
    end
    local size = math.floor(tonumber(text) or 8)
    size = math.max(numericOptions.min, math.min(numericOptions.max, size))
    return self:addNumericInput(d, "size", "Font size", tostring(size), numericOptions)
  end

  ---Add a background color input and return a reader for its current value.
  ---@param d Dialog Destination dialog.
  ---@param initialHex string? Initial RGBA color.
  ---@param options table? Control identifier, label, and change callback.
  ---@return fun(): string readColor Reads the selected RGBA color.
  function self:addBackgroundInput(d, initialHex, options)
    options = options or {}
    local id = options.id or "backgroundColor"
    local r, g, b, a = 255, 255, 255, 0
    if U.isHexColor(initialHex) then
      r, g, b, a = U.rgba(initialHex:lower())
    end
    d:color({
      id = id,
      label = options.label or "Background",
      color = Color({ r = r, g = g, b = b, a = a }),
      onchange = options.onchange,
    })
    return function()
      local background = d.data[id]
      U.check(background, "Choose a background color")
      return U.colorHex(background)
    end
  end

  return self
end

return M
