-- Optional OpenType naming metadata. Malformed records never become executable data.
local U = require("src.core.util")
local M = {}

---Check whether a Unicode codepoint represents whitespace.
---@param cp integer Unicode scalar codepoint.
---@return boolean isSpace True if codepoint is a space separator.
local function space(cp)
  return cp == 32
    or cp == 0xa0
    or cp == 0x1680
    or (cp >= 0x2000 and cp <= 0x200a)
    or cp == 0x202f
    or cp == 0x205f
    or cp == 0x3000
end

---Normalize font naming metadata and reject invalid or oversized text.
---@param value any Candidate name.
---@return string? name Clean name, or nil if invalid.
function M.clean(value)
  if type(value) ~= "string" then
    return nil
  end
  local ok, result = pcall(function()
    local out, pending = {}, false
    for _, cp in utf8.codes(value) do
      if
        cp < 32
        or (cp >= 127 and cp <= 159)
        or cp == 0x2028
        or cp == 0x2029
        or (cp >= 0xd800 and cp <= 0xdfff)
      then
        return nil
      end
      if space(cp) then
        pending = #out > 0
      else
        if pending then
          out[#out + 1] = " "
          pending = false
        end
        out[#out + 1] = utf8.char(cp)
      end
    end
    local text = table.concat(out)
    if text == "" or utf8.len(text) > 128 then
      return nil
    end
    return text
  end)
  return ok and result or nil
end

---Derive a display name from a font path.
---@param path string? Font file path.
---@return string name Clean filename or the default font name.
function M.fallback(path)
  local name = (type(path) == "string" and path:match("[^/\\]$") and U.basename(path) or ""):gsub(
    "%.[tT][tT][fF]$",
    ""
  )
  return M.clean(name) or "Untitled Font"
end

local roman = {}
-- Mac Roman high half, in encoding order.
local chars =
  "ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø¿¡¬√ƒ≈∆«»… ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ"
for _, cp in utf8.codes(chars) do
  roman[#roman + 1] = cp
end

---Decode a name string record using Mac Roman or UTF-16BE.
---@param t table Font table reader slice.
---@param offset integer 0-based byte offset in table.
---@param length integer Byte length of record.
---@param mac boolean True to decode Mac Roman; false for UTF-16BE.
---@return string? decoded Decoded string, or nil on decoding error.
local function decode(t, offset, length, mac)
  t:at(offset, length)
  if length > 4096 then
    return nil
  end
  local out = {}
  if mac then
    for i = offset, offset + length - 1 do
      local b = t:u8(i)
      out[#out + 1] = utf8.char(b < 128 and b or roman[b - 127])
    end
  else
    if length % 2 ~= 0 then
      return nil
    end
    local i = offset
    while i < offset + length do
      local cp = t:u16(i)
      i = i + 2
      if cp >= 0xd800 and cp <= 0xdbff then
        if i >= offset + length then
          return nil
        end
        local low = t:u16(i)
        i = i + 2
        if low < 0xdc00 or low > 0xdfff then
          return nil
        end
        cp = 0x10000 + (cp - 0xd800) * 1024 + low - 0xdc00
      elseif cp >= 0xdc00 and cp <= 0xdfff then
        return nil
      end
      out[#out + 1] = utf8.char(cp)
    end
  end
  return M.clean(table.concat(out))
end

---Read display name and designer from an OpenType name table.
---@param t table? Bounded name-table reader.
---@return string? name Preferred display name.
---@return string? designer Preferred designer name.
function M.read(t)
  if not t then
    return nil
  end
  local ok, result, author = pcall(function()
    local format, count, storage = t:u16(0), t:u16(2), t:u16(4)
    if (format ~= 0 and format ~= 1) or count > 4096 then
      return nil
    end
    t:at(6, count * 12)
    local tags = {}
    if format == 1 then
      local pos = 6 + count * 12
      local n = t:u16(pos)
      t:at(pos + 2, n * 4)
      for i = 0, n - 1 do
        local success, tag =
          pcall(decode, t, storage + t:u16(pos + 4 + i * 4), t:u16(pos + 2 + i * 4), false)
        if success and tag then
          tags[0x8000 + i] = tag:lower()
        end
      end
    end
    local records = {}
    for i = 0, count - 1 do
      local p = 6 + i * 12
      local platform, encoding, language, id = t:u16(p), t:u16(p + 2), t:u16(p + 4), t:u16(p + 6)
      if
        (id == 4 or id == 16 or id == 17 or id == 1 or id == 2 or id == 9)
        and (id ~= 9 or language < 0x8000 or tags[language] ~= nil)
        and (
          (platform == 0 and encoding <= 6 and encoding ~= 5)
          or (platform == 3 and (encoding == 0 or encoding == 1 or encoding == 10))
          or (platform == 1 and encoding == 0)
        )
      then
        local success, text = pcall(decode, t, storage + t:u16(p + 10), t:u16(p + 8), platform == 1)
        if success and text then
          local tag = tags[language]
          local english = (tag and (tag == "en" or tag:match("^en%-")))
            or (platform == 3 and language < 0x8000 and language & 1023 == 9)
            or (platform == 1 and language == 0)
          local neutral = (platform == 0 or platform == 3) and language == 0
          records[#records + 1] = {
            id = id,
            text = text,
            group = platform .. ":" .. language,
            rank = (english and 0 or neutral and 100 or 200)
              + (platform == 3 and 0 or platform == 0 and 10 or 20),
            order = i,
          }
        end
      end
    end
    table.sort(records, function(a, b)
      return a.rank == b.rank and a.order < b.order or a.rank < b.rank
    end)
    local displayName, designer
    for _, r in ipairs(records) do
      if r.id == 9 then
        designer = r.text
        break
      end
    end
    for _, id in ipairs({ 4, 16, 1 }) do
      for _, r in ipairs(records) do
        if r.id == id then
          local text = r.text
          if id ~= 4 then
            for _, style in ipairs(records) do
              if style.id == id + 1 and style.group == r.group then
                if style.text:lower() ~= "regular" and style.text ~= text then
                  text = text .. " " .. style.text
                end
                break
              end
            end
          end
          local clean = M.clean(text)
          if clean then
            displayName = clean
            break
          end
        end
      end
      if displayName then
        break
      end
    end
    return displayName, designer
  end)
  if ok then
    return result, author
  end
  return nil, nil
end
return M
