local M = {}

---Rasterize a glyph outline into a cell-sized alpha mask.
---@param glyph table Glyph outline and horizontal offset.
---@param profile table Cell geometry, scale, baseline, and antialiasing.
---@return Image mask Rendered glyph mask.
function M.mask(glyph, profile)
  local image = Image(profile.cellWidth, profile.cellHeight, ColorMode.RGB)
  local gc =
    assert(image.context, "This Aseprite build has no Image.context; use a standard Skia build")
  gc.antialias = profile.antialias
  gc.color = Color(255, 255, 255, 255)
  gc:beginPath()

  ---Transform a glyph coordinate into raster pixel coordinates.
  ---@param p table Vector point { x: number, y: number }.
  ---@return number px Raster pixel x coordinate.
  ---@return number py Raster pixel y coordinate.
  local function point(p)
    return profile.originX + (glyph.offsetX or 0) + p.x * profile.scale,
      profile.baseline - p.y * profile.scale
  end
  for _, contour in ipairs(glyph.contours) do
    local expanded = {}
    for i, p in ipairs(contour) do
      expanded[#expanded + 1] = p
      local nextP = contour[i % #contour + 1]
      if not p.on and not nextP.on then
        expanded[#expanded + 1] = { x = (p.x + nextP.x) / 2, y = (p.y + nextP.y) / 2, on = true }
      end
    end
    local start = 1
    while start <= #expanded and not expanded[start].on do
      start = start + 1
    end
    if start <= #expanded then
      local ordered = {}
      for j = 0, #expanded - 1 do
        ordered[#ordered + 1] = expanded[(start + j - 1) % #expanded + 1]
      end
      ordered[#ordered + 1] = ordered[1]
      local current = ordered[1]
      gc:moveTo(point(current))
      local i = 2
      while i <= #ordered do
        local p = ordered[i]
        if p.on then
          gc:lineTo(point(p))
          current = p
          i = i + 1
        else
          local finish = ordered[i + 1]
          local x0, y0 = point(current)
          local qx, qy = point(p)
          local x1, y1 = point(finish)
          gc:cubicTo(
            x0 + (qx - x0) * 2 / 3,
            y0 + (qy - y0) * 2 / 3,
            x1 + (qx - x1) * 2 / 3,
            y1 + (qy - y1) * 2 / 3,
            x1,
            y1
          )
          current = finish
          i = i + 2
        end
      end
      gc:closePath()
    end
  end
  gc:fill()
  return image
end

return M
