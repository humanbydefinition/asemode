local U = require("src.core.util")
local Edit = require("src.document.edit")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Validate = require("src.document.validate")
local Repertoire = require("src.fonts.repertoire")
local Loader = require("src.fonts.loader")
local M = {}

---Calculate the grid column and row coordinates of a selection's top-left bounds.
---@param selection Selection Aseprite selection.
---@param geometry table Grid geometry containing originX, originY, cellWidth, cellHeight.
---@return integer col Top-left column index.
---@return integer row Top-left row index.
local function origin(selection, geometry)
  local bounds = selection.bounds
  return (bounds.x - geometry.originX) // geometry.cellWidth,
    (bounds.y - geometry.originY) // geometry.cellHeight
end

---Capture semantic cell data, independent of source sprite and tile indices.
---@param sprite Sprite Source document.
---@param layer Layer Source text layer.
---@param frame Frame|integer Source frame or frame number.
---@param selection Selection Selection containing occupied cells to copy.
---@return table clipboard Captured cells and anchor coordinates.
function M.copy(sprite, layer, frame, selection)
  U.check(selection and not selection.isEmpty, "Select the cells to copy first")
  local selected = Edit.selectedCells(sprite, layer, frame, { selection = selection })
  U.check(selected.count > 0, "The selection has no occupied Asemode cells")
  local g = Model.geometry(sprite)
  local cel = layer:cel(U.frameNumber(frame))
  local col, row = origin(selection, g)
  local celCol, celRow = Model.celOrigin(cel, g)
  local result = { col = col, row = row, cells = {} }
  for _, cell in ipairs(selected.cells) do
    result.cells[#result.cells + 1] = {
      col = celCol + cell.col - col,
      row = celRow + cell.row - row,
      glyph = cell.glyphKey,
      fg = cell.foregroundRGBA,
      bg = cell.backgroundRGBA,
      flags = cell.flags,
    }
  end
  return result
end

---Prepare the target cells and any font masks without changing the document.
---@param sprite Sprite Destination document.
---@param layer Layer Destination text layer.
---@param frame Frame|integer Target frame or frame number.
---@param selection? Selection Target paste selection or anchor.
---@param clipboard table Copied clipboard payload.
---@param resolve? fun(id: string, digest: string): table User font resource resolver.
---@return table prepared Staged write operations, additions, and missing counts.
function M.prepare(sprite, layer, frame, selection, clipboard, resolve)
  U.check(clipboard and #clipboard.cells > 0, "Copy Asemode cells first")
  local id = Model.editable(sprite, layer)
  Validate.requireValid(sprite, layer)
  local g, extent = Model.geometry(sprite), Model.coverage(sprite)
  local col, row = clipboard.col, clipboard.row
  if selection and not selection.isEmpty then
    col, row = origin(selection, g)
  end
  local index, keys, unseen = Profile.index(sprite, id), {}, {}
  for _, cell in ipairs(clipboard.cells) do
    local x, y = col + cell.col, row + cell.row
    U.check(
      x >= extent.firstCol
        and x < extent.firstCol + extent.columns
        and y >= extent.firstRow
        and y < extent.firstRow + extent.rows,
      "Copied cells do not fit on the canvas. Select another paste position."
    )
    if cell.glyph ~= " " and not index.glyphs[cell.glyph] and not unseen[cell.glyph] then
      unseen[cell.glyph] = true
      keys[#keys + 1] = cell.glyph
    end
  end
  local additions, resolved = {}, {}
  if #keys > 0 and index.profile.kind == "truetype" then
    local p = index.profile
    local job = Loader.fromProfile(p, {
      pixelSize = p.pixelSize,
      cellWidth = p.cellWidth,
      cellHeight = p.cellHeight,
      antialias = p.antialias,
      characters = table.concat(index.order),
    }, resolve)
    Loader.ensureCharacters(job, keys)
    -- Keep the destination's existing layout even when its stored repertoire
    -- was extended with fallback characters after the font was imported.
    local advance = p.advance
    for _, key in ipairs(advance and {} or index.supportedOrder) do
      local meta = index.glyphs[key].meta
      if type(meta.advance) == "number" and type(meta.offsetX) == "number" then
        advance = 2 * meta.offsetX + meta.advance * p.scale
        break
      end
    end
    for _, glyph in ipairs(job.glyphs) do
      if unseen[glyph.glyphKey] and not glyph.renderFallback and advance then
        glyph.offsetX = (advance - glyph.advance * p.scale) / 2
      end
    end
    job.profile.originX, job.profile.baseline, job.profile.scale = p.originX, p.baseline, p.scale
    job:finish()
    for i, glyph in ipairs(job.glyphs) do
      if unseen[glyph.glyphKey] then
        resolved[glyph.glyphKey] = not glyph.renderFallback
        if not glyph.renderFallback then
          additions[#additions + 1] = { glyph = glyph, image = job.masks[i] }
        end
      end
    end
  end
  local writes, missing = {}, 0
  for _, cell in ipairs(clipboard.cells) do
    local entry = index.glyphs[cell.glyph]
    local supported = cell.glyph == " "
      or entry and entry.meta.renderFallback ~= "space"
      or resolved[cell.glyph]
    if not supported then
      missing = missing + 1
    end
    writes[#writes + 1] = {
      col = col + cell.col,
      row = row + cell.row,
      glyph = supported and cell.glyph or " ",
      fg = cell.fg,
      bg = cell.bg,
      flags = cell.flags,
    }
  end
  local needsSpace = false
  for _, cell in ipairs(writes) do
    needsSpace = needsSpace or cell.glyph == " "
  end
  Repertoire.budget(
    index.profile,
    #index.order + #additions + (needsSpace and not index.glyphs[" "] and 1 or 0)
  )
  return {
    sprite = sprite,
    layer = layer,
    frame = U.frameNumber(frame),
    id = id,
    geometry = g,
    extent = extent,
    writes = writes,
    additions = additions,
    missing = missing,
    needsSpace = needsSpace,
  }
end

---Commit a prepared paste as one undoable operation.
---@param prepared table Staged paste operations returned by prepare.
function M.apply(prepared)
  local sprite, layer, g, extent =
    prepared.sprite, prepared.layer, prepared.geometry, prepared.extent
  U.check(
    app.sprite == sprite and app.layer == layer and app.frame.frameNumber == prepared.frame,
    "The destination changed; paste again"
  )
  Model.editable(sprite, layer)
  Validate.requireValid(sprite, layer)
  local current = Model.geometry(sprite)
  U.check(
    current.cellWidth == g.cellWidth
      and current.cellHeight == g.cellHeight
      and current.originX == g.originX
      and current.originY == g.originY,
    "The destination grid changed; paste again"
  )
  U.check(
    Model.meta(layer).fontProfileId == prepared.id,
    "The destination font changed; paste again"
  )
  local image, cel, minX, minY = Model.expandTilemapCel(
    sprite,
    layer,
    prepared.frame,
    g,
    extent.firstCol,
    extent.firstRow,
    extent.columns,
    extent.rows
  )
  local ok, problem = pcall(app.transaction, "Paste Asemode Cells", function()
    local index = Profile.index(sprite, prepared.id)
    for _, item in ipairs(prepared.additions) do
      local tile = sprite:newTile(index.masks)
      tile.image = item.image
      Model.setMeta(tile, Repertoire.metadata(item.glyph, tile.image))
    end
    Profile.invalidate()
    if prepared.needsSpace then
      Profile.ensureCharacters(sprite, prepared.id, { " " })
    end
    for _, cell in ipairs(prepared.writes) do
      image:drawPixel(
        cell.col - minX,
        cell.row - minY,
        Profile.orientedTile(sprite, prepared.id, cell.glyph, cell.fg, cell.bg, cell.flags)
      )
    end
    local position = Point(g.originX + minX * g.cellWidth, g.originY + minY * g.cellHeight)
    if cel then
      cel.image = image
      cel.position = position
    else
      sprite:newCel(layer, prepared.frame, image, position)
    end
  end)
  Profile.invalidate()
  if not ok then
    error(problem, 0)
  end
end

return M
