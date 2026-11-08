-- Portable sfnt-v1 identity. Raw resource hashes keep their existing meaning.
local U = require("src.core.util")
local Binary = require("src.core.binary")
local M = {}

---Calculate a portable SFNT identity after validating the font directory.
---@param bytes string Standalone SFNT font data.
---@param checkpoint? fun(message: string) Cooperative progress callback.
---@return table identity Portable identity containing the sfnt-v1 identifier.
function M.identify(bytes, checkpoint)
  U.check(type(bytes) == "string" and #bytes >= 12, "INVALID_FONT: truncated SFNT header")
  U.check(#bytes <= 16 * 1024 * 1024, "LIMIT_EXCEEDED: font exceeds 16 MiB")
  local flavor, count = string.unpack(">I4I2", bytes)
  U.check(
    flavor == 0x00010000 or flavor == 0x74727565 or flavor == 0x4f54544f,
    "UNSUPPORTED_FONT: use decoded standalone TTF or OTF data"
  )
  U.check(count > 0 and count <= 256, "LIMIT_EXCEEDED: SFNT requires 1–256 tables")
  local directoryEnd = 12 + count * 16
  U.check(directoryEnd <= #bytes, "INVALID_FONT: truncated directory")
  local tables, tags, ranges, head = {}, {}, {}, nil
  for i = 1, count do
    local tag, _, offset, length = string.unpack(">c4I4I4I4", bytes, 13 + (i - 1) * 16)
    U.check(
      not tags[tag] and offset >= directoryEnd and offset + length <= #bytes,
      "INVALID_FONT: duplicate or out-of-bounds table"
    )
    tags[tag] = true
    local entry = { tag = tag, offset = offset, length = length }
    if tag ~= "DSIG" then
      tables[#tables + 1] = entry
    end
    if length > 0 then
      ranges[#ranges + 1] = entry
    end
    if tag == "head" then
      head = entry
    end
  end
  U.check(head and head.length >= 12, "INVALID_FONT: missing or truncated head table")
  table.sort(ranges, function(a, b)
    return a.offset < b.offset
  end)
  for i = 2, #ranges do
    U.check(
      ranges[i].offset >= ranges[i - 1].offset + ranges[i - 1].length,
      "INVALID_FONT: overlapping tables"
    )
  end
  table.sort(tables, function(a, b)
    return string.unpack(">I4", a.tag) < string.unpack(">I4", b.tag)
  end)
  local chunks = { "textmode.font.sfnt.v1\0", bytes:sub(1, 4), string.pack(">I2", #tables) }
  for idx, entry in ipairs(tables) do
    if checkpoint then
      checkpoint("Identifying font tables", idx / math.max(1, #tables * 2))
    end
    chunks[#chunks + 1] = entry.tag .. string.pack(">I4", entry.length)
    local data = bytes:sub(entry.offset + 1, entry.offset + entry.length)
    if entry.tag == "head" then
      data = data:sub(1, 8) .. "\0\0\0\0" .. data:sub(13)
    end
    chunks[#chunks + 1] = data
  end
  local hashCheckpoint = checkpoint
    and function(msg, frac)
      checkpoint(msg, 0.5 + 0.5 * (frac or 0))
    end
  return { id = "sfnt-v1-sha256:" .. Binary.sha256(table.concat(chunks), hashCheckpoint) }
end
return M
