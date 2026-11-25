-- Run in Aseprite batch mode with --script-param root=<repository>.
local root = assert(app.params.root, "Pass the repository root as a script parameter")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Loader = require("src.fonts.loader")
local Render = require("src.fonts.render")
local Model = require("src.document.model")
local Validate = require("src.document.validate")
local pc = app.pixelColor

for _, antialias in ipairs({ false, true }) do
  for _, id in ipairs({ "atascii", "cpc464", "unscii-8", "bescii" }) do
    for _, size in ipairs({ 8, 12, 14, 16, 24 }) do
      local job = Loader.bundled(id, { pixelSize = size, antialias = antialias })
      local p = job.profile
      assert(p.clippedGlyphs == 0, "automatically measured glyph outlines must fit")
      assert(p.cellWidth == size and p.cellHeight == size, "unexpected extra cell pixels")
      for _, glyph in ipairs(job.glyphs) do
        local expanded = {}
        for key, value in pairs(p) do
          expanded[key] = value
        end
        local padding = 2
        expanded.cellWidth, expanded.cellHeight =
          p.cellWidth + 2 * padding, p.cellHeight + 2 * padding
        expanded.originX, expanded.baseline = p.originX + padding, p.baseline + padding
        local image = Render.mask(glyph, expanded)
        for y = 0, image.height - 1 do
          for x = 0, image.width - 1 do
            if
              x < padding
              or x >= p.cellWidth + padding
              or y < padding
              or y >= p.cellHeight + padding
            then
              assert(
                pc.rgbaA(image:getPixel(x, y)) == 0,
                string.format("%s at %d clipped glyph %s", id, size, glyph.glyphKey)
              )
            end
          end
        end
      end
    end
  end
end

local job = Loader.bundled("atascii", { pixelSize = 12 }):finish()
local sprite = Model.create(job, 40, 25, false, "transparent")
assert(sprite.width == 480 and sprite.height == 300 and #Validate.run(sprite) == 0)
sprite:close()
print("PASS measured glyphs fit their cells and created canvas")
