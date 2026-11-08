local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local T = require("src.document.transforms")
local pc = app.pixelColor
local image = Image(8, 8, ColorMode.RGB)
for y = 0, 7 do
  for x = 0, 7 do
    image:drawPixel(x, y, pc.rgba(x * 27, y * 27, (x * 7 + y) * 4, 255))
  end
end
for bits = 0, 7 do
  local flags = (bits & 1 ~= 0 and pc.TILE_XFLIP or 0)
    | (bits & 2 ~= 0 and pc.TILE_YFLIP or 0)
    | (bits & 4 ~= 0 and pc.TILE_DFLIP or 0)
  local old = image:clone()
  if bits & 4 ~= 0 then
    old:flip(FlipType.DIAGONAL)
  end
  if bits & 1 ~= 0 then
    old:flip(FlipType.HORIZONTAL)
  end
  if bits & 2 ~= 0 then
    old:flip(FlipType.VERTICAL)
  end
  assert(old.bytes == T.renderMask(image, flags).bytes, "transform mismatch " .. bits)
end
print("PASS square preview transform parity")
