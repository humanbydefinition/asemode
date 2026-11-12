local root = assert(app.params.root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Render = require("src.fonts.render")
local Preview = require("src.ui.font_preview")
local pc = app.pixelColor
local glyph = {
  glyphKey = "X",
  xMin = -2,
  xMax = 10,
  yMin = -4,
  yMax = 8,
  contours = {
    {
      { x = -2, y = -4, on = true },
      { x = 10, y = -4, on = true },
      { x = 10, y = 8, on = true },
      { x = -2, y = 8, on = true },
    },
  },
}
for _, antialias in ipairs({ false, true }) do
  local profile = {
    cellWidth = 8,
    cellHeight = 8,
    originX = 0,
    baseline = 6,
    scale = 1,
    antialias = antialias,
  }
  local cell = Render.mask(glyph, profile)
  local sample = { { index = 1, clipped = true } }
  local extent = Preview.prepare({ profile = profile, glyphs = { glyph } }, sample)
  assert(extent.left == 2 and extent.right == 2 and extent.top == 2 and extent.bottom == 2)
  local overflow = sample[1].overflow
  for y = 0, overflow.height - 1 do
    for x = 0, overflow.width - 1 do
      local inside = x >= 2 and x < 10 and y >= 2 and y < 10
      local alpha = pc.rgbaA(overflow:getPixel(x, y))
      if inside then
        assert(alpha == 0 and pc.rgbaA(cell:getPixel(x - 2, y - 2)) == 255)
      else
        assert(alpha == 255)
      end
    end
  end
end
print("PASS font preview overflow rasterization")
