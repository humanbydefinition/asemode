local JSON = require("src.portable.json")
local Codec = require("src.portable.codec")
local cases = JSON.parse(io.read("*a"))
local results = JSON.array()
for i, item in ipairs(cases) do
  local result = Codec.decode(item.text, item.limits)
  if result.ok then
    result.warnings = JSON.array(result.warnings)
  end
  results[i] = result
end
print(JSON.stringify(results))
