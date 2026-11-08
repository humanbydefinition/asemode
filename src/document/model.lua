local U = require("src.core.util")
local Base = require("src.document.base")
local Profile = require("src.document.profile")
local M = { schemaVersion = 1 }
local pc = app.pixelColor
M.meta, M.setMeta, M.managed, M.layerManaged, M.geometry =
  Base.meta, Base.setMeta, Base.managed, Base.layerManaged, Base.geometry

---Return the grid coordinates of a tilemap cel's origin.
---@param cel Cel Tilemap cel to locate.
---@param geometry table Grid geometry containing originX, originY, cellWidth, cellHeight.
---@return integer col Grid column index.
---@return integer row Grid row index.
function M.celOrigin(cel, geometry)
  return (cel.position.x - geometry.originX) // geometry.cellWidth,
    (cel.position.y - geometry.originY) // geometry.cellHeight
end

---Prepare an expanded tilemap image without mutating the document.
---@param sprite Sprite Document containing the layer.
---@param layer Layer Tilemap layer to read.
---@param frame Frame|integer Target frame or frame number.
---@param geometry table Grid geometry.
---@param firstCol integer First column index.
---@param firstRow integer First row index.
---@param columns integer Number of columns.
---@param rows integer Number of rows.
---@return Image image Expanded tilemap image.
---@return Cel? cel Existing cel if present.
---@return integer minX Bounding minimum column.
---@return integer minY Bounding minimum row.
function M.expandTilemapCel(sprite, layer, frame, geometry, firstCol, firstRow, columns, rows)
  local cel = layer:cel(frame)
  local minX, minY = firstCol, firstRow
  local maxX, maxY = firstCol + columns, firstRow + rows
  if cel then
    local x, y = M.celOrigin(cel, geometry)
    minX, minY = math.min(minX, x), math.min(minY, y)
    maxX, maxY = math.max(maxX, x + cel.image.width), math.max(maxY, y + cel.image.height)
  end
  local image = Image(maxX - minX, maxY - minY, ColorMode.TILEMAP)
  if cel then
    local x, y = M.celOrigin(cel, geometry)
    for pixel in cel.image:pixels() do
      image:drawPixel(x - minX + pixel.x, y - minY + pixel.y, pixel())
    end
  end
  return image, cel, minX, minY
end

---Reject native tilemaps that share managed font tiles.
---@param layer Layer Candidate layer to check.
---@param message string Error message if the tilemap is unmanaged but shares font tiles.
function M.checkUnmanagedTilemap(layer, message)
  local binding = M.meta(layer.tileset)
  U.check(
    binding.schemaVersion ~= 1 or (binding.role ~= "paint" and binding.role ~= "masks"),
    message
  )
end

-- A regular sprite can acquire Asemode resources without replacing its grid.
---Check whether a sprite can receive Asemode resources.
---@param sprite Sprite? Candidate sprite.
---@return boolean eligible Whether the sprite and its metadata are supported.
function M.eligible(sprite)
  if not (sprite and sprite.isValid and sprite.colorMode == ColorMode.RGB) then
    return false
  end
  if sprite.tileManagementPlugin then
    return false
  end
  local schema = M.meta(sprite).schemaVersion
  if schema ~= nil and schema ~= M.schemaVersion then
    return false
  end
  if schema == nil then
    return true
  end
  local ok = pcall(M.geometry, sprite)
  return ok
end

---Reject a sprite that cannot receive Asemode resources.
---@param sprite Sprite? Candidate sprite.
function M.requireEligible(sprite)
  U.check(sprite and sprite.isValid, "Open an RGB sprite first")
  U.check(
    sprite.colorMode == ColorMode.RGB,
    "Textmode layers require an RGB/RGBA sprite; convert the color mode explicitly first"
  )
  U.check(not sprite.tileManagementPlugin, "This sprite uses another tile management extension")
  U.check(M.eligible(sprite), "Unsupported or invalid Asemode document metadata")
end

---Check whether a sprite is a supported Asemode document.
---@param sprite Sprite? Candidate sprite.
---@return boolean supported Whether the document is managed and eligible.
function M.supported(sprite)
  if not M.managed(sprite) then
    return false
  end
  return M.eligible(sprite)
end

---Identify a layer carrying Asemode metadata, including unsupported versions.
---@param sprite Sprite? Candidate document.
---@param layer Layer? Candidate layer.
---@return boolean marked Whether both objects carry Asemode schema markers.
function M.markedLayer(sprite, layer)
  return not not (
    sprite
    and sprite.isValid
    and layer
    and layer.isTilemap
    and layer.sprite == sprite
    and M.meta(sprite).schemaVersion ~= nil
    and M.meta(layer).schemaVersion ~= nil
  )
end

---Check whether a layer is a valid text layer belonging to the sprite.
---@param sprite Sprite? Candidate document.
---@param layer Layer? Candidate layer.
---@return boolean valid Whether the layer and its font resources match.
function M.textLayer(sprite, layer)
  if not (M.supported(sprite) and M.layerManaged(layer) and layer.sprite == sprite) then
    return false
  end
  local id = M.meta(layer).fontProfileId
  local ok, index = pcall(Profile.index, sprite, id)
  return ok and index.paint == layer.tileset
end

---Check whether a sprite contains any marked Asemode layers.
---@param sprite Sprite? Candidate sprite.
---@return boolean hasLayers True if at least one layer carries Asemode metadata.
function M.hasMarkedLayers(sprite)
  if not sprite then
    return false
  end
  for _, layer in ipairs(M.layers(sprite)) do
    if M.markedLayer(sprite, layer) then
      return true
    end
  end
  return false
end

---Check that a layer and its parent groups are visible and editable.
---@param layer Layer? Candidate layer or group.
---@param sprite Sprite Containing document root.
---@return boolean editable True if the layer and all ancestors are visible and editable.
function M.ancestorsEditable(layer, sprite)
  local current = layer
  while current and current ~= sprite do
    if not (current.isEditable and current.isVisible) then
      return false
    end
    current = current.parent
  end
  return true
end

-- Includes every cell with a nonempty intersection with the canvas.
---Calculate grid cells that intersect the sprite canvas.
---@param sprite Sprite Document whose canvas is measured.
---@param geometry table? Grid geometry; defaults to the document metadata.
---@return table coverage First row and column, dimensions, and partial-cell flag.
function M.coverage(sprite, geometry)
  local g = geometry or M.geometry(sprite)
  local firstCol, firstRow = -g.originX // g.cellWidth, -g.originY // g.cellHeight
  local lastCol = (sprite.width - 1 - g.originX) // g.cellWidth
  local lastRow = (sprite.height - 1 - g.originY) // g.cellHeight
  local columns, rows = lastCol - firstCol + 1, lastRow - firstRow + 1
  U.check(
    columns <= 4096 and rows <= 4096 and columns * rows <= 4 * 1024 * 1024,
    "Visible Textmode grid exceeds the supported cell limits"
  )
  return {
    firstCol = firstCol,
    firstRow = firstRow,
    columns = columns,
    rows = rows,
    partial = (
      g.originX + firstCol * g.cellWidth ~= 0
      or g.originY + firstRow * g.cellHeight ~= 0
      or g.originX + (lastCol + 1) * g.cellWidth ~= sprite.width
      or g.originY + (lastRow + 1) * g.cellHeight ~= sprite.height
    ),
  }
end

---Initialize Asemode metadata or verify the existing cell size.
---@param sprite Sprite Destination document.
---@param width integer Cell width in pixels.
---@param height integer Cell height in pixels.
function M.initialize(sprite, width, height)
  M.requireEligible(sprite)
  U.integer(width, "Cell width", 1, 512)
  U.integer(height, "Cell height", 1, 512)
  if M.managed(sprite) then
    local g = M.geometry(sprite)
    U.check(
      g.cellWidth == width and g.cellHeight == height,
      "The document cell size changed; open Add Textmode Layer again"
    )
    return
  end
  local geometry = M.meta(sprite)
  geometry.schemaVersion, geometry.cellWidth, geometry.cellHeight = 1, width, height
  geometry.originX, geometry.originY, geometry.background = 0, 0, "transparent"
  M.coverage(sprite, geometry)
  M.setMeta(sprite, geometry)
end

---Normalize a color value or named preset into an RGBA hexadecimal string.
---@param value string? Color value or preset name ('white', 'black').
---@return string? hex Normalized #rrggbbaa string, or nil if invalid.
local function backgroundColor(value)
  if value == "white" then
    return "#ffffffff"
  end
  if value == "black" then
    return "#000000ff"
  end
  return U.isHexColor(value) and value or nil
end

-- Only a proven, unchanged generated fill is exempt from mixed-project rules.
---Identify a generated background that remains an unchanged solid fill.
---@param sprite Sprite Document containing the layer.
---@param layer Layer Candidate background layer.
---@return string? color RGBA color when the fill is still valid.
function M.generatedBackground(sprite, layer)
  local color = M.meta(layer).generatedBackground
  if not color and layer.isBackground then
    color = M.meta(sprite).background
  end
  color = backgroundColor(color)
  if not color then
    return nil
  end
  local value = pc.rgba(U.rgba(color))
  if #layer.cels == 0 then
    return nil
  end
  for _, cel in ipairs(layer.cels) do
    if
      cel.position.x ~= 0
      or cel.position.y ~= 0
      or cel.image.width ~= sprite.width
      or cel.image.height ~= sprite.height
    then
      return nil
    end
    for pixel in cel.image:pixels() do
      if pixel() ~= value then
        return nil
      end
    end
  end
  return color
end

---Classify non-text layers and unchanged generated backgrounds.
---@param sprite Sprite Document to inspect.
---@return table composition Mixed-content flag and generated backgrounds.
function M.composition(sprite)
  local backgrounds, mixed = {}, false
  for _, layer in ipairs(M.layers(sprite)) do
    if not M.layerManaged(layer) then
      local color = not layer.isReference
        and not layer.isTilemap
        and M.generatedBackground(sprite, layer)
      if color then
        backgrounds[#backgrounds + 1] = { layer = layer, color = color }
      else
        mixed = true
      end
    end
  end
  return { mixed = mixed, backgrounds = backgrounds }
end

---Replace generated background images at a new canvas size.
---@param backgrounds table[] Generated background layers and colors.
---@param width integer New canvas width.
---@param height integer New canvas height.
function M.resizeBackgrounds(backgrounds, width, height)
  for _, item in ipairs(backgrounds) do
    local seen = {}
    for _, cel in ipairs(item.layer.cels) do
      local id = cel.image.id
      if not seen[id] then
        local image = Image(width, height, ColorMode.RGB)
        image:clear(pc.rgba(U.rgba(item.color)))
        cel.image = image
        seen[id], seen[image.id] = true, true
      end
    end
    local meta = M.meta(item.layer)
    meta.generatedBackground = item.color
    M.setMeta(item.layer, meta)
  end
end

---List non-group layers recursively in document order.
---@param sprite Sprite Document to inspect.
---@return Layer[] layers Flattened layer list.
function M.layers(sprite)
  local result = {}
  ---Recursively collect leaf layers from a layer list.
  ---@param layers Layer[] List of layers or groups to traverse.
  local function walk(layers)
    for _, layer in ipairs(layers) do
      if layer.isGroup then
        walk(layer.layers)
      else
        result[#result + 1] = layer
      end
    end
  end
  walk(sprite.layers)
  return result
end

---Create a text tilemap layer for an installed font profile.
---@param sprite Sprite Destination document.
---@param id string Installed font profile identifier.
---@param name? string Layer name; defaults to the profile name.
---@return Layer layer Created layer.
function M.addLayer(sprite, id, name)
  local index = Profile.index(sprite, id)
  app.sprite = sprite
  local layer
  app.transaction("Add Textmode Layer", function()
    local previous = app.layer
    app.command.NewLayer({
      name = name or index.profile.name,
      tilemap = true,
      ui = false,
      gridBounds = Rectangle(0, 0, index.profile.cellWidth, index.profile.cellHeight),
    })
    layer = app.layer
    U.check(
      layer and layer ~= previous and layer.isTilemap,
      "Aseprite could not create a tilemap layer; check that the document is writable"
    )
    local emptyTileset = layer.tileset
    layer.tileset = index.paint
    sprite:deleteTileset(emptyTileset)
    M.setMeta(layer, { schemaVersion = 1, fontProfileId = id })
  end)
  return layer
end

-- All resources and initial stamps belong to the same undo step.
---Install a prepared font and add a text layer in one undo step.
---@param sprite Sprite Destination document.
---@param job AsemodeFontJob Completed font job.
---@param allowClipping boolean Whether clipped glyphs are approved.
---@param options table? Destination snapshot, insertion anchor, and stamp options.
---@return Layer layer Created layer.
---@return string id Installed font profile identifier.
---@return table? stamps Prepared foreground and background stamp indices.
function M.attach(sprite, job, allowClipping, options)
  options = options or {}
  M.requireEligible(sprite)
  U.check(job.position == #job.glyphs, "Font import is not complete")
  U.check(job.profile.clippedGlyphs == 0 or allowClipping, "Confirm font clipping first")
  if options.geometry then
    local g = M.geometry(sprite)
    for _, key in ipairs({ "cellWidth", "cellHeight", "originX", "originY" }) do
      U.check(
        g[key] == options.geometry[key],
        "The Textmode grid changed; open the layer dialog again"
      )
    end
  elseif options.unmanaged then
    U.check(
      not M.managed(sprite),
      "Asemode was added to this document while the dialog was open; try again"
    )
  end
  if options.anchor then
    local found = false
    ---Recursively check whether the anchor layer exists in the tree.
    ---@param layers Layer[] Layers to inspect.
    local function walk(layers)
      for _, layer in ipairs(layers) do
        if layer == options.anchor then
          found = true
        end
        if layer.isGroup then
          walk(layer.layers)
        end
      end
    end
    walk(sprite.layers)
    U.check(found, "The layer insertion destination was removed")
    local parent = options.anchor.isGroup and options.anchor or options.anchor.parent
    U.check(M.ancestorsEditable(parent, sprite), "Unlock and show the destination group first")
  end
  app.sprite = sprite
  if options.anchor then
    app.layer = options.anchor
  end
  local layer, id, stamps
  local ok, err = pcall(function()
    app.transaction("Add Textmode Layer", function()
      M.initialize(sprite, job.profile.cellWidth, job.profile.cellHeight)
      id = Profile.install(sprite, job, allowClipping)
      layer = M.addLayer(sprite, id)
      if options.foregroundGlyph then
        stamps = {
          foreground = Profile.variant(sprite, id, options.foregroundGlyph, options.fg, options.bg),
        }
        if options.backgroundGlyph then
          stamps.background =
            Profile.variant(sprite, id, options.backgroundGlyph, options.fg, options.bg)
        end
      end
    end)
  end)
  Profile.invalidate()
  if not ok then
    error(err, 0)
  end
  return layer, id, stamps
end

---Create a new textmode sprite from a completed font job.
---@param job AsemodeFontJob Completed font job.
---@param cols integer Number of grid columns.
---@param rows integer Number of grid rows.
---@param allowClipping boolean Whether clipped glyphs are approved.
---@param background? string Background color or transparent, white, or black.
---@return Sprite sprite Created sprite.
---@return Layer layer Created text layer.
---@return string id Installed font profile identifier.
function M.create(job, cols, rows, allowClipping, background)
  background = background or "transparent"
  local color = backgroundColor(background)
  U.check(
    background == "transparent" or color,
    "Choose a transparent, white, black, or custom background color"
  )
  local backgroundR, backgroundG, backgroundB, backgroundA
  if color then
    backgroundR, backgroundG, backgroundB, backgroundA = U.rgba(color)
  end
  local transparentBackground = background == "transparent" or backgroundA == 0
  U.integer(cols, "Columns", 1, 4096)
  U.integer(rows, "Rows", 1, 4096)
  local w, h = job.profile.cellWidth, job.profile.cellHeight
  U.check(
    cols * w <= 65535 and rows * h <= 65535 and cols * rows <= 4 * 1024 * 1024,
    "Document dimensions exceed the supported limits"
  )
  local sprite = Sprite(cols * w, rows * h, ColorMode.RGB)
  local defaultPalette = app.defaultPalette
  if defaultPalette then
    sprite:setPalette(defaultPalette)
  end
  local ok, result = pcall(function()
    app.transaction("Create Textmode Sprite", function()
      M.setMeta(sprite, {
        schemaVersion = 1,
        cellWidth = w,
        cellHeight = h,
        originX = 0,
        originY = 0,
        background = background,
      })
      sprite.gridBounds = Rectangle(0, 0, w, h)
    end)
    local id = Profile.install(sprite, job, allowClipping)
    local original = sprite.layers[1]
    if not transparentBackground then
      app.sprite, app.layer = sprite, original
      local cel = original:cel(1)
      U.check(cel, "Aseprite did not create the initial background cel")
      cel.image:clear(pc.rgba(backgroundR, backgroundG, backgroundB, backgroundA))
      M.setMeta(
        original,
        { generatedBackground = U.hex(backgroundR, backgroundG, backgroundB, backgroundA) }
      )
      if backgroundA == 255 then
        app.command.ConvertLayer({ to = "background", ui = false })
        U.check(sprite.backgroundLayer, "Aseprite did not create the background layer")
      end
    end
    local layer = M.addLayer(sprite, id, "Text 1")
    if transparentBackground then
      sprite:deleteLayer(original)
    end
    return { sprite = sprite, layer = layer, profileId = id }
  end)
  if not ok then
    sprite:close()
    error(result, 0)
  end
  return result.sprite, result.layer, result.profileId
end

---Validate a text layer and its ancestors for editing.
---@param sprite Sprite Managed document.
---@param layer Layer Candidate layer.
---@return string id Layer font profile identifier.
function M.editable(sprite, layer)
  M.geometry(sprite)
  U.check(M.layerManaged(layer), "Select an Asemode tilemap layer")
  U.check(
    M.ancestorsEditable(layer, sprite),
    "Unlock and show the text layer and its parent groups"
  )
  return M.meta(layer).fontProfileId
end

return M
