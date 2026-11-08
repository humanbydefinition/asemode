local U = require("src.core.util")
local Repertoire = require("src.fonts.repertoire")
local Base = require("src.document.base")
local Transforms = require("src.document.transforms")
local M = {}
local pc = app.pixelColor
local cached

---Choose readable primary and secondary glyphs from a profile or font job.
---@param indexOrGlyphs table Stored font profile index or list of glyph records.
---@param includeMissingSecond? boolean Whether to fall back to missing second glyph.
---@return string primary Selected primary glyph key.
---@return string secondary Selected secondary glyph key.
function M.defaultStamps(indexOrGlyphs, includeMissingSecond)
  local available, supported, all = {}, {}, {}
  if indexOrGlyphs.glyphs then
    local index = indexOrGlyphs
    supported, all = index.supportedOrder or {}, index.order or {}
    for _, key in ipairs({ "0", "1" }) do
      local entry = index.glyphs[key]
      available[key] = entry and entry.meta and not entry.meta.renderFallback
    end
  else
    for _, glyph in ipairs(indexOrGlyphs) do
      all[#all + 1] = glyph.glyphKey
      if not glyph.renderFallback then
        available[glyph.glyphKey] = true
        supported[#supported + 1] = glyph.glyphKey
      end
    end
  end
  local primary = available["0"] and "0" or supported[1] or all[1]
  local secondary = available["1"] and "1"
    or supported[2]
    or (includeMissingSecond and all[2])
    or primary
  return primary, secondary
end

---Discard the cached font profile index.
function M.invalidate()
  cached = nil
end

---List stored font profiles and their mask tilesets.
---@param sprite Sprite Document to inspect.
---@return table[] profiles Stored profile records.
function M.profiles(sprite)
  local result = {}
  for _, ts in ipairs(sprite.tilesets) do
    local meta = Base.meta(ts)
    if meta.schemaVersion == 1 and meta.role == "masks" then
      local ok, profile = pcall(U.decode, meta.profileJson or "")
      if ok and type(profile) == "table" then
        result[#result + 1] = { id = meta.fontProfileId, profile = profile, masks = ts }
      end
    end
  end
  return result
end

---Build shared metadata for a rendered paint tile.
---@param id string Font profile identifier.
---@param glyph string Glyph key character.
---@param fg string Hexadecimal foreground color in #rrggbbaa format.
---@param bg string Hexadecimal background color in #rrggbbaa format.
---@param orientation? integer Native tile orientation flags.
---@param image Image Rendered tile image.
---@return table metadata Metadata record for the paint tile.
function M.paintMeta(id, glyph, fg, bg, orientation, image)
  return {
    schemaVersion = orientation and orientation ~= 0 and 2 or 1,
    fontProfileId = id,
    glyphKey = glyph,
    foregroundRGBA = fg,
    backgroundRGBA = bg,
    orientation = orientation,
    imageHash = U.hash(image.bytes),
  }
end

---Check tile-count and memory limits before adding a paint variant.
---@param count integer Current variant tile count.
---@param cellWidth integer Cell width in pixels.
---@param cellHeight integer Cell height in pixels.
---@return boolean countOk Whether the count is below 65,535 tiles.
---@return boolean bytesOk Whether total memory is below 128 MiB.
function M.checkVariantBudget(count, cellWidth, cellHeight)
  return count < 65535, (count + 1) * cellWidth * cellHeight * 4 < 128 * 1024 * 1024
end

---Bind a text layer to a font profile and its paint tileset.
---@param layer Layer Target text layer.
---@param targetId string Font profile identifier.
---@param targetIndex table Font profile index containing the paint tileset.
function M.bindLayer(layer, targetId, targetIndex)
  layer.tileset = targetIndex.paint
  local metadata = Base.meta(layer)
  metadata.fontProfileId = targetId
  Base.setMeta(layer, metadata)
end

---Build or reuse the glyph and paint-variant index for a profile.
---@param sprite Sprite Document containing the profile.
---@param profileId string Font profile identifier.
---@return table index Cached font profile index.
function M.index(sprite, profileId)
  if cached and cached.sprite == sprite and cached.id == profileId then
    return cached
  end
  local result = {
    sprite = sprite,
    id = profileId,
    glyphs = {},
    variants = {},
    order = {},
    supportedOrder = {},
    missingOrder = {},
  }
  for _, ts in ipairs(sprite.tilesets) do
    local meta = Base.meta(ts)
    if meta.schemaVersion == 1 and meta.fontProfileId == profileId then
      if meta.role == "masks" then
        result.masks = ts
        result.profile = U.decode(meta.profileJson)
        for i = 1, #ts - 1 do
          local tile = ts:tile(i)
          local gm = Base.meta(tile)
          if gm.glyphKey then
            result.glyphs[gm.glyphKey] = { tile = tile, meta = gm }
            result.order[#result.order + 1] = gm.glyphKey
            local order = gm.renderFallback == "space" and result.missingOrder
              or result.supportedOrder
            order[#order + 1] = gm.glyphKey
          end
        end
      elseif meta.role == "paint" then
        result.paint = ts
        for i = 1, #ts - 1 do
          local v = Base.meta(ts:tile(i))
          if v.glyphKey and v.foregroundRGBA and v.backgroundRGBA then
            result.variants[U.key(
              v.glyphKey,
              v.foregroundRGBA,
              v.backgroundRGBA,
              v.orientation or 0
            )] =
              i
          end
        end
      end
    end
  end
  U.check(
    result.masks and result.paint and result.profile,
    "Font data is incomplete. Try undoing recent edits or restoring an earlier .aseprite file."
  )
  table.sort(result.missingOrder, function(a, b)
    return utf8.codepoint(a) < utf8.codepoint(b)
  end)
  cached = result
  return result
end

---Install a completed font job and optional paint variants in the document.
---@param sprite Sprite Destination document.
---@param job AsemodeFontJob Completed font job.
---@param allowClipping boolean Whether clipped glyphs are approved.
---@param variants? table[] Prepared paint variants.
---@return string id New profile identifier.
function M.install(sprite, job, allowClipping, variants)
  local geometry = Base.geometry(sprite)
  U.check(job.position == #job.glyphs, "Font import is not complete")
  U.check(
    job.profile.cellWidth == geometry.cellWidth and job.profile.cellHeight == geometry.cellHeight,
    "Font cell size differs from the document. Fit it to the document grid or use Regrid."
  )
  U.check(
    job.profile.clippedGlyphs == 0 or allowClipping,
    "Glyphs would be clipped; confirm clipping in the preview"
  )
  local id = tostring(Uuid())
  app.transaction("Import Asemode Font", function()
    local profile = U.copy(job.profile)
    profile.id = id
    local masks =
      sprite:newTileset(Grid({ 0, 0, geometry.cellWidth, geometry.cellHeight }), #job.glyphs + 1)
    masks.name = "Asemode masks: " .. profile.name
    Base.setMeta(
      masks,
      { schemaVersion = 1, fontProfileId = id, role = "masks", profileJson = json.encode(profile) }
    )
    for i, glyph in ipairs(job.glyphs) do
      local tile = masks:tile(i)
      tile.image = job.masks[i]
      Base.setMeta(tile, Repertoire.metadata(glyph, tile.image))
    end
    local paint = sprite:newTileset(
      Grid({ 0, 0, geometry.cellWidth, geometry.cellHeight }),
      1 + #(variants or {})
    )
    paint.name = "Asemode paint: " .. profile.name
    Base.setMeta(paint, { schemaVersion = 1, fontProfileId = id, role = "paint" })
    for i, variant in ipairs(variants or {}) do
      local tile = paint:tile(i)
      tile.image = variant.image
      Base.setMeta(
        tile,
        M.paintMeta(
          id,
          variant.glyphKey,
          variant.foregroundRGBA,
          variant.backgroundRGBA,
          variant.orientation,
          tile.image
        )
      )
    end
  end)
  M.invalidate()
  return id
end

---Composite foreground and background colors through a glyph mask.
---@param mask Image Glyph alpha mask.
---@param fg string Foreground RGBA color.
---@param bg string Background RGBA color.
---@param checkpoint? fun() Cooperative callback invoked per row.
---@return Image image Colorized glyph image.
function M.colorize(mask, fg, bg, checkpoint)
  local fr, fgc, fb, fa = U.rgba(fg)
  local br, bgc, bb, ba = U.rgba(bg)
  local image = Image(mask.width, mask.height, ColorMode.RGB)
  for y = 0, image.height - 1 do
    if checkpoint then
      checkpoint()
    end
    for x = 0, image.width - 1 do
      local coverage = pc.rgbaA(mask:getPixel(x, y)) / 255
      local alpha = coverage * fa / 255
      local bgAlpha = ba / 255 * (1 - alpha)
      local outAlpha = alpha + bgAlpha
      ---Blend single color channel components with alpha coverage.
      ---@param f integer Foreground color channel value (0-255).
      ---@param b integer Background color channel value (0-255).
      ---@return integer blended Blended channel value.
      local function channel(f, b)
        return outAlpha == 0 and 0 or math.floor((f * alpha + b * bgAlpha) / outAlpha + 0.5)
      end
      image:drawPixel(
        x,
        y,
        pc.rgba(
          channel(fr, br),
          channel(fgc, bgc),
          channel(fb, bb),
          math.floor(outAlpha * 255 + 0.5)
        )
      )
    end
  end
  return image
end

-- Explicit new character requests may extend a profile; broken stored references may not.
---Add fallback masks for requested characters missing from a profile.
---@param sprite Sprite Document containing the profile.
---@param id string Font profile identifier.
---@param keys string|string[] Requested characters.
---@return string[] missing Added fallback character keys.
function M.ensureCharacters(sprite, id, keys)
  local index = M.index(sprite, id)
  local missing = Repertoire.missing(index.glyphs, keys)
  Repertoire.budget(index.profile, #index.order + #missing)
  if #missing == 0 then
    return missing
  end
  local wanted = {}
  for _, key in ipairs(missing) do
    wanted[key] = true
  end
  for i = 1, #index.paint - 1 do
    U.check(
      not wanted[Base.meta(index.paint:tile(i)).glyphKey],
      "A stored tile has no matching glyph. Try undoing recent edits or restoring an earlier .aseprite file."
    )
  end
  app.transaction("Prepare Missing Asemode Characters", function()
    for _, key in ipairs(missing) do
      local glyph = Repertoire.fallback(key, index.profile)
      local tile = sprite:newTile(index.masks)
      tile.image = Image(index.profile.cellWidth, index.profile.cellHeight, ColorMode.RGB)
      Base.setMeta(tile, Repertoire.metadata(glyph, tile.image))
    end
  end)
  M.invalidate()
  return missing
end

---Find or create a colorized glyph variant in the profile paint tileset.
---@param sprite Sprite Document containing the profile.
---@param id string Font profile identifier.
---@param glyph string Unicode character.
---@param fg string Foreground RGBA color.
---@param bg string Background RGBA color.
---@param orientation? integer Baked transform flags.
---@return integer index Paint tile index.
function M.variant(sprite, id, glyph, fg, bg, orientation)
  orientation = orientation or 0
  local index = M.index(sprite, id)
  Repertoire.scalar(glyph)
  local source = index.glyphs[glyph]
  if not source then
    local result
    app.transaction("Prepare Asemode Stamp", function()
      M.ensureCharacters(sprite, id, { glyph })
      result = M.variant(sprite, id, glyph, fg, bg, orientation)
    end)
    return result
  end
  if Base.meta(source.tile).glyphKey ~= glyph then
    M.invalidate()
    return M.variant(sprite, id, glyph, fg, bg, orientation)
  end
  U.check(
    source.meta.imageHash == U.hash(source.tile.image.bytes),
    "Canonical glyph was edited. Restore the font before creating variants."
  )
  local key = U.key(glyph, fg, bg, orientation)
  if index.variants[key] then
    local candidate = index.paint:tile(index.variants[key])
    local meta = candidate and Base.meta(candidate)
    if
      not meta
      or meta.glyphKey ~= glyph
      or meta.foregroundRGBA ~= fg
      or meta.backgroundRGBA ~= bg
      or (meta.orientation or 0) ~= orientation
    then
      M.invalidate()
      return M.variant(sprite, id, glyph, fg, bg, orientation)
    end
    U.check(
      meta.imageHash == U.hash(candidate.image.bytes),
      "Selected tile was edited. Try undoing the pixel edit or restoring an earlier .aseprite file."
    )
    return index.variants[key]
  end
  local countOk, bytesOk =
    M.checkVariantBudget(#index.paint - 1, index.profile.cellWidth, index.profile.cellHeight)
  U.check(countOk, "Font has 65535 color variants; use a new font profile")
  U.check(bytesOk, "Paint tiles exceed 128 MiB; use a smaller cell size or fewer colors")
  local mask = orientation ~= 0 and Transforms.renderMask(source.tile.image, orientation)
    or source.tile.image
  local image = M.colorize(mask, fg, bg)
  local tile
  app.transaction("Prepare Asemode Stamp", function()
    tile = sprite:newTile(index.paint)
    tile.image = image
    Base.setMeta(
      tile,
      M.paintMeta(id, glyph, fg, bg, orientation ~= 0 and orientation or nil, tile.image)
    )
  end)
  -- A sprite change event may have invalidated the module cache during the transaction.
  index.variants[key] = tile.index
  return tile.index
end

---Create a native tile value with an orientation appropriate to cell shape.
---@param sprite Sprite Document containing the profile.
---@param id string Font profile identifier.
---@param glyph string Unicode character.
---@param fg string Foreground RGBA color.
---@param bg string Background RGBA color.
---@param flags integer Native orientation flags.
---@return integer tile Encoded native tile value.
function M.orientedTile(sprite, id, glyph, fg, bg, flags)
  local profile = M.index(sprite, id).profile
  if profile.cellWidth ~= profile.cellHeight then
    return pc.tile(M.variant(sprite, id, glyph, fg, bg, flags), 0)
  end
  return pc.tile(M.variant(sprite, id, glyph, fg, bg), flags)
end

---Read and validate metadata and transform flags from a native tile value.
---@param layer Layer Text tilemap layer.
---@param value integer Encoded native tile value.
---@return table? metadata Tile metadata, or nil for an empty tile.
---@return integer flags Decoded orientation flags.
function M.decode(layer, value)
  local ti, flags = pc.tileI(value), pc.tileF(value)
  if ti == 0 then
    return nil, flags
  end
  local tile = layer.tileset:tile(ti)
  U.check(tile, "Tile reference is out of range")
  local meta = Base.meta(tile)
  U.check(
    (meta.schemaVersion == 1 or meta.schemaVersion == 2)
      and meta.glyphKey
      and meta.foregroundRGBA
      and meta.backgroundRGBA,
    "Unknown tile " .. ti .. ". Try undoing recent edits or restoring an earlier .aseprite file."
  )
  if meta.schemaVersion == 2 then
    U.check(
      Transforms.validFlags(meta.orientation) and meta.orientation ~= 0,
      "Invalid tile orientation"
    )
    U.check(flags & pc.TILE_DFLIP == 0, "Diagonal native flags are unsupported on oriented tiles")
    flags = meta.orientation ~ flags
  end
  return meta, flags
end

return M
