-- Bounded TrueType outline reader. Font concepts follow OpenType and textmode.js;
-- this implementation adds composite expansion and table-local bounds checks.
local U = require("src.core.util")
local Names = require("src.fonts.names")
local Repertoire = require("src.fonts.repertoire")
local M = {}

---Create a bounded binary buffer reader.
---@param data string Binary data string.
---@param start? integer 0-based starting offset in data.
---@param length? integer Length of this reader slice in bytes.
---@return table reader Reader with bounds checks and unpack helpers.
local function reader(data, start, length)
  local r = { data = data, start = start or 0, length = length or #data }

  ---Compute 1-based string index and verify bounds.
  ---@param offset integer 0-based offset within slice.
  ---@param count integer Number of bytes to read.
  ---@return integer index 1-based byte index.
  function r:at(offset, count)
    U.check(offset >= 0 and count >= 0 and offset + count <= self.length, "Truncated font table")
    return self.start + offset + 1
  end

  ---Read an unsigned 8-bit integer.
  ---@param o integer 0-based offset.
  ---@return integer byte Value (0-255).
  function r:u8(o)
    return self.data:byte(self:at(o, 1))
  end

  ---Read a signed 8-bit integer.
  ---@param o integer 0-based offset.
  ---@return integer byte Signed value (-128 to 127).
  function r:i8(o)
    local n = self:u8(o)
    return n >= 128 and n - 256 or n
  end

  ---Read an unsigned big-endian 16-bit integer.
  ---@param o integer 0-based offset.
  ---@return integer word Value (0-65535).
  function r:u16(o)
    return string.unpack(">I2", self.data, self:at(o, 2))
  end

  ---Read a signed big-endian 16-bit integer.
  ---@param o integer 0-based offset.
  ---@return integer word Signed value (-32768 to 32767).
  function r:i16(o)
    return string.unpack(">i2", self.data, self:at(o, 2))
  end

  ---Read an unsigned big-endian 32-bit integer.
  ---@param o integer 0-based offset.
  ---@return integer dword 32-bit integer.
  function r:u32(o)
    return string.unpack(">I4", self.data, self:at(o, 4))
  end

  ---Create a sub-reader for a nested table slice.
  ---@param o integer 0-based offset.
  ---@param n integer Slice length in bytes.
  ---@return table slice Child reader for the slice.
  function r:sub(o, n)
    self:at(o, n)
    return reader(self.data, self.start + o, n)
  end

  return r
end

---Check whether a bit flag is set.
---@param n integer Bit field.
---@param mask integer Bit mask.
---@return boolean set True if any bit in mask is set.
local function bit(n, mask)
  return (n & mask) ~= 0
end

---Parse and validate a TrueType font from binary data.
---@param data string Font file bytes.
---@return table font Parsed font metrics and glyph accessors.
function M.parse(data)
  U.check(type(data) == "string" and #data <= 16 * 1024 * 1024, "Font exceeds the 16 MiB limit")
  local root = reader(data)
  local signature = data:sub(1, 4)
  U.check(
    signature == "\0\1\0\0" or signature == "true",
    "Use a static TrueType (.ttf) font. CFF, WOFF, collections, and color fonts are not supported."
  )
  local count = root:u16(4)
  U.check(count > 0 and count <= 256, "Invalid SFNT table count")
  local tables = {}
  for i = 0, count - 1 do
    local pos = 12 + 16 * i
    local tag = data:sub(root:at(pos, 4), root:at(pos, 4) + 3)
    U.check(not tables[tag], "Duplicate font table: " .. tag)
    tables[tag] = root:sub(root:u32(pos + 8), root:u32(pos + 12))
  end
  for _, tag in ipairs({ "fvar", "CFF ", "CFF2", "COLR", "CBDT", "sbix", "SVG " }) do
    U.check(
      not tables[tag],
      "Unsupported font table: " .. tag .. "; use a static monochrome TrueType font"
    )
  end
  for _, tag in ipairs({ "head", "maxp", "hhea", "hmtx", "loca", "glyf", "cmap" }) do
    U.check(tables[tag], "Missing font table: " .. tag)
  end
  local head, maxp, hhea = tables.head, tables.maxp, tables.hhea
  local displayName, designer = Names.read(tables.name)
  local font = {
    displayName = displayName,
    designer = designer,
    unitsPerEm = head:u16(18),
    ascender = hhea:i16(4),
    descender = hhea:i16(6),
    lineGap = hhea:i16(8),
    maxAdvance = hhea:u16(10),
    glyphCount = maxp:u16(4),
    tables = tables,
    glyphCache = {},
  }
  U.check(font.unitsPerEm > 0 and font.glyphCount > 0, "Invalid font dimensions")
  local metricsCount, locaFormat = hhea:u16(34), head:i16(50)
  U.check(metricsCount > 0 and metricsCount <= font.glyphCount, "Invalid horizontal metrics count")
  U.check(locaFormat == 0 or locaFormat == 1, "Invalid loca format")
  local offsets, advances = {}, {}
  for i = 0, font.glyphCount do
    offsets[i] = locaFormat == 0 and tables.loca:u16(i * 2) * 2 or tables.loca:u32(i * 4)
    U.check(
      offsets[i] <= tables.glyf.length and (i == 0 or offsets[i] >= offsets[i - 1]),
      "Invalid glyph offsets"
    )
  end
  for i = 0, font.glyphCount - 1 do
    advances[i] = tables.hmtx:u16(math.min(i, metricsCount - 1) * 4)
    if i >= metricsCount then
      tables.hmtx:i16(metricsCount * 4 + (i - metricsCount) * 2)
    end
  end

  local cmap, subtables = tables.cmap, {}
  for i = 0, cmap:u16(2) - 1 do
    local pos = 4 + i * 8
    local platform, encoding, offset = cmap:u16(pos), cmap:u16(pos + 2), cmap:u32(pos + 4)
    local format = cmap:u16(offset)
    if
      (platform == 0 or (platform == 3 and (encoding == 1 or encoding == 10)))
      and (format == 4 or format == 12)
    then
      local length = format == 12 and cmap:u32(offset + 4) or cmap:u16(offset + 2)
      subtables[#subtables + 1] = {
        table = cmap:sub(offset, length),
        format = format,
        rank = (format == 12 and 100 or 0) + (platform == 0 and 10 or 0),
      }
    end
  end
  table.sort(subtables, function(a, b)
    return a.rank > b.rank
  end)
  U.check(#subtables > 0, "Font has no supported Unicode cmap (format 4 or 12)")
  font.mapping = {}

  ---Add a codepoint-to-glyph mapping if valid and not already mapped.
  ---@param cp integer Unicode scalar codepoint.
  ---@param gid integer Glyph ID in font.
  local function add(cp, gid)
    if
      cp <= 0x10ffff
      and (cp < 0xd800 or cp > 0xdfff)
      and gid > 0
      and gid < font.glyphCount
      and not font.mapping[cp]
    then
      font.mapping[cp] = gid
    end
  end
  for _, record in ipairs(subtables) do
    local t = record.table
    if record.format == 12 then
      local groups = t:u32(12)
      U.check(groups <= 100000, "Too many cmap groups")
      local last = -1
      for i = 0, groups - 1 do
        local pos = 16 + i * 12
        local first, finish, gid = t:u32(pos), t:u32(pos + 4), t:u32(pos + 8)
        U.check(first <= finish and first > last and finish <= 0x10ffff, "Invalid cmap range")
        for cp = first, finish do
          add(cp, gid + cp - first)
        end
        last = finish
      end
    else
      local segments = t:u16(6) // 2
      U.check(segments > 0 and segments <= 32767, "Invalid cmap segments")
      local ends, starts = 14, 16 + 2 * segments
      local deltas, ranges = 16 + 4 * segments, 16 + 6 * segments
      local last = -1
      for i = 0, segments - 1 do
        local first, finish = t:u16(starts + 2 * i), t:u16(ends + 2 * i)
        U.check(first <= finish and first > last, "Invalid or overlapping cmap segment")
        last = finish
        local delta, range = t:i16(deltas + 2 * i), t:u16(ranges + 2 * i)
        for cp = first, math.min(finish, 0xfffe) do
          local gid
          if range == 0 then
            gid = (cp + delta) & 0xffff
          else
            gid = t:u16(ranges + 2 * i + range + 2 * (cp - first))
            if gid ~= 0 then
              gid = (gid + delta) & 0xffff
            end
          end
          add(cp, gid)
        end
      end
    end
  end

  local active = {}

  ---Extract and cache the vector outline for a glyph ID.
  ---@param gid integer Glyph ID to extract.
  ---@param depth? integer Composite recursion depth.
  ---@return table outline Glyph metrics, bounding box, and contours.
  function font:outline(gid, depth)
    depth = depth or 0
    U.check(gid >= 0 and gid < self.glyphCount, "Invalid component glyph reference")
    U.check(depth <= 32 and not active[gid], "Cyclic or deeply nested composite glyph")
    if self.glyphCache[gid] then
      return self.glyphCache[gid]
    end
    active[gid] = true
    local g = {
      glyphIndex = gid,
      advance = advances[gid],
      contours = {},
      points = {},
      xMin = 0,
      xMax = 0,
      yMin = 0,
      yMax = 0,
    }
    if offsets[gid] ~= offsets[gid + 1] then
      local t = tables.glyf:sub(offsets[gid], offsets[gid + 1] - offsets[gid])
      local n = t:i16(0)
      g.xMin, g.yMin, g.xMax, g.yMax = t:i16(2), t:i16(4), t:i16(6), t:i16(8)
      if n >= 0 then
        U.check(n <= 4096, "Too many glyph contours")
        if n > 0 then
          local ends = {}
          for i = 0, n - 1 do
            ends[i + 1] = t:u16(10 + 2 * i)
            U.check(i == 0 or ends[i + 1] > ends[i], "Invalid contour endpoints")
          end
          local pointCount = ends[n] + 1
          local p = 10 + n * 2
          local instructions = t:u16(p)
          p = p + 2
          t:at(p, instructions)
          p = p + instructions
          local flags = {}
          while #flags < pointCount do
            local flag = t:u8(p)
            p = p + 1
            local repeats = 0
            if bit(flag, 8) then
              repeats = t:u8(p)
              p = p + 1
            end
            U.check(#flags + repeats + 1 <= pointCount, "Invalid repeated glyph flags")
            for _ = 0, repeats do
              flags[#flags + 1] = flag
            end
          end
          local xs, ys, value = {}, {}, 0
          for i, flag in ipairs(flags) do
            local d = 0
            if bit(flag, 2) then
              d = t:u8(p) * (bit(flag, 16) and 1 or -1)
              p = p + 1
            elseif not bit(flag, 16) then
              d = t:i16(p)
              p = p + 2
            end
            value = value + d
            xs[i] = value
          end
          value = 0
          for i, flag in ipairs(flags) do
            local d = 0
            if bit(flag, 4) then
              d = t:u8(p) * (bit(flag, 32) and 1 or -1)
              p = p + 1
            elseif not bit(flag, 32) then
              d = t:i16(p)
              p = p + 2
            end
            value = value + d
            ys[i] = value
          end
          local first = 1
          for _, finish in ipairs(ends) do
            local contour = {}
            for i = first, finish + 1 do
              local pt = { x = xs[i], y = ys[i], on = bit(flags[i], 1) }
              contour[#contour + 1] = pt
              g.points[#g.points + 1] = pt
            end
            g.contours[#g.contours + 1] = contour
            first = finish + 2
          end
        end
      else
        local p, components, flags = 10, 0, 0
        repeat
          components = components + 1
          U.check(components <= 4096, "Too many composite components")
          flags = t:u16(p)
          local childId = t:u16(p + 2)
          p = p + 4
          local words, xy = bit(flags, 1), bit(flags, 2)
          local a, b
          if words then
            a = xy and t:i16(p) or t:u16(p)
            b = xy and t:i16(p + 2) or t:u16(p + 2)
            p = p + 4
          else
            a = xy and t:i8(p) or t:u8(p)
            b = xy and t:i8(p + 1) or t:u8(p + 1)
            p = p + 2
          end
          local xx, xyM, yx, yy = 1, 0, 0, 1
          if bit(flags, 8) then
            xx = t:i16(p) / 16384
            yy = xx
            p = p + 2
          elseif bit(flags, 64) then
            xx = t:i16(p) / 16384
            yy = t:i16(p + 2) / 16384
            p = p + 4
          elseif bit(flags, 128) then
            xx, yx, xyM, yy =
              t:i16(p) / 16384, t:i16(p + 2) / 16384, t:i16(p + 4) / 16384, t:i16(p + 6) / 16384
            p = p + 8
          end
          U.check(
            not (bit(flags, 0x800) and bit(flags, 0x1000)),
            "Conflicting composite offset flags"
          )
          local child = self:outline(childId, depth + 1)
          local dx, dy = a, b
          if xy then
            if bit(flags, 0x800) then
              dx, dy = xx * a + xyM * b, yx * a + yy * b
            end
            if bit(flags, 4) then
              dx, dy = math.floor(dx + 0.5), math.floor(dy + 0.5)
            end
          else
            local parentPoint, childPoint = g.points[a + 1], child.points[b + 1]
            U.check(parentPoint and childPoint, "Invalid composite point attachment")
            dx = parentPoint.x - (xx * childPoint.x + xyM * childPoint.y)
            dy = parentPoint.y - (yx * childPoint.x + yy * childPoint.y)
          end
          for _, contour in ipairs(child.contours) do
            local transformed = {}
            for _, pt in ipairs(contour) do
              local point =
                { x = xx * pt.x + xyM * pt.y + dx, y = yx * pt.x + yy * pt.y + dy, on = pt.on }
              transformed[#transformed + 1] = point
              g.points[#g.points + 1] = point
            end
            g.contours[#g.contours + 1] = transformed
          end
          U.check(#g.points <= 100000, "Composite outline exceeds the point limit")
          if bit(flags, 0x200) then
            g.advance = child.advance
          end
        until not bit(flags, 32)
        if bit(flags, 256) then
          local length = t:u16(p)
          t:at(p + 2, length)
        end
      end
      -- Use expanded points for composites; control-point bounds safely contain curves.
      if #g.points > 0 then
        g.xMin, g.xMax, g.yMin, g.yMax = math.huge, -math.huge, math.huge, -math.huge
        for _, pt in ipairs(g.points) do
          g.xMin, g.xMax = math.min(g.xMin, pt.x), math.max(g.xMax, pt.x)
          g.yMin, g.yMax = math.min(g.yMin, pt.y), math.max(g.yMax, pt.y)
        end
      end
    end
    active[gid] = nil
    self.glyphCache[gid] = g
    return g
  end

  ---Resolve font glyphs for a character subset or the full supported repertoire.
  ---@param subset? string Optional UTF-8 string of characters to extract.
  ---@return table[] glyphs Resolved glyph records.
  function font:characters(subset)
    local cps = {}
    if subset and subset ~= "" then
      local seen = {}
      for _, key in ipairs(Repertoire.keys(subset)) do
        local cp = utf8.codepoint(key)
        if not seen[cp] then
          cps[#cps + 1] = cp
          seen[cp] = true
        end
      end
    else
      for cp in pairs(self.mapping) do
        if cp >= 32 and not (cp >= 127 and cp < 160) then
          cps[#cps + 1] = cp
        end
      end
      table.sort(cps)
    end
    U.check(#cps > 0 and #cps <= 16384, "Font has too many supported characters (maximum 16384)")
    local glyphs, missing = {}, {}
    for _, cp in ipairs(cps) do
      if not self.mapping[cp] then
        missing[#missing + 1] = cp
      else
        local outline = self:outline(self.mapping[cp])
        local glyph = {}
        for k, v in pairs(outline) do
          glyph[k] = v
        end
        glyph.glyphKey = utf8.char(cp)
        glyph.codePoint = cp
        glyphs[#glyphs + 1] = glyph
      end
    end
    table.sort(missing)
    for _, cp in ipairs(missing) do
      glyphs[#glyphs + 1] = Repertoire.fallback(utf8.char(cp))
    end
    return glyphs
  end
  return font
end

return M
