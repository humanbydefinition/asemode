local U = require("src.core.util")
local M = {}

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local inverse = {}

for i = 1, 64 do
  inverse[alphabet:sub(i, i)] = i - 1
end

---Encode binary data as Base64.
---@param bytes string Binary input.
---@return string encoded Base64 text.
function M.encode(bytes)
  local out, chunks = {}, {}
  for i = 1, #bytes, 3 do
    local a, b, c = bytes:byte(i, i + 2)
    local n = (a << 16) | ((b or 0) << 8) | (c or 0)
    out[#out + 1] = alphabet:sub((n >> 18) + 1, (n >> 18) + 1)
      .. alphabet:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
      .. (b and alphabet:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1) or "=")
      .. (c and alphabet:sub((n & 63) + 1, (n & 63) + 1) or "=")
    if #out == 1024 then
      chunks[#chunks + 1] = table.concat(out)
      out = {}
    end
  end
  chunks[#chunks + 1] = table.concat(out)
  return table.concat(chunks)
end

---Decode Base64 and reject invalid padding or output above the byte limit.
---@param text string Base64 input.
---@param limit integer Maximum decoded byte count.
---@param checkpoint? fun(message: string) Optional cooperative checkpoint.
---@return string bytes Decoded binary data.
function M.decode(text, limit, checkpoint)
  U.check(
    type(text) == "string" and #text % 4 == 0 and #text <= 4 * ((limit + 2) // 3),
    "Invalid or oversized Base64 resource"
  )
  local out, chunks = {}, {}
  for i = 1, #text, 4 do
    if checkpoint and (i - 1) % 65536 == 0 then
      checkpoint("Reading saved font data", (i - 1) / math.max(1, #text))
    end
    local a, b, c, d =
      text:sub(i, i), text:sub(i + 1, i + 1), text:sub(i + 2, i + 2), text:sub(i + 3, i + 3)
    local aa, bb, cc, dd = inverse[a], inverse[b], inverse[c], inverse[d]
    U.check(
      aa
        and bb
        and (cc or c == "=")
        and (dd or d == "=")
        and (c ~= "=" or d == "=")
        and (i == #text - 3 or (c ~= "=" and d ~= "=")),
      "Invalid Base64 resource"
    )
    U.check(
      (c ~= "=" or bb % 16 == 0) and (d ~= "=" or c == "=" or cc % 4 == 0),
      "Invalid Base64 padding"
    )
    local n = (aa << 18) | (bb << 12) | ((cc or 0) << 6) | (dd or 0)
    out[#out + 1] = string.char((n >> 16) & 255)
      .. (cc and string.char((n >> 8) & 255) or "")
      .. (dd and string.char(n & 255) or "")
    if #out == 1024 then
      chunks[#chunks + 1] = table.concat(out)
      out = {}
    end
  end
  chunks[#chunks + 1] = table.concat(out)
  local bytes = table.concat(chunks)
  U.check(#bytes <= limit, "Decoded resource exceeds limit")

  return bytes
end

local K = {
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
}

---Rotate a 32-bit unsigned integer right by a given bit count.
---@param n integer 32-bit word.
---@param b integer Bit rotation count (1 to 31).
---@return integer rotated Rotated 32-bit word.
local function rr(n, b)
  return ((n >> b) | (n << (32 - b))) & 0xffffffff
end

---Calculate the SHA-256 digest of binary data.
---@param bytes string Binary input.
---@param checkpoint? fun(message: string, fraction?: number) Optional cooperative checkpoint.
---@return string digest Lowercase hexadecimal digest.
function M.sha256(bytes, checkpoint)
  local h = {
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  }
  local tail = "\128" .. string.rep("\0", (55 - #bytes) % 64) .. string.pack(">I8", #bytes * 8)
  local length = #bytes + #tail

  for offset = 1, length, 64 do
    if checkpoint and (offset - 1) % 65536 == 0 then
      checkpoint("Identifying font data", (offset - 1) / math.max(1, length))
    end

    local block = offset + 63 <= #bytes and bytes:sub(offset, offset + 63)
      or (bytes:sub(offset) .. tail):sub(1, 64)
    if offset > #bytes then
      block = tail:sub(offset - #bytes, offset - #bytes + 63)
    end

    local w = {}
    for i = 1, 16 do
      w[i] = string.unpack(">I4", block, (i - 1) * 4 + 1)
    end
    for i = 17, 64 do
      local a, b = w[i - 15], w[i - 2]
      w[i] = (
        w[i - 16]
        + (rr(a, 7) ~ rr(a, 18) ~ (a >> 3))
        + w[i - 7]
        + (rr(b, 17) ~ rr(b, 19) ~ (b >> 10))
      ) & 0xffffffff
    end

    local a, b, c, d, e, f, g, v = table.unpack(h)
    for i = 1, 64 do
      local t = (v + (rr(e, 6) ~ rr(e, 11) ~ rr(e, 25)) + ((e & f) ~ (~e & g)) + K[i] + w[i])
        & 0xffffffff
      local t2 = ((rr(a, 2) ~ rr(a, 13) ~ rr(a, 22)) + ((a & b) ~ (a & c) ~ (b & c))) & 0xffffffff
      v, g, f, e, d, c, b, a = g, f, e, (d + t) & 0xffffffff, c, b, a, (t + t2) & 0xffffffff
    end

    for i, n in ipairs({ a, b, c, d, e, f, g, v }) do
      h[i] = (h[i] + n) & 0xffffffff
    end
  end

  local out = {}
  for i, n in ipairs(h) do
    out[i] = string.format("%08x", n)
  end

  return table.concat(out)
end

return M
