local U = require("src.core.util")
local JSON = require("src.portable.json")
local Codec = require("src.portable.codec")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Loader = require("src.fonts.loader")
local Snapshot = require("src.document.snapshot")
local Validate = require("src.document.validate")
local Transforms = require("src.document.transforms")
local version = require("src.core.version")
local M = {}
local Blend = require("src.document.blend")
---Export selected Asemode layers and frames as portable document JSON.
---@param sprite Sprite Source document.
---@param layer Layer? Selected source layer.
---@param frame Frame|integer Source frame or frame number.
---@param options table? Export selection, limits, and checkpoint options.
---@return table result Document, JSON text, and export warnings.
function M.export(sprite, layer, frame, options)
  options = options or {}
  local layers, excluded = {}, {}
  local selectedId = layer and Model.meta(layer).portableLayerIdJson
  for _, candidate in ipairs(Model.layers(sprite)) do
    if
      options.target == "all"
      or candidate == layer
      or (selectedId and Model.meta(candidate).portableLayerIdJson == selectedId)
    then
      U.check(
        Model.meta(candidate).schemaVersion ~= 1 or candidate.isTilemap,
        "Text layer is no longer a tilemap: "
          .. candidate.name
          .. ". Try undoing the conversion or restoring an earlier .aseprite file."
      )
      if Model.layerManaged(candidate) then
        layers[#layers + 1] = candidate
      else
        excluded[#excluded + 1] = candidate.name
      end
    end
  end
  U.check(#layers > 0, "No Asemode layers are available for export")
  local result = { format = Codec.format, formatVersion = Codec.version, frames = JSON.array() }
  local frameNumbers = {}
  if options.frames == "all" then
    for i = 1, #sprite.frames do
      frameNumbers[#frameNumbers + 1] = i
    end
  else
    frameNumbers[1] = U.frameNumber(frame)
  end
  U.check(#frameNumbers <= 65536, "LIMIT_EXCEEDED: too many frames")
  local geometry = U.copy(Model.geometry(sprite))
  local extent = Model.coverage(sprite, geometry)
  local context = Validate.exportContext(sprite)
  local totalLayers, totalCells = 0, 0
  local minLayers, maxLayers, included, includedCount, singleName = nil, 0, {}, 0, nil
  for _, frameNumber in ipairs(frameNumbers) do
    local count = 0
    for _, source in ipairs(layers) do
      if source:cel(frameNumber) then
        count = count + 1
        local id = tostring(source.uuid)
        if not included[id] then
          included[id] = true
          includedCount = includedCount + 1
          singleName = source.name
        end
      end
    end
    minLayers = math.min(minLayers or count, count)
    maxLayers = math.max(maxLayers, count)
    U.check(count <= 256, "LIMIT_EXCEEDED: too many layers in frame " .. frameNumber)
    totalLayers = totalLayers + count
    totalCells = totalCells + count * extent.columns * extent.rows
    U.check(
      totalLayers <= 65536 and totalCells <= 4000000,
      "LIMIT_EXCEEDED: document layer or cell budget exceeded"
    )
  end
  local outside, partial = 0, false
  local totalRows, exportedRows = totalLayers * extent.rows, 0
  result.metadata = {
    createdAt = options.createdAt or os.date("!%Y-%m-%dT%H:%M:%SZ"),
    generator = { name = "Asemode", version = options.generatorVersion or version },
  }
  -- Groups occupy stacking positions even though they are not exported.
  -- Rank once for all frames, including groups, before applying cel z-index.
  local ranks, order = {}, 0
  ---Recursively assign sequential stacking ranks to all leaf layers and groups.
  ---@param items Layer[] Layer hierarchy to traverse.
  local function rankLayers(items)
    for _, item in ipairs(items) do
      order = order + 1
      if item.isGroup then
        rankLayers(item.layers)
      else
        ranks[tostring(item.uuid)] = order
      end
    end
  end
  rankLayers(sprite.layers)
  for _, frameNumber in ipairs(frameNumbers) do
    local present = {}
    for _, source in ipairs(layers) do
      if source:cel(frameNumber) then
        present[#present + 1] = source
      end
    end
    local snapshot = Snapshot.capture(
      sprite,
      present,
      frameNumber,
      { checkpoint = options.checkpoint, context = context, geometry = geometry, extent = extent }
    )
    outside, partial = outside + snapshot.outside, partial or snapshot.extent.partial
    local g, extent = snapshot.geometry, snapshot.extent
    table.sort(snapshot.layers, function(a, b)
      local az, bz = a.cel and a.cel.zIndex or 0, b.cel and b.cel.zIndex or 0
      local ai, bi = ranks[tostring(a.layer.uuid)] + az, ranks[tostring(b.layer.uuid)] + bz
      return ai < bi or (ai == bi and az < bz)
    end)
    local duration = math.floor(sprite.frames[frameNumber].duration * 1000 + 0.5)
    U.check(
      duration >= 1 and duration <= 65535,
      "INVALID_DURATION: frame " .. frameNumber .. " has unsupported timing"
    )
    local outputFrame = { durationMs = duration, layers = JSON.array() }
    result.frames[#result.frames + 1] = outputFrame
    local seenIds = {}
    for _, entry in ipairs(snapshot.layers) do
      if entry.cel then
        local source, cel = entry.layer, entry.cel

        local metadata = Model.meta(source)
        local layerId = metadata.portableLayerIdJson and JSON.parse(metadata.portableLayerIdJson)
          or tostring(source.uuid)
        U.check(
          not seenIds[layerId],
          "Conflicting layer variants in frame " .. frameNumber .. ": " .. layerId
        )
        seenIds[layerId] = true
        local celMetadata = Model.meta(cel)
        local hidden = celMetadata.portableHidden and cel.opacity == 0
        local visible, parent = source.isVisible and not hidden, source.parent
        while parent and parent ~= sprite do
          U.check(
            parent.opacity == nil and parent.blendMode == nil,
            "Compositing groups cannot be represented by flat portable layers: " .. parent.name
          )
          visible = visible and parent.isVisible
          parent = parent.parent
        end
        -- MUL_UN8, used by Aseprite to combine cel and layer opacity.
        local alpha = source.opacity
            * (hidden and (celMetadata.portableOpacity or 0) or (cel and cel.opacity or 255))
          + 128
        alpha = ((alpha >> 8) + alpha) >> 8
        local output = {
          id = layerId,
          visible = visible,
          opacity = alpha / 255,
          blendMode = Blend.blendName(source.blendMode),
          offsetX = 0,
          offsetY = 0,
          rotationZ = 0,
          grid = {
            cols = extent.columns,
            rows = extent.rows,
            cellWidth = g.cellWidth,
            cellHeight = g.cellHeight,
          },
          cells = { encoding = "object-rows-v1", rows = JSON.array() },
        }
        local profile = Profile.index(sprite, Model.meta(source).fontProfileId).profile
        local reference = Loader.reference(profile, options.resolveFont, options.checkpoint)
        if reference then
          output.font = U.copy(reference)
        end
        for y = 1, extent.rows do
          exportedRows = exportedRows + 1
          if options.checkpoint then
            options.checkpoint(
              "Exporting " .. source.name .. ": row " .. y,
              exportedRows / math.max(1, totalRows)
            )
          end
          local row = JSON.array()
          for x = 1, extent.columns do
            local cell = entry.rows[y][x]
            row[x] = {
              x = x - 1,
              y = y - 1,
              character = cell and cell.meta.glyphKey or " ",
              foreground = cell and cell.meta.foregroundRGBA or "#00000000",
              background = cell and cell.meta.backgroundRGBA or "#00000000",
              transform = cell and Transforms.nativeToPortable(cell.flags, g)
                or { invert = false, flipX = false, flipY = false, rotation = 0 },
            }
          end
          output.cells.rows[y] = row
        end
        outputFrame.layers[#outputFrame.layers + 1] = output
      end
    end
  end
  local encodeOptions = U.copy(options)
  encodeOptions.pretty = true
  local encoded = Codec.encode(result, encodeOptions)
  U.check(encoded.ok, not encoded.ok and Codec.message(encoded) or "")
  return {
    document = result,
    text = encoded.text,
    outside = outside,
    excluded = excluded,
    partial = partial,
    review = {
      minLayers = minLayers or 0,
      maxLayers = maxLayers,
      layerName = includedCount == 1 and singleName or nil,
    },
  }
end
return M
