local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local Loader = require("src.fonts.loader")
local Repertoire = require("src.fonts.repertoire")
local StampState = require("src.document.stamp_state")
local Remap = require("src.document.remap")
local M = {}
local pc = app.pixelColor

---Check whether a cell's canvas bounding box intersects the current marquee selection.
---@param sprite Sprite Document containing the cell.
---@param geometry table Grid geometry.
---@param position Point Cel pixel position.
---@param pixelX integer Cel-relative column index.
---@param pixelY integer Cel-relative row index.
---@param selection Selection Aseprite selection object.
---@return boolean selected True if the cell center point is inside the selection.
local function isCellSelected(sprite, geometry, position, pixelX, pixelY, selection)
  local x = position.x + pixelX * geometry.cellWidth
  local y = position.y + pixelY * geometry.cellHeight
  local left, top = math.max(0, x), math.max(0, y)
  local right, bottom =
    math.min(sprite.width, x + geometry.cellWidth), math.min(sprite.height, y + geometry.cellHeight)
  return right > left
    and bottom > top
    and not selection.isEmpty
    and selection:contains((left + right) // 2, (top + bottom) // 2)
end

---Capture occupied selected cells and their bounding grid.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to inspect.
---@param frame Frame|integer Frame or frame number.
---@param options table? Detached selection and cooperative checkpoint.
---@return table selection Captured cells, count, and bounding dimensions.
function M.selectedCells(sprite, layer, frame, options)
  options = options or {}
  Model.editable(sprite, layer)
  local cel = layer:cel(U.frameNumber(frame))
  local selected = options.selection or sprite.selection
  if not cel or selected.isEmpty then
    return { cells = {}, count = 0, columns = 0, rows = 0 }
  end
  if not options.validated then
    if options.checkpoint then
      local issues = Validate.run(sprite, layer, { checkpoint = options.checkpoint })
      U.check(#issues == 0, Validate.text(issues))
    else
      Validate.requireValid(sprite, layer)
    end
    options.validationComplete = true
  end
  local geometry = Model.geometry(sprite)
  local cells = {}
  local minX, minY, maxX, maxY
  for pixel in cel.image:pixels() do
    if pixel.x == 0 and options.checkpoint then
      options.checkpoint()
    end
    if isCellSelected(sprite, geometry, cel.position, pixel.x, pixel.y, selected) then
      local meta, flags = Profile.decode(layer, pixel())
      if meta then
        cells[#cells + 1] = {
          col = pixel.x,
          row = pixel.y,
          glyphKey = meta.glyphKey,
          foregroundRGBA = meta.foregroundRGBA,
          backgroundRGBA = meta.backgroundRGBA,
          flags = flags or 0,
          outline = meta.outline,
        }
        minX = minX and math.min(minX, pixel.x) or pixel.x
        minY = minY and math.min(minY, pixel.y) or pixel.y
        maxX = maxX and math.max(maxX, pixel.x) or pixel.x
        maxY = maxY and math.max(maxY, pixel.y) or pixel.y
      end
    end
  end
  if #cells == 0 then
    return { cells = {}, count = 0, columns = 0, rows = 0 }
  end
  table.sort(cells, function(a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.col < b.col
  end)
  return {
    cells = cells,
    count = #cells,
    minCol = minX,
    minRow = minY,
    columns = maxX - minX + 1,
    rows = maxY - minY + 1,
  }
end

---Transform occupied selected cells in a single transaction.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to edit.
---@param frame Frame|integer Frame or frame number.
---@param transform fun(metadata: table, flags: integer): integer? Maps a cell to a replacement tile value.
---@return integer count Number of changed cells.
function M.change(sprite, layer, frame, transform)
  Model.editable(sprite, layer)
  Validate.requireValid(sprite, layer)
  local cel = layer:cel(U.frameNumber(frame))
  if not cel then
    return 0
  end
  local image, count = cel.image:clone(), 0
  local geometry = Model.geometry(sprite)
  local selection = sprite.selection
  app.transaction("Edit Text Cells", function()
    for pixel in image:pixels() do
      if isCellSelected(sprite, geometry, cel.position, pixel.x, pixel.y, selection) then
        local meta, flags = Profile.decode(layer, pixel())
        if meta then
          local newValue = transform(meta, flags)
          if newValue and newValue ~= pixel() then
            pixel(newValue)
            count = count + 1
          end
        end
      end
    end
    if count > 0 then
      cel.image = image
    end
  end)
  return count
end

---Replace selected cell attributes while preserving unspecified values.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to edit.
---@param frame Frame|integer Frame or frame number.
---@param fg string? Replacement foreground RGBA color.
---@param bg string? Replacement background RGBA color.
---@param glyph string? Replacement glyph.
---@param orientation integer? Replacement orientation flags.
---@return integer count Number of changed cells.
function M.recolor(sprite, layer, frame, fg, bg, glyph, orientation)
  local id = Model.editable(sprite, layer)
  if glyph then
    Repertoire.scalar(glyph)
  end
  return M.change(sprite, layer, frame, function(meta, flags)
    return Profile.orientedTile(
      sprite,
      id,
      glyph or meta.glyphKey,
      fg or meta.foregroundRGBA,
      bg or meta.backgroundRGBA,
      orientation == nil and flags or orientation,
      meta.outline
    )
  end)
end

---Insert text into a text layer, expanding the cel when needed.
---@param sprite Sprite Destination document.
---@param layer Layer Destination text layer.
---@param frame Frame|integer Frame or frame number.
---@param text string Text to insert.
---@param col integer Starting grid column.
---@param row integer Starting grid row.
---@param fg string Foreground RGBA color.
---@param bg string Background RGBA color.
---@param tabSize? integer Tab width in cells; defaults to four.
---@return integer count Number of cells written.
function M.insert(sprite, layer, frame, text, col, row, fg, bg, tabSize)
  local id = Model.editable(sprite, layer)
  Validate.requireValid(sprite, layer)
  U.integer(col, "Column", 0, 4095)
  U.integer(row, "Row", 0, 4095)
  tabSize = U.integer(tabSize or 4, "Tab width", 1, 16)
  local g = Model.geometry(sprite)
  local extent = Model.coverage(sprite, g)
  local cols, rows = extent.columns, extent.rows
  local originalCol, writes, keys = col, {}, {}
  local index = Profile.index(sprite, id)
  for _, cp in utf8.codes(text:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")) do
    if cp == 10 then
      col, row = originalCol, row + 1
    elseif cp == 9 then
      col = originalCol + ((col - originalCol) // tabSize + 1) * tabSize
    else
      local key = utf8.char(cp)
      Repertoire.scalar(key)
      keys[#keys + 1] = key
      U.check(
        col < cols and row < rows,
        "Text exceeds the canvas; choose a smaller block or a larger grid"
      )
      writes[#writes + 1] =
        { col = col + extent.firstCol, row = row + extent.firstRow, glyph = key }
      col = col + 1
    end
  end
  Repertoire.budget(index.profile, #index.order + #Repertoire.missing(index.glyphs, keys))
  if #writes == 0 then
    return 0
  end
  local image, cel, minX, minY = Model.expandTilemapCel(
    sprite,
    layer,
    U.frameNumber(frame),
    g,
    extent.firstCol,
    extent.firstRow,
    cols,
    rows
  )
  app.transaction("Insert Text Cells", function()
    Profile.ensureCharacters(sprite, id, keys)
    for _, write in ipairs(writes) do
      image:drawPixel(
        write.col - minX,
        write.row - minY,
        Profile.variant(sprite, id, write.glyph, fg, bg)
      )
    end
    local position = Point(g.originX + minX * g.cellWidth, g.originY + minY * g.cellHeight)
    if cel then
      cel.image = image
      cel.position = position
    else
      sprite:newCel(layer, U.frameNumber(frame), image, position)
    end
  end)
  return #writes
end

---List distinct characters used in all cels of a text layer.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to inspect.
---@return string[] keys Characters in first-seen order.
function M.characters(sprite, layer)
  Validate.requireValid(sprite, layer)
  local keys, seen = {}, {}
  for _, cel in ipairs(layer.cels) do
    for pixel in cel.image:pixels() do
      local meta = Profile.decode(layer, pixel())
      if meta and not seen[meta.glyphKey] then
        keys[#keys + 1], seen[meta.glyphKey] = meta.glyphKey, true
      end
    end
  end
  return keys
end

-- Capture all stored frames and bindings, including hidden and linked cels.
---Capture a signature of layer content, bindings, and document geometry.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to inspect.
---@return string signature Signature used to detect stale operations.
function M.layerSignature(sprite, layer)
  Model.editable(sprite, layer)
  local tilesetIndex = 0
  for i, tileset in ipairs(sprite.tilesets) do
    if tileset == layer.tileset then
      tilesetIndex = i
      break
    end
  end
  local parts = {
    tostring(layer.uuid),
    tilesetIndex,
    json.encode(Model.meta(layer)),
    json.encode(Model.geometry(sprite)),
    sprite.width,
    sprite.height,
    #sprite.frames,
  }
  local index = Profile.index(sprite, Model.meta(layer).fontProfileId)
  parts[#parts + 1] = json.encode(Model.meta(index.masks))
  for _, key in ipairs(index.order) do
    local source = index.glyphs[key]
    parts[#parts + 1] = json.encode(Model.meta(source.tile)) .. U.hash(source.tile.image.bytes)
  end
  for _, cel in ipairs(layer.cels) do
    parts[#parts + 1] = table.concat(
      { cel.frameNumber, cel.image.id, U.hash(cel.image.bytes), cel.position.x, cel.position.y },
      ":"
    )
  end
  return table.concat(parts, "|")
end

---Find layer characters absent from the target font profile.
---@param sprite Sprite Source document.
---@param layer Layer Text layer to inspect.
---@param id string Target profile identifier.
---@return string[] missing Missing character keys.
function M.missing(sprite, layer, id)
  local target = Profile.index(sprite, id)
  local missing = {}
  for _, cel in ipairs(layer.cels) do
    for pixel in cel.image:pixels() do
      local meta = Profile.decode(layer, pixel())
      if meta and not target.glyphs[meta.glyphKey] then
        missing[meta.glyphKey] = true
      end
    end
  end
  local result = {}
  for key in pairs(missing) do
    result[#result + 1] = key
  end
  table.sort(result)
  return result
end

---Replace a layer font and remap its cels and saved stamps.
---@param sprite Sprite Document to update.
---@param layer Layer Text layer to update.
---@param id string Target profile identifier.
function M.replaceFont(sprite, layer, id)
  Model.editable(sprite, layer)
  Validate.requireValid(sprite, layer)
  local missing = M.missing(sprite, layer, id)
  local index = Profile.index(sprite, id)
  app.transaction("Replace Text Layer Font", function()
    Profile.ensureCharacters(sprite, id, missing)
    M.remapLayer(sprite, layer, id)
    Profile.bindLayer(layer, id, index)
    StampState.reconcileLayer(sprite, layer, id)
  end)
  Profile.invalidate()
end

---Remap linked cels across layers before replacing any source image.
M.remapLayers = Remap.layers

---Remap layer cels to variants from another font profile.
---@param sprite Sprite Document containing both profiles.
---@param layer Layer Layer with old tile references.
---@param id string Target profile identifier.
function M.remapLayer(sprite, layer, id)
  M.remapLayers(sprite, { { layer = layer, id = Model.meta(layer).fontProfileId, targetId = id } })
end

---Compute a cache signature for the document layout, profiles, and text cel contents.
---@param sprite Sprite Document to fingerprint.
---@return string signature Composite fingerprint string.
local function signature(sprite)
  local parts = {
    json.encode(Model.geometry(sprite)),
    sprite.width,
    sprite.height,
    tostring(Model.composition(sprite).mixed),
  }
  for _, entry in ipairs(Profile.profiles(sprite)) do
    parts[#parts + 1] = entry.id .. ":" .. U.hash(json.encode(entry.profile))
  end
  for _, layer in ipairs(Model.layers(sprite)) do
    parts[#parts + 1] = tostring(layer.uuid)
    if Model.layerManaged(layer) then
      parts[#parts + 1] = Model.meta(layer).fontProfileId
      for _, cel in ipairs(layer.cels) do
        parts[#parts + 1] = string.format(
          "%d:%d:%d:%s",
          cel.frameNumber,
          cel.position.x,
          cel.position.y,
          U.hash(cel.image.bytes)
        )
      end
    end
  end
  return table.concat(parts, "|")
end

---Calculate the fractional intersection of a rectangle with the canvas.
---@param x integer Rectangle left pixel coordinate.
---@param y integer Rectangle top pixel coordinate.
---@param w integer Rectangle width in pixels.
---@param h integer Rectangle height in pixels.
---@param canvasWidth integer Canvas width in pixels.
---@param canvasHeight integer Canvas height in pixels.
---@return number fraction Fraction of the rectangle visible on canvas (0.0 to 1.0).
local function visibleFraction(x, y, w, h, canvasWidth, canvasHeight)
  local width = math.max(0, math.min(canvasWidth, x + w) - math.max(0, x))
  local height = math.max(0, math.min(canvasHeight, y + h) - math.max(0, y))
  return width * height / (w * h)
end

---Calculate the canvas and visibility effects of a new cell size.
---@param sprite Sprite Document to inspect.
---@param width integer New cell width.
---@param height integer New cell height.
---@return table preview Target geometry, backgrounds, and clipped or hidden counts.
function M.previewRegrid(sprite, width, height)
  U.integer(width, "Cell width", 1, 512)
  U.integer(height, "Cell height", 1, 512)
  local old, composition = Model.geometry(sprite), Model.composition(sprite)
  local extent = Model.coverage(sprite, old)
  local g = U.copy(old)
  g.cellWidth, g.cellHeight = width, height
  local canvasWidth, canvasHeight = sprite.width, sprite.height
  if not composition.mixed then
    canvasWidth = g.originX + (-g.originX // width + extent.columns) * width
    canvasHeight = g.originY + (-g.originY // height + extent.rows) * height
  end
  U.check(
    canvasWidth <= 65535 and canvasHeight <= 65535,
    "Regrid canvas exceeds Aseprite dimensions"
  )
  local coverage = Model.coverage({ width = canvasWidth, height = canvasHeight }, g)
  local clipped, hidden = 0, 0
  for _, layer in ipairs(Model.layers(sprite)) do
    if Model.layerManaged(layer) then
      for _, cel in ipairs(layer.cels) do
        for pixel in cel.image:pixels() do
          if pc.tileI(pixel()) ~= 0 then
            local baseCol, baseRow = Model.celOrigin(cel, old)
            local col, row = baseCol + pixel.x, baseRow + pixel.y
            local before = visibleFraction(
              old.originX + col * old.cellWidth,
              old.originY + row * old.cellHeight,
              old.cellWidth,
              old.cellHeight,
              sprite.width,
              sprite.height
            )
            local after = visibleFraction(
              g.originX + col * width,
              g.originY + row * height,
              width,
              height,
              canvasWidth,
              canvasHeight
            )
            if after < before - 0.000001 then
              if after == 0 then
                hidden = hidden + 1
              else
                clipped = clipped + 1
              end
            end
          end
        end
      end
    end
  end
  return {
    mixed = composition.mixed,
    backgrounds = composition.backgrounds,
    width = canvasWidth,
    height = canvasHeight,
    coverage = coverage,
    clipped = clipped,
    hidden = hidden,
  }
end

-- Prepare resources before mutation; capture the target to reject stale previews.
---Prepare font jobs and capture document state for regridding.
---@param sprite Sprite Document to regrid.
---@param width integer New cell width.
---@param height integer New cell height.
---@param resolve? function Saved font resource resolver.
---@return table jobs Font jobs and document signature.
function M.prepareRegrid(sprite, width, height, resolve)
  Validate.requireValid(sprite)
  M.previewRegrid(sprite, width, height)
  for _, layer in ipairs(Model.layers(sprite)) do
    if layer.isTilemap and not Model.layerManaged(layer) then
      Model.checkUnmanagedTilemap(
        layer,
        "A native tilemap shares Asemode font tiles; give it an independent tileset before changing cell size"
      )
    end
  end
  local old = Model.geometry(sprite)
  local jobs = { context = signature(sprite) }
  for _, entry in ipairs(Profile.profiles(sprite)) do
    local index = Profile.index(sprite, entry.id)
    local p = index.profile
    U.check(
      p.kind == "truetype",
      "Bitmap profiles must be reimported at the new authored cell size"
    )
    local job = Loader.fromProfile(p, {
      pixelSize = p.pixelSize * height / old.cellHeight,
      characters = table.concat(index.order),
      cellWidth = width,
      cellHeight = height,
      antialias = p.antialias,
    }, resolve)
    jobs[#jobs + 1] = { oldId = entry.id, job = job }
  end
  return jobs
end

---Calculate canvas changes for a requested grid size.
---@param sprite Sprite Document to inspect.
---@param columns integer Requested columns.
---@param rows integer Requested rows.
---@return table preview Target canvas size and visibility changes.
function M.previewGridSize(sprite, columns, rows)
  columns = U.integer(columns, "Columns", 1, 4096)
  rows = U.integer(rows, "Rows", 1, 4096)
  local g = Model.geometry(sprite)
  local width = g.originX + (-g.originX // g.cellWidth + columns) * g.cellWidth
  local height = g.originY + (-g.originY // g.cellHeight + rows) * g.cellHeight
  U.check(
    width > 0
      and height > 0
      and width <= 65535
      and height <= 65535
      and columns * rows <= 4 * 1024 * 1024,
    "Grid dimensions exceed Aseprite canvas limits"
  )
  return {
    width = width,
    height = height,
    columns = columns,
    rows = rows,
    hidesRight = width < sprite.width,
    hidesBottom = height < sprite.height,
    expandsRight = width > sprite.width,
    expandsBottom = height > sprite.height,
  }
end

-- Changing the canvas extent hides content without cropping stored cel images.
---Resize the canvas to a grid size without cropping stored cel images.
---@param sprite Sprite Document to resize.
---@param columns integer Requested columns.
---@param rows integer Requested rows.
---@return integer columns Applied columns.
---@return integer rows Applied rows.
function M.resizeGrid(sprite, columns, rows)
  Validate.requireValid(sprite)
  local target = M.previewGridSize(sprite, columns, rows)
  if sprite.width == target.width and sprite.height == target.height then
    return columns, rows
  end
  local backgrounds = Model.composition(sprite).backgrounds
  app.transaction("Resize Textmode Grid", function()
    sprite.width, sprite.height = target.width, target.height
    Model.resizeBackgrounds(backgrounds, target.width, target.height)
  end)
  return columns, rows
end

---Apply prepared font jobs and change the document cell size.
---@param sprite Sprite Document to regrid.
---@param jobs table Prepared jobs and original document signature.
---@param width integer New cell width.
---@param height integer New cell height.
---@param allowClipping boolean Whether clipped glyphs are approved.
---@param allowHidden boolean Whether newly clipped or hidden cells are approved.
function M.regrid(sprite, jobs, width, height, allowClipping, allowHidden)
  Validate.requireValid(sprite)
  U.check(
    jobs.context == signature(sprite),
    "The document changed after preparation; preview the cell size again"
  )
  local old, target = Model.geometry(sprite), M.previewRegrid(sprite, width, height)
  U.check(
    target.clipped + target.hidden == 0 or allowHidden,
    "Confirm occupied cells becoming clipped or hidden"
  )
  for _, item in ipairs(jobs) do
    U.check(item.job.position == #item.job.glyphs, "Finish all font imports before regrid")
    U.check(
      item.job.profile.cellWidth == width and item.job.profile.cellHeight == height,
      "Prepared cell size differs"
    )
    U.check(
      item.job.profile.clippedGlyphs == 0 or allowClipping,
      "Regrid clips glyphs; confirm in the preview"
    )
  end
  local oldLayers, oldProfiles = {}, {}
  for _, layer in ipairs(Model.layers(sprite)) do
    if Model.layerManaged(layer) then
      Model.editable(sprite, layer)
      local copies = {}
      for _, cel in ipairs(layer.cels) do
        copies[#copies + 1] = { cel = cel, x = cel.position.x, y = cel.position.y }
      end
      oldLayers[#oldLayers + 1] =
        { layer = layer, id = Model.meta(layer).fontProfileId, cels = copies }
    end
  end
  for _, entry in ipairs(Profile.profiles(sprite)) do
    local index = Profile.index(sprite, entry.id)
    oldProfiles[#oldProfiles + 1], oldProfiles[#oldProfiles + 2] = index.masks, index.paint
  end
  local ok, err = pcall(function()
    app.transaction("Regrid Textmode Sprite", function()
      local geometry = U.copy(old)
      geometry.cellWidth, geometry.cellHeight = width, height
      Model.setMeta(sprite, geometry)
      local replacements = {}
      for _, item in ipairs(jobs) do
        replacements[item.oldId] = Profile.install(sprite, item.job, allowClipping)
      end
      for _, data in ipairs(oldLayers) do
        local targetIndex =
          Profile.index(sprite, U.check(replacements[data.id], "Prepared font profile is missing"))
        M.remapLayer(sprite, data.layer, targetIndex.id)
        Profile.bindLayer(data.layer, targetIndex.id, targetIndex)
        StampState.reconcileLayer(sprite, data.layer, targetIndex.id)
      end
      sprite.width, sprite.height = target.width, target.height
      if not target.mixed then
        Model.resizeBackgrounds(target.backgrounds, target.width, target.height)
      end
      for _, data in ipairs(oldLayers) do
        for _, copy in ipairs(data.cels) do
          copy.cel.position = Point(
            old.originX + (copy.x - old.originX) // old.cellWidth * width,
            old.originY + (copy.y - old.originY) // old.cellHeight * height
          )
        end
      end
      for _, ts in ipairs(oldProfiles) do
        sprite:deleteTileset(ts)
      end
    end)
  end)
  Profile.invalidate()
  if not ok then
    error(err, 0)
  end
end

return M
