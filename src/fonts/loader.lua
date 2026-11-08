local U = require("src.core.util")
local Metrics = require("src.core.metrics")
local TTF = require("src.fonts.truetype")
local Render = require("src.fonts.render")
local Resources = require("src.fonts.resources")
local Bundled = require("src.fonts.bundled")
local Names = require("src.fonts.names")
local Repertoire = require("src.fonts.repertoire")
local Identity = require("src.fonts.identity")
local M = {}

---Build a font preparation job from raw TTF font bytes.
---@param bytes string Binary font file contents.
---@param name string Display name for the font.
---@param source AsemodeFontSource Font source descriptor.
---@param hash string 8-character FNV-1a hash of bytes.
---@param options? table Optional measurement and subset options.
---@param parsed? table Optional pre-parsed font table from inspect.
---@return AsemodeFontJob job Incremental font preparation job.
local function fromBytes(bytes, name, source, hash, options, parsed)
  options = options or {}
  local font = parsed or TTF.parse(bytes)
  local glyphs = font:characters(options.characters)
  local profile = Metrics.measure(font, glyphs, options)
  profile.kind, profile.source, profile.name = "truetype", source, name
  profile.sourceHash = hash
  profile.portableFont = source.kind == "bundled" and U.copy(Resources[source.id].portableFont)
    or Identity.identify(bytes, options.checkpoint)
  profile.portableFont.name = font.displayName
  local job = M.job(profile, glyphs, function(glyph)
    return Render.mask(glyph, profile)
  end)
  job.resolveCharacters = function(keys)
    local resolved = font:characters(keys)
    for _, glyph in ipairs(resolved) do
      if glyph.renderFallback then
        glyph.advance = profile.cellWidth / profile.scale
      else
        glyph.offsetX = Metrics.offsetX(profile, glyph.advance)
      end
    end
    return resolved
  end
  return job
end

---Read and inspect a standalone font file.
---@param path string Font file path.
---@return table candidate Font bytes, parsed metadata, and source hash.
function M.inspect(path)
  local bytes = U.read(path, 16 * 1024 * 1024)
  local font = TTF.parse(bytes)
  return {
    path = path,
    bytes = bytes,
    font = font,
    extractedName = font.displayName,
    extractedAuthor = font.designer,
    name = font.displayName or Names.fallback(path),
    sourceHash = U.hash(bytes),
  }
end

---Create a font preparation job from an inspected candidate.
---@param candidate table Candidate returned by inspect.
---@param name string Font display name.
---@param options table? Font measurement and glyph options.
---@param source AsemodeFontSource? Override for the font source descriptor.
---@return AsemodeFontJob job Incremental font rendering job.
function M.candidate(candidate, name, options, source)
  return fromBytes(
    candidate.bytes,
    name,
    source or { kind = "file", path = candidate.path },
    candidate.sourceHash,
    options,
    candidate.font
  )
end

---Inspect a font file and prepare its glyph rendering job.
---@param path string Font file path.
---@param options table? Font measurement and glyph options.
---@return AsemodeFontJob job Incremental font rendering job.
function M.vector(path, options)
  local candidate = M.inspect(path)
  return M.candidate(candidate, candidate.name, options)
end

---Prepare a font job from a saved library resource.
---@param id string Saved font identifier.
---@param options table? Font measurement and glyph options.
---@param resolve function Saved resource resolver.
---@param name string Font display name.
---@param digest string Expected source digest.
---@return AsemodeFontJob job Incremental font rendering job.
function M.user(id, options, resolve, name, digest)
  U.check(
    type(resolve) == "function",
    "Saved font library is unavailable. Restore the same font or replace it."
  )
  local resource = resolve(id, digest)
  return fromBytes(
    resource.bytes,
    name,
    { kind = "user", id = id, sha256 = resource.sha256 },
    resource.sourceHash,
    options
  )
end

---Retrieve a complete bundled font resource or raise an error.
---@param id string Bundled font identifier.
---@return table resource Font bytes and resource metadata.
function M.resource(id)
  local resource = Resources[id]
  U.check(
    resource and type(resource.bytes) == "string" and #resource.bytes == resource.byteLength,
    "Font unavailable: " .. tostring(id) .. ". Obtain and upload the original font or replace it."
  )
  return resource
end

---Prepare a font job from a bundled resource.
---@param id string Bundled font identifier.
---@param options table? Font measurement and glyph options.
---@return AsemodeFontJob job Incremental font rendering job.
function M.bundled(id, options)
  local resource = M.resource(id)
  local name
  for _, font in ipairs(Bundled) do
    if font.id == id then
      name = font.name
      break
    end
  end
  U.check(name, "Unknown bundled font: " .. tostring(id))
  return fromBytes(
    resource.bytes,
    name,
    { kind = "bundled", id = id, sha256 = resource.sha256 },
    resource.sourceHash,
    options
  )
end

-- Return a reference only when the original revision is still verifiable.
---Resolve a portable identity only when the source revision is verifiable.
---@param profile AsemodeFontProfile Font profile.
---@param resolve? function Saved resource resolver.
---@param checkpoint? fun(message: string) Cooperative progress callback.
---@return table? reference Portable font identity, or nil when unavailable.
function M.reference(profile, resolve, checkpoint)
  if profile.portableFont then
    return U.copy(profile.portableFont)
  end
  local source = profile.source
  if not source then
    return nil
  end
  if source.kind == "bundled" then
    local resource = Resources[source.id]
    if resource and resource.sha256 == source.sha256 then
      return U.copy(resource.portableFont)
    end
  elseif source.kind == "user" and resolve then
    local ok, resource = pcall(resolve, source.id, source.sha256, checkpoint)
    if ok and resource and resource.sha256 == source.sha256 then
      return Identity.identify(resource.bytes, checkpoint)
    end
  end
  -- File-only legacy profiles have a non-cryptographic integrity hash. Do not
  -- infer a portable revision from that hash or from embedded glyph masks.
  return nil
end

---Recreate a font job from a verifiable stored source.
---@param profile AsemodeFontProfile Stored font profile.
---@param options table? New measurement and glyph options.
---@param resolve? function Saved resource resolver.
---@return AsemodeFontJob job Incremental font rendering job.
function M.fromProfile(profile, options, resolve)
  local source = profile.source
  U.check(
    type(source) == "table"
      and (source.kind == "bundled" or source.kind == "file" or source.kind == "user"),
    "Font source is unavailable. Replace or reimport the font before changing cell size."
  )
  if source.kind == "user" then
    U.check(
      type(source.id) == "string"
        and U.isSha256(source.sha256)
        and source.id == "user-" .. source.sha256,
      "Saved font source descriptor is invalid. Restore the same font or replace it."
    )
    return M.user(source.id, options, resolve, profile.name, source.sha256)
  end
  if source.kind == "bundled" then
    local resource = Resources[source.id]
    if not resource and resolve and type(source.sha256) == "string" then
      local userId = "user-" .. source.sha256
      local ok, restored = pcall(resolve, userId, source.sha256)
      if ok and restored then
        return M.user(userId, options, resolve, profile.name, source.sha256)
      end
    end
    resource = resource or M.resource(source.id)
    U.check(
      resource.sha256 == source.sha256,
      "Bundled font has changed. Replace or reimport the font before changing cell size."
    )
    return M.bundled(source.id, options)
  end
  U.check(
    type(source.path) == "string" and source.path ~= "",
    "Font file path is missing. Replace or reimport the font."
  )
  local bytes = U.read(source.path, 16 * 1024 * 1024)
  local hash = U.hash(bytes)
  U.check(
    hash == profile.sourceHash,
    "Font file has changed. Replace or reimport the font before changing cell size."
  )
  return fromBytes(bytes, profile.name, { kind = "file", path = source.path }, hash, options)
end

---Create a batched glyph rendering job, updating fallback advances in place.
---@param profile AsemodeFontProfile Font metrics and rendering settings.
---@param glyphs table[] Glyphs to render.
---@param render fun(glyph: table): Image Render one supported glyph.
---@return AsemodeFontJob job Incremental glyph rendering job.
function M.job(profile, glyphs, render)
  Repertoire.budget(profile, #glyphs)
  for _, glyph in ipairs(glyphs) do
    if glyph.renderFallback then
      glyph.advance = profile.cellWidth / (profile.scale or 1)
    end
  end
  local job = { profile = profile, glyphs = glyphs, masks = {}, position = 0 }
  ---Render the next batch of font masks.
  ---@param batch? integer Maximum glyphs to render; defaults to 16.
  ---@return boolean done Whether all glyphs are rendered.
  function job:step(batch)
    for i = self.position + 1, math.min(#self.glyphs, self.position + (batch or 16)) do
      self.masks[i] = self.glyphs[i].renderFallback
          and Image(profile.cellWidth, profile.cellHeight, ColorMode.RGB)
        or render(self.glyphs[i])
      self.position = i
    end
    return self.position == #self.glyphs
  end

  ---Render all remaining masks.
  ---@return AsemodeFontJob job Completed rendering job.
  function job:finish()
    while not self:step(64) do
    end
    return self
  end
  return job
end

-- Appending glyphs keeps the existing cell geometry and completed masks.
---Resolve requested characters in a font job, adding fallbacks where needed.
---@param job AsemodeFontJob Font job to update.
---@param keys string|string[] Requested characters.
---@return string[] missing Character keys that could not be resolved.
function M.ensureCharacters(job, keys)
  local available = {}
  for _, glyph in ipairs(job.glyphs) do
    available[glyph.glyphKey] = true
  end
  local requested = Repertoire.missing(available, keys)
  Repertoire.budget(job.profile, #job.glyphs + #requested)
  local missing = {}
  if #requested == 0 then
    return missing
  end
  local resolved = job.resolveCharacters and job.resolveCharacters(requested) or {}
  if not job.resolveCharacters then
    for _, key in ipairs(requested) do
      resolved[#resolved + 1] = Repertoire.fallback(key, job.profile)
    end
  end
  for _, glyph in ipairs(resolved) do
    job.glyphs[#job.glyphs + 1] = glyph
    if glyph.renderFallback then
      missing[#missing + 1] = glyph.glyphKey
    elseif Metrics.isClipped(job.profile, glyph) then
      job.profile.clippedGlyphs = job.profile.clippedGlyphs + 1
    end
  end
  return missing
end

---Parse and validate a bitmap character map.
---@param value string|table UTF-8 text, JSON, or mapping entries.
---@return string[] keys Unique character keys in sheet order.
function M.mapping(value)
  if type(value) == "string" then
    value = value:gsub("^\239\187\191", "")
    if value:match("^%s*[%[{]") then
      local decoded = U.decode(value)
      value = decoded.glyphs or decoded.map or decoded
    else
      value = U.characters(value:gsub("[\r\n]", ""))
    end
  end
  U.check(type(value) == "table" and #value > 0, "Provide a UTF-8 character map or JSON array")
  local result, seen = {}, {}
  for _, entry in ipairs(value) do
    local key = type(entry) == "table" and (entry.glyphKey or entry.character) or entry
    U.check(
      type(key) == "string" and #U.characters(key) == 1,
      "Each mapping entry must contain one Unicode character"
    )
    local cp = utf8.codepoint(key)
    U.check(
      cp >= 32 and not (cp >= 127 and cp < 160),
      "Character maps cannot contain control characters"
    )
    U.check(not seen[key], "Duplicate character in mapping: " .. key)
    seen[key] = true
    result[#result + 1] = key
  end
  return result
end

---Prepare a bitmap font job from an image sheet and character map.
---@param path string Image sheet path.
---@param mapping string|table Character map or atlas manifest.
---@param options table? Cell size, margins, spacing, and mask mode.
---@return AsemodeFontJob job Incremental bitmap rendering job.
function M.bitmap(path, mapping, options)
  options = options or {}
  local w = U.integer(options.cellWidth or 8, "Cell width", 1, 512)
  local h = U.integer(options.cellHeight or 8, "Cell height", 1, 512)
  local margin = U.integer(options.margin or 0, "Margin", 0, 1024)
  local spacing = U.integer(options.spacing or 0, "Spacing", 0, 1024)
  local sheet = Image({ fromFile = path })
  U.check(
    sheet and sheet.colorMode == ColorMode.RGB,
    "Use an RGBA PNG sheet (convert indexed sheets to RGB first)"
  )
  U.check(
    (sheet.width - margin * 2 + spacing) % (w + spacing) == 0
      and (sheet.height - margin * 2 + spacing) % (h + spacing) == 0,
    "Sheet dimensions contain partial cells"
  )
  local cols = (sheet.width - margin * 2 + spacing) // (w + spacing)
  local rows = (sheet.height - margin * 2 + spacing) // (h + spacing)
  local manifest
  if type(mapping) == "string" and mapping:match("^%s*{") then
    manifest = U.decode(mapping)
  end
  local keys = M.mapping(mapping)
  local declared = manifest
    and manifest.format == "asemode-atlas"
    and manifest.version == 1
    and manifest.glyphCount == #keys
    and manifest.columns == cols
    and manifest.rows == rows
    and manifest.cellWidth == w
    and manifest.cellHeight == h
  U.check(
    cols > 0
      and rows > 0
      and (
        #keys == cols * rows or (declared and #keys > (rows - 1) * cols and #keys <= cols * rows)
      ),
    "Character-map length must match the sheet (or an explicit Asemode final-row glyphCount)"
  )
  local glyphs = {}
  for i, key in ipairs(keys) do
    local entry = declared and manifest.glyphs and manifest.glyphs[i]
    local fallback
    if type(entry) == "table" then
      fallback = entry.renderFallback
    end
    U.check(fallback == nil or fallback == "space", "Invalid atlas fallback marker")
    glyphs[#glyphs + 1] = {
      glyphKey = key,
      codePoint = utf8.codepoint(key),
      advance = w,
      xMin = 0,
      xMax = w,
      yMin = 0,
      yMax = h,
      offsetX = 0,
      sheetIndex = i - 1,
      renderFallback = fallback,
    }
    if fallback then
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local ox, oy =
            margin + ((i - 1) % cols) * (w + spacing), margin + ((i - 1) // cols) * (h + spacing)
          U.check(
            app.pixelColor.rgbaA(sheet:getPixel(ox + x, oy + y)) == 0,
            "Atlas fallback mask must be blank"
          )
        end
      end
      glyphs[#glyphs].xMax, glyphs[#glyphs].yMax = 0, 0
    end
  end
  local profile = {
    schemaVersion = 1,
    kind = "bitmap",
    name = U.basename(path),
    sourcePath = path,
    sourceHash = U.hash(sheet.bytes),
    cellWidth = w,
    cellHeight = h,
    naturalWidth = w,
    naturalHeight = h,
    baseline = h,
    originX = 0,
    pixelSize = h,
    scale = 1,
    unitsPerEm = h,
    antialias = false,
    clippedGlyphs = 0,
    margin = margin,
    spacing = spacing,
    maskMode = options.maskMode or "alpha",
  }
  return M.withBitmap(
    { profile = profile, glyphs = glyphs },
    sheet,
    cols,
    margin,
    spacing,
    options.maskMode or "alpha"
  )
end

-- Keep bitmap rendering incremental without holding an editor cel or document open.
---Create an incremental mask-rendering job for a bitmap sheet.
---@param job table Font profile and mapped glyphs.
---@param sheet Image Source image sheet.
---@param cols integer Number of sheet columns.
---@param margin integer Sheet margin in pixels.
---@param spacing integer Spacing between cells.
---@param mode string Mask mode, including luminance or alpha.
---@return AsemodeFontJob job Incremental bitmap rendering job.
function M.withBitmap(job, sheet, cols, margin, spacing, mode)
  local profile = job.profile
  local pc = app.pixelColor
  return M.job(profile, job.glyphs, function(glyph)
    local index = glyph.sheetIndex
    local image = Image(profile.cellWidth, profile.cellHeight, ColorMode.RGB)
    local ox = margin + (index % cols) * (profile.cellWidth + spacing)
    local oy = margin + (index // cols) * (profile.cellHeight + spacing)
    for y = 0, image.height - 1 do
      for x = 0, image.width - 1 do
        local pixel = sheet:getPixel(ox + x, oy + y)
        local alpha = pc.rgbaA(pixel)
        if mode == "luminance" then
          alpha = math.floor(
            alpha
                * (pc.rgbaR(pixel) * 0.2126 + pc.rgbaG(pixel) * 0.7152 + pc.rgbaB(pixel) * 0.0722)
                / 255
              + 0.5
          )
        end
        image:drawPixel(x, y, alpha == 0 and 0 or pc.rgba(255, 255, 255, alpha))
      end
    end
    return image
  end)
end

return M
