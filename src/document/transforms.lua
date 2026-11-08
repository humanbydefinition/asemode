local U = require("src.core.util")
local M = {}
local pc = app.pixelColor
local X, Y, D = pc.TILE_XFLIP, pc.TILE_YFLIP, pc.TILE_DFLIP

---Check whether flags contain only native tile transforms.
---@param flags any Candidate flag value.
---@return boolean valid True if flags is a non-negative integer with only valid flip/diagonal bits.
function M.validFlags(flags)
  return math.type(flags) == "integer" and flags >= 0 and flags & ~(X | Y | D) == 0
end

---Convert native tile transform flags into a 2x2 coordinate transformation matrix.
---@param flags integer Native tile transform flags.
---@return table matrix 4-element transformation matrix { m11, m12, m21, m22 }.
local function matrix(flags)
  local x, y = flags & X ~= 0 and -1 or 1, flags & Y ~= 0 and -1 or 1
  return flags & D ~= 0 and { 0, y, x, 0 } or { x, 0, 0, y }
end

---Find the native transform flags that match a given 2x2 transformation matrix.
---@param m table 4-element transformation matrix.
---@return integer flags Matching native tile transform flags.
local function flagsFor(m)
  for bits = 0, 7 do
    local flags = (bits & 1 ~= 0 and X or 0)
      | (bits & 2 ~= 0 and Y or 0)
      | (bits & 4 ~= 0 and D or 0)
    local n = matrix(flags)
    if m[1] == n[1] and m[2] == n[2] and m[3] == n[3] and m[4] == n[4] then
      return flags
    end
  end
  error("Unsupported native transform")
end

---Round a rotation to the nearest supported quarter turn.
---@param rotation number Rotation in degrees.
---@return integer rotation Quarter turn in the range 0 to 270 degrees.
function M.quantizeRotation(rotation)
  rotation = ((rotation % 360) + 360) % 360
  return (math.floor((rotation + 45) / 90) % 4) * 90
end

---Convert a portable cell transform to native tile flags.
---@param transform table Portable transform; inversion is unsupported.
---@param metrics table Grid metrics reserved for compatibility.
---@return integer flags Native tile transform flags.
function M.portableToNative(transform, metrics)
  U.check(not transform.invert, "Cell inversion cannot be preserved")
  local rotation = M.quantizeRotation(transform.rotation)
  local base = ({ [0] = 0, [90] = D | X, [180] = X | Y, [270] = D | Y })[rotation]
  return base ~ (transform.flipX and X or 0) ~ (transform.flipY and Y or 0)
end

---Convert native tile flags to a portable cell transform.
---@param flags integer Native tile transform flags.
---@param metrics table Grid metrics reserved for compatibility.
---@return table transform Portable rotation and flip flags.
function M.nativeToPortable(flags, metrics)
  U.check(flags & ~(X | Y | D) == 0, "Unknown native tile transform flags")
  local diagonal = flags & D ~= 0
  return {
    invert = false,
    rotation = diagonal and 90 or 0,
    flipX = (flags & X ~= 0) ~= diagonal,
    flipY = flags & Y ~= 0,
  }
end

---Render a transformed copy of a glyph mask within its original dimensions.
---@param mask Image Source mask.
---@param flags integer Native tile transform flags.
---@param checkpoint? fun() Cooperative callback invoked per row.
---@return Image image Transformed mask.
function M.renderMask(mask, flags, checkpoint)
  local w, h = mask.width, mask.height
  local output = Image(w, h, ColorMode.RGB)
  local diagonal = flags & D ~= 0
  local ox, oy = (w - h) // 2, (h - w) // 2
  for y = 0, h - 1 do
    if checkpoint then
      checkpoint()
    end
    for x = 0, w - 1 do
      local dx = flags & X ~= 0 and w - 1 - x or x
      local dy = flags & Y ~= 0 and h - 1 - y or y
      local sx, sy = dx, dy
      if diagonal then
        sx, sy = dy - oy, dx - ox
      end
      if sx >= 0 and sx < w and sy >= 0 and sy < h then
        output:drawPixel(x, y, mask:getPixel(sx, sy))
      end
    end
  end
  return output
end

---Compose native tile flags with one quarter turn.
---@param flags integer Native tile transform flags.
---@param clockwise boolean Rotate clockwise when true.
---@return integer flags Composed native transform flags.
function M.rotate(flags, clockwise)
  -- Compose inverse sampling matrices: native flags sample D * F.
  local a, b = matrix(flags), matrix(clockwise and (D | X) or (D | Y))
  return flagsFor({
    a[1] * b[1] + a[2] * b[3],
    a[1] * b[2] + a[2] * b[4],
    a[3] * b[1] + a[4] * b[3],
    a[3] * b[2] + a[4] * b[4],
  })
end

return M
