local U = require("src.core.util")
local JSON = require("src.portable.json")
local Codec = require("src.portable.codec")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Loader = require("src.fonts.loader")
local Repertoire = require("src.fonts.repertoire")
local Transforms = require("src.document.transforms")
local M = {}
local Blend = require("src.document.blend")
local PortableStages = require("src.document.portable_stages")

---Replace control and surrogate characters with question marks for safe UI display.
---@param value string Input string.
---@return string safe Sanitized display string.
local function safeLabel(value)
  local result = {}
  for _, cp in utf8.codes(value, true) do
    result[#result + 1] = (cp < 32 or (cp >= 0xd800 and cp <= 0xdfff)) and "?" or utf8.char(cp)
  end
  return table.concat(result)
end

---Capture the destination state used to detect changes during an import.
---@param sprite Sprite? Destination sprite, or nil for a new document.
---@param anchor Layer? Destination layer or group.
---@param frame Frame? Destination frame; defaults to the active frame.
---@return AsemodeImportTarget target Captured import destination.
function M.captureTarget(sprite, anchor, frame)
  if not sprite then
    return { mode = "new" }
  end
  Model.requireEligible(sprite)

  local result = {
    mode = "add",
    sprite = sprite,
    anchor = anchor,
    frame = frame or app.frame,
    width = sprite.width,
    height = sprite.height,
    frameCount = #sprite.frames,
    managed = Model.managed(sprite),
  }
  if result.managed then
    result.geometry = U.copy(Model.geometry(sprite))
  end

  result.ancestors = {}
  local node = anchor
  while node and node ~= sprite do
    result.ancestors[#result.ancestors + 1] = {
      layer = node,
      parent = node.parent,
      index = node.stackIndex,
      visible = node.isVisible,
      editable = node.isEditable,
    }
    node = node.parent
  end

  return result
end

---Reject an import destination that changed since it was captured.
---@param target AsemodeImportTarget Captured destination.
function M.checkTarget(target)
  if target.mode == "new" then
    return
  end
  local sprite = target.sprite
  U.check(
    sprite.isValid and app.sprite == sprite,
    "STALE_IMPORT: destination sprite changed or closed"
  )
  Model.requireEligible(sprite)
  U.check(
    sprite.width == target.width
      and sprite.height == target.height
      and #sprite.frames == target.frameCount
      and app.frame == target.frame
      and sprite.frames[target.frame.frameNumber] == target.frame,
    "STALE_IMPORT: canvas or frame changed"
  )
  U.check(Model.managed(sprite) == target.managed, "STALE_IMPORT: document ownership changed")
  if target.geometry then
    local current = Model.geometry(sprite)
    for _, key in ipairs({ "cellWidth", "cellHeight", "originX", "originY" }) do
      U.check(current[key] == target.geometry[key], "STALE_IMPORT: grid changed")
    end
  end
  for _, previous in ipairs(target.ancestors) do
    local found = false
    local ok, children = pcall(function()
      return previous.parent.layers
    end)
    if ok then
      for _, child in ipairs(children) do
        if child == previous.layer then
          found = true
        end
      end
    end
    U.check(found, "STALE_IMPORT: insertion destination was removed")
    local layer = previous.layer
    U.check(
      layer.parent == previous.parent
        and layer.stackIndex == previous.index
        and layer.isVisible == previous.visible
        and layer.isEditable == previous.editable,
      "STALE_IMPORT: insertion destination changed"
    )
    if layer.isGroup then
      U.check(layer.isVisible and layer.isEditable, "Unlock and show the destination group first")
    end
  end
end

---Convert an RGBA table { r, g, b, a } to a #rrggbbaa hexadecimal string.
---@param value table RGBA color table with r, g, b, a integer components.
---@return string hex Lowercase hexadecimal color.
local function rgba(value)
  return U.hex(value.r, value.g, value.b, value.a)
end

---Record a diagnostic warning code and message onto an import plan.
---@param plan AsemodeImportPlan Import plan.
---@param code string Diagnostic identifier code.
---@param message string Human-readable warning message.
local function diagnostic(plan, code, message)
  plan.diagnostics[#plan.diagnostics + 1] = { code = code, message = message }
end

-- Validate document properties that cannot be fixed in the import options.
-- Keep the portable codec independent of Aseprite's native limitations.
---Check whether a frame duration falls within Aseprite's supported integer range.
---@param duration number Frame duration in milliseconds.
---@return boolean valid True if duration is between 1 and 65535 ms.
local function validDuration(duration)
  local rounded = math.floor(duration + 0.5)
  return duration >= 1 and duration <= 65535 and rounded >= 1 and rounded <= 65535
end

---Construct a structured problem descriptor.
---@param code string Error code.
---@param path string JSON path location.
---@param message string Error description.
---@return table problem Structured error record.
local function problem(code, path, message)
  return { code = code, path = path, message = message }
end

---Format a JSON path string for a frame index.
---@param frameIndex integer 1-based frame index.
---@return string path JSON path string.
local function framePath(frameIndex)
  return "$.frames[" .. (frameIndex - 1) .. "]"
end

---Format a JSON path string for a layer within a frame.
---@param frameIndex integer 1-based frame index.
---@param layerIndex integer 1-based layer index.
---@return string path JSON path string.
local function layerPath(frameIndex, layerIndex)
  return framePath(frameIndex) .. ".layers[" .. (layerIndex - 1) .. "]"
end

---Validate total frame count against native Aseprite limits.
---@param frames table[] List of frames.
---@return table? problem Error record if frame count exceeds 65535.
local function frameCountProblem(frames)
  if #frames > 65535 then
    return problem("LIMIT_EXCEEDED", "$.frames", "Native frame count exceeds 65535")
  end
end

---Validate a single frame's duration against native limits.
---@param frame table Frame record.
---@param frameIndex integer 1-based frame index.
---@return table? problem Error record if duration is invalid.
local function frameProblem(frame, frameIndex)
  if not validDuration(frame.durationMs) then
    return problem(
      "INVALID_DURATION",
      framePath(frameIndex) .. ".durationMs",
      "Aseprite supports 1 to 65535 ms"
    )
  end
end

---Validate layer grid dimensions against native limits.
---@param grid table Grid dimensions { cols, rows }.
---@param frameIndex integer 1-based frame index.
---@param layerIndex integer 1-based layer index.
---@return table? problem Error record if dimensions exceed 4096.
local function gridProblem(grid, frameIndex, layerIndex)
  if grid.cols > 4096 or grid.rows > 4096 then
    return problem(
      "LIMIT_EXCEEDED",
      layerPath(frameIndex, layerIndex) .. ".grid",
      "Native layers support at most 4096 rows and columns"
    )
  end
end

---Validate layer blend mode against supported native modes.
---@param layer table Layer record.
---@param frameIndex integer 1-based frame index.
---@param layerIndex integer 1-based layer index.
---@return table? problem Error record if blend mode is unsupported.
---@return string? mode Resolved native blend mode.
local function blendProblem(layer, frameIndex, layerIndex)
  local ok, mode = pcall(Blend.blend, layer.blendMode)
  if not ok then
    return problem(
      "UNSUPPORTED_BLEND_MODE",
      layerPath(frameIndex, layerIndex) .. ".blendMode",
      "Unsupported blend mode: " .. layer.blendMode
    )
  end
  return nil, mode
end

---Validate a single cell's character and transform flags.
---@param cell table Cell record with character and transform.
---@param frameIndex integer 1-based frame index.
---@param layerIndex integer 1-based layer index.
---@param y integer 1-based row index.
---@param x integer 1-based column index.
---@return table? problem Error record if cell is unsupported.
local function cellProblem(cell, frameIndex, layerIndex, y, x)
  local code, suffix, message
  if not pcall(Repertoire.scalar, cell.character) then
    code, suffix, message =
      "UNSUPPORTED_GLYPH_STRING", ".character", "One Unicode scalar per cell is required"
  elseif cell.transform.invert then
    code, suffix, message =
      "UNSUPPORTED_CELL_TRANSFORM", ".transform.invert", "Cell inversion cannot be preserved"
  else
    return nil
  end
  local path = layerPath(frameIndex, layerIndex)
    .. ".cells.rows["
    .. (y - 1)
    .. "]["
    .. (x - 1)
    .. "]"
    .. suffix
  return problem(code, path, message)
end

---Raise an error with formatted message if an issue is present.
---@param issue table? Structured issue record.
local function requireValid(issue)
  if issue then
    error(Codec.message(issue), 0)
  end
end

-- Validate cells while optionally collecting their characters for preparation.
---Validate cells across rows and optionally collect characters and report progress.
---@param layer table Layer containing cells.rows.
---@param frameIndex integer 1-based frame index.
---@param layerIndex integer 1-based layer index.
---@param onRow? fun(row: integer) Row progress callback.
---@param onCell? fun(cell: table) Cell character callback.
---@return table? issue Validation issue if found.
local function validateNativeRows(layer, frameIndex, layerIndex, onRow, onCell)
  for y, row in ipairs(layer.cells.rows) do
    if onRow then
      onRow(y)
    end
    for x, cell in ipairs(row) do
      local issue = cellProblem(cell, frameIndex, layerIndex, y, x)
      if issue then
        return issue
      end
      if onCell then
        onCell(cell)
      end
    end
  end
end

---Validate a layer's grid, blend mode, and all cell rows.
---@param layer table Layer to validate.
---@param frameIndex integer 1-based frame index.
---@param layerIndex integer 1-based layer index.
---@param onRow? fun(row: integer) Row progress callback.
---@return table? issue Validation issue if found.
local function validateNativeLayer(layer, frameIndex, layerIndex, onRow)
  local issue = gridProblem(layer.grid, frameIndex, layerIndex)
  if not issue then
    issue = blendProblem(layer, frameIndex, layerIndex)
  end
  return issue or validateNativeRows(layer, frameIndex, layerIndex, onRow)
end

---Decode an import and check Aseprite-specific limits.
---@param bytes string Portable document JSON.
---@param options table? Decoder limits and optional checkpoint.
---@return table result Decoded document or structured error.
function M.read(bytes, options)
  local invalidFonts = {}
  local result = Codec.decodeWithFontRecovery(bytes, options, function(id, sourceIndex, name)
    invalidFonts[sourceIndex] = { id = id, name = name }
  end)
  if result.ok and next(invalidFonts) then
    result.invalidFonts = invalidFonts
  end
  if not result.ok then
    return result
  end
  local frames = result.document.frames
  local frameCountIssue = frameCountProblem(frames)
  if frameCountIssue then
    return { ok = false, error = frameCountIssue }
  end
  local totalRows, checkedRows = 0, 0
  for _, frame in ipairs(frames) do
    if type(frame) == "table" and type(frame.layers) == "table" then
      for _, layer in ipairs(frame.layers) do
        if
          type(layer) == "table"
          and type(layer.cells) == "table"
          and type(layer.cells.rows) == "table"
        then
          totalRows = totalRows + #layer.cells.rows
        end
      end
    end
  end
  for frameIndex, frame in ipairs(frames) do
    local issue = frameProblem(frame, frameIndex)
    if issue then
      return { ok = false, error = issue }
    end
    for layerIndex, layer in ipairs(frame.layers) do
      issue = validateNativeLayer(layer, frameIndex, layerIndex, function(y)
        checkedRows = checkedRows + 1
        if options and options.checkpoint then
          options.checkpoint(
            "Checking frame " .. frameIndex .. ", layer " .. layerIndex .. ": row " .. y,
            checkedRows / math.max(1, totalRows)
          )
        end
      end)
      if issue then
        return { ok = false, error = issue }
      end
    end
  end
  return result
end

-- Jobs are supplied by the caller; font choice and protected reads stay outside.
---Prepare import resources without committing them to the destination.
---@param document table Portable document to import.
---@param options table? Preparation options and font jobs.
---@param target AsemodeImportTarget? Captured destination; defaults to a new document.
---@return AsemodeImportPlan plan Prepared import plan.
function M.prepareImport(document, options, target)
  options = options or {}
  target = target or M.captureTarget()
  local decoded = Codec.decodeValue(document, { checkpoint = options.checkpoint })
  U.check(decoded.ok, not decoded.ok and Codec.message(decoded) or "")
  document = decoded.document
  M.checkTarget(target)
  local layers, frameIndexFor, layerIndexFor = {}, {}, {}
  for frameIndex, frame in ipairs(document.frames) do
    for layerIndex, layer in ipairs(frame.layers) do
      layers[#layers + 1], frameIndexFor[#layers + 1], layerIndexFor[#layers + 1] =
        layer, frameIndex, layerIndex
    end
  end
  local first = layers[1] and layers[1].grid
    or { cellWidth = options.cellWidth or 8, cellHeight = options.cellHeight or 8 }
  local g = target.geometry
    or {
      cellWidth = options.cellWidth or first.cellWidth,
      cellHeight = options.cellHeight or first.cellHeight,
      originX = 0,
      originY = 0,
    }
  U.integer(g.cellWidth, "Cell width", 1, 512)
  U.integer(g.cellHeight, "Cell height", 1, 512)
  local plan = {
    target = target,
    geometry = U.copy(g),
    layers = {},
    layerVariants = {},
    fonts = {},
    diagnostics = {},
    bytes = 0,
    verifyResources = options.verifyResources,
    allowClipping = options.allowClipping,
    maxCols = 1,
    maxRows = 1,
    paletteColors = {},
  }
  plan.frames = {}
  requireValid(frameCountProblem(document.frames))
  U.check(
    target.mode ~= "add" or #document.frames == 1 or target.frameCount + #document.frames <= 65535,
    "LIMIT_EXCEEDED: native frame count exceeds 65535"
  )
  for i, frame in ipairs(document.frames) do
    local rounded = math.floor(frame.durationMs + 0.5)
    requireValid(frameProblem(frame, i))
    plan.frames[i] = rounded
  end
  if #layers == 0 then
    plan.maxCols = U.integer(options.blankCols or 1, "Columns", 1, 4096)
    plan.maxRows = U.integer(options.blankRows or 1, "Rows", 1, 4096)
    U.check(
      plan.maxCols * g.cellWidth <= 65535 and plan.maxRows * g.cellHeight <= 65535,
      "Blank canvas exceeds native dimensions"
    )
  end
  local paletteSeen = {}
  ---Add an opaque or semi-transparent color to the staged palette.
  ---@param value table RGBA color table { r, g, b, a }.
  local function addPaletteColor(value)
    if value.a == 0 or #plan.paletteColors >= 256 then
      return
    end
    local color = rgba(value)
    if paletteSeen[color] then
      return
    end
    paletteSeen[color] = true
    plan.paletteColors[#plan.paletteColors + 1] = color
  end
  if #layers == 0 and options.blankJob then
    plan.blankFont = { job = options.blankJob, variants = {}, byKey = {}, glyphs = {} }
    plan.fonts[#plan.fonts + 1] = plan.blankFont
  end
  local fontByJob = {}
  local rotationRounded, missingGlyph, hiddenCells = false, false, false
  local presentationWarnings = {}
  local extent = target.sprite and Model.coverage(target.sprite, g)
  plan.firstCol, plan.firstRow = extent and extent.firstCol or 0, extent and extent.firstRow or 0

  ---Track allocated memory for staged images and check budget limit.
  ---@param bytes integer Number of bytes to reserve.
  local function reserve(bytes)
    plan.bytes = plan.bytes + bytes
    U.check(plan.bytes <= 256 * 1024 * 1024, "LIMIT_EXCEEDED: staged images exceed 256 MiB")
  end

  ---Cooperative checkpoint callback for reporting staging progress.
  ---@param message string Status message.
  ---@param fraction number Progress fraction (0.0 to 1.0).
  local function checkpoint(message, fraction)
    if options.checkpoint then
      options.checkpoint(message, fraction)
    end
  end
  local stages = PortableStages.new({
    loader = Loader,
    profile = Profile,
    transforms = Transforms,
    validateNativeRows = validateNativeRows,
    requireValid = requireValid,
    diagnostic = diagnostic,
  })
  local totalSourceRows =
    stages:collectRepertoire(layers, options, frameIndexFor, layerIndexFor, checkpoint)
  local validatedRows = 0
  for i, layer in ipairs(layers) do
    if not options.selected or options.selected[i] then
      local label = "Frame "
        .. frameIndexFor[i]
        .. ", layer "
        .. layerIndexFor[i]
        .. " ("
        .. safeLabel(layer.id)
        .. ")"
      local grid, job =
        layer.grid,
        U.check(options.jobs and options.jobs[i], "Choose a font for source layer " .. i)
      if options.invalidFonts and options.invalidFonts[i] then
        U.check(
          options.substitutes and options.substitutes[i],
          "FONT_SUBSTITUTE_REQUIRED: choose a font for " .. label
        )
      end
      if
        layer.font
        and (not job.profile.portableFont or layer.font.id ~= job.profile.portableFont.id)
      then
        U.check(
          options.substitutes and options.substitutes[i],
          "FONT_SUBSTITUTE_REQUIRED: choose an explicit substitute for " .. label
        )
      end
      requireValid(gridProblem(grid, frameIndexFor[i], layerIndexFor[i]))
      U.check(
        grid.cols * g.cellWidth <= 65535 and grid.rows * g.cellHeight <= 65535,
        "Imported layer exceeds native pixel dimensions"
      )
      U.check(
        job.profile.cellWidth == g.cellWidth and job.profile.cellHeight == g.cellHeight,
        "Prepared font does not match the common cell size"
      )
      if grid.cellWidth ~= g.cellWidth or grid.cellHeight ~= g.cellHeight then
        presentationWarnings.cellSize = true
      end
      if layer.offsetX ~= 0 or layer.offsetY ~= 0 or layer.rotationZ ~= 0 then
        presentationWarnings.layerPresentation = true
      end
      local opacity = math.floor(layer.opacity * 255 + 0.5)
      if opacity / 255 ~= layer.opacity then
        presentationWarnings.opacity = true
      end
      local blendIssue, mode = blendProblem(layer, frameIndexFor[i], layerIndexFor[i])
      requireValid(blendIssue)
      local font = fontByJob[job]
      if not font then
        font = { job = job, variants = {}, byKey = {}, glyphs = {} }
        fontByJob[job] = font
        plan.fonts[#plan.fonts + 1] = font
        reserve(#job.glyphs * g.cellWidth * g.cellHeight * 4)
        for n, glyph in ipairs(job.glyphs) do
          font.glyphs[glyph.glyphKey] = n
        end
        if job.profile.clippedGlyphs > 0 then
          diagnostic(
            plan,
            "FONT_CLIPPING",
            job.profile.name
              .. ": "
              .. job.profile.clippedGlyphs
              .. " glyph(s) clip. Review the font preview."
          )
        end
      end
      reserve(grid.cols * grid.rows * 4)
      local entry = {
        sourceIndex = i,
        frameIndex = frameIndexFor[i],
        layerIndex = layerIndexFor[i],
        source = layer,
        font = font,
        opacity = opacity,
        blendMode = mode,
        name = safeLabel(layer.id),
        values = {},
      }
      if entry.name ~= layer.id then
        presentationWarnings.layerName = true
      end
      for y, row in ipairs(layer.cells.rows) do
        validatedRows = validatedRows + 1
        checkpoint(
          "Validating " .. label .. ": " .. y .. "/" .. grid.rows,
          0.35 + 0.25 * (validatedRows / math.max(1, totalSourceRows))
        )
        local values = {}
        for x, cell in ipairs(row) do
          local flags = Transforms.portableToNative(cell.transform, g)
          if Transforms.quantizeRotation(cell.transform.rotation) ~= cell.transform.rotation then
            rotationRounded = true
          end
          if job.glyphs[font.glyphs[cell.character]].renderFallback then
            missingGlyph = true
          end
          addPaletteColor(cell.foreground)
          addPaletteColor(cell.background)
          local fg, bg = rgba(cell.foreground), rgba(cell.background)
          local orientation = flags
          local key = U.key(cell.character, fg, bg, orientation)
          local index = font.byKey[key]
          if not index then
            reserve(g.cellWidth * g.cellHeight * 4)
            local countOk, bytesOk =
              Profile.checkVariantBudget(#font.variants, g.cellWidth, g.cellHeight)
            U.check(countOk and bytesOk, "LIMIT_EXCEEDED: paint tiles exceed the profile budget")
            index = #font.variants + 1
            font.byKey[key] = index
            font.variants[index] = {
              glyphKey = cell.character,
              foregroundRGBA = fg,
              backgroundRGBA = bg,
              orientation = orientation,
            }
          end
          values[x] = app.pixelColor.tile(index, 0)
          if extent and (x > extent.columns or y > extent.rows) then
            hiddenCells = true
          end
        end
        entry.values[y] = values
      end
      plan.layers[#plan.layers + 1] = entry
      plan.maxCols, plan.maxRows =
        math.max(plan.maxCols, grid.cols), math.max(plan.maxRows, grid.rows)
    end
  end
  if presentationWarnings.cellSize then
    diagnostic(
      plan,
      "CELL_METRICS_CHANGED",
      "Some source cell sizes differ from the selected cell size."
    )
  end
  if presentationWarnings.layerPresentation then
    diagnostic(
      plan,
      "LAYER_PRESENTATION_DISCARDED",
      "Some layer offsets or rotations will be discarded."
    )
  end
  if presentationWarnings.opacity then
    diagnostic(
      plan,
      "OPACITY_QUANTIZED",
      "Some opacity values will be rounded to the nearest 1/255."
    )
  end
  if presentationWarnings.layerName then
    diagnostic(
      plan,
      "LAYER_LABEL_CHANGED",
      "Unsupported characters in some layer names will be replaced with '?'."
    )
  end
  if hiddenCells then
    diagnostic(
      plan,
      "HIDDEN_IMPORTED_CELLS",
      "Some imported cells are outside the canvas and are not visible."
    )
  end
  if missingGlyph then
    diagnostic(
      plan,
      "MISSING_GLYPHS_AS_SPACES",
      "Some characters are unavailable in the selected fonts and appear as spaces."
    )
  end
  if rotationRounded then
    diagnostic(plan, "CELL_ROTATION_ROUNDED", "Cell rotations were rounded to the nearest 90°.")
  end
  U.check(#plan.layers > 0 or #layers == 0, "Choose at least one source layer")
  stages:buildSplitLayerGroups(plan, target)
  stages:renderStagedTilemaps(plan, totalSourceRows, checkpoint)
  M.checkTarget(target)
  return plan
end

---Create native tilemap layers in the document for staged layer variants.
---@param plan AsemodeImportPlan Staged import plan.
---@param sprite Sprite Destination document.
---@param ids table Map from font descriptor to installed profile ID.
---@param parent Layer|Sprite Parent group or root sprite.
---@param insertion integer Target stacking index.
---@return Layer[] imported Created native layers.
---@return table nativeVariants Map from variant group to created layer.
local function createImportLayers(plan, sprite, ids, parent, insertion)
  local imported, nativeVariants = {}, {}
  for _, group in ipairs(plan.layerVariants) do
    local entry = group.first
    local layer = Model.addLayer(sprite, ids[group.font], group.blank and "Textmode" or entry.name)
    layer.parent = parent
    layer.stackIndex = insertion
    insertion = insertion + 1
    if entry then
      layer.opacity, layer.blendMode, layer.isVisible =
        #plan.frames == 1 and entry.opacity or 255,
        entry.blendMode,
        #plan.frames > 1 or entry.source.visible
      local metadata = Model.meta(layer)
      metadata.portableLayerIdJson = JSON.stringify(entry.source.id, { pretty = false })
      Model.setMeta(layer, metadata)
    end
    nativeVariants[group] = layer
    imported[#imported + 1] = layer
  end
  return imported, nativeVariants
end

---Create tilemap cels on native layers from staged tilemap images.
---@param plan AsemodeImportPlan Staged import plan.
---@param sprite Sprite Destination document.
---@param firstFrame integer 1-based first target frame number.
---@param imported Layer[] Created native layers.
---@param nativeVariants table Map from variant group to created layer.
local function createImportCels(plan, sprite, firstFrame, imported, nativeVariants)
  local byFrame = {}
  for _, entry in ipairs(plan.layers) do
    local layer = nativeVariants[entry.variant]
    local frameNumber = firstFrame + entry.frameIndex - 1
    U.check(
      not layer:cel(frameNumber),
      "Duplicate native layer variant in frame " .. entry.frameIndex
    )
    local cel = sprite:newCel(
      layer,
      frameNumber,
      entry.image,
      Point(
        plan.geometry.originX + plan.firstCol * plan.geometry.cellWidth,
        plan.geometry.originY + plan.firstRow * plan.geometry.cellHeight
      )
    )
    cel.opacity = #plan.frames == 1 and 255 or (entry.source.visible and entry.opacity or 0)
    if #plan.frames > 1 then
      Model.setMeta(
        cel,
        { portableHidden = not entry.source.visible, portableOpacity = entry.opacity }
      )
    end
    byFrame[frameNumber] = byFrame[frameNumber] or {}
    byFrame[frameNumber][#byFrame[frameNumber] + 1] = { cel = cel, layer = layer }
  end
  local positions = {}
  for rank, layer in ipairs(imported) do
    positions[tostring(layer.uuid)] = rank
  end
  for _, entries in pairs(byFrame) do
    local slots = {}
    for _, entry in ipairs(entries) do
      slots[#slots + 1] = positions[tostring(entry.layer.uuid)]
    end
    table.sort(slots)
    for i, entry in ipairs(entries) do
      local offset = slots[i] - positions[tostring(entry.layer.uuid)]
      U.check(
        offset >= -32768 and offset <= 32767,
        "UNSUPPORTED_LAYER_ORDER: cel z-index exceeds Aseprite range"
      )
      entry.cel.zIndex = offset
    end
  end
end

---Commit a prepared import after rechecking its destination and resources.
---@param plan AsemodeImportPlan Prepared import; cannot be committed twice.
---@param consent table? User approvals, including font clipping.
---@return table result Destination sprite and imported layers.
function M.commitImport(plan, consent)
  consent = consent or {}
  U.check(not plan.committed, "This import was already committed")
  M.checkTarget(plan.target)
  for _, font in ipairs(plan.fonts) do
    U.check(
      font.job.profile.clippedGlyphs == 0 or consent.allowClipping,
      "Confirm the font clipping preview first"
    )
  end
  if plan.verifyResources then
    plan.verifyResources()
  end
  local previousSprite, previousLayer = app.sprite, app.layer
  local target, created = plan.target, plan.target.mode == "new"
  local sprite = target.sprite
  -- Avoid allocating a canvas-sized temporary raster before creating tilemaps.
  if created then
    sprite = Sprite(1, 1, ColorMode.RGB)
  end
  local imported, active = {}, nil
  local ok, err = pcall(function()
    app.sprite = sprite
    if target.anchor then
      app.layer = target.anchor
    end
    app.transaction("Import Textmode JSON", function()
      if created then
        sprite.width, sprite.height =
          plan.maxCols * plan.geometry.cellWidth, plan.maxRows * plan.geometry.cellHeight
        if #plan.paletteColors > 0 then
          local palette = Palette(#plan.paletteColors)
          for index, value in ipairs(plan.paletteColors) do
            palette:setColor(index - 1, Color(U.rgba(value)))
          end
          sprite:setPalette(palette)
        elseif app.defaultPalette then
          sprite:setPalette(app.defaultPalette)
        end
      end
      Model.initialize(sprite, plan.geometry.cellWidth, plan.geometry.cellHeight)
      if created then
        sprite.gridBounds = Rectangle(0, 0, plan.geometry.cellWidth, plan.geometry.cellHeight)
      end
      local original = created and sprite.layers[1]
      local ids = {}
      for _, font in ipairs(plan.fonts) do
        ids[font] = Profile.install(sprite, font.job, consent.allowClipping, font.variants)
      end
      local parent = target.anchor
          and (target.anchor.isGroup and target.anchor or target.anchor.parent)
        or sprite
      local insertion = target.anchor and not target.anchor.isGroup and target.anchor.stackIndex + 1
        or #parent.layers + 1
      local firstFrame = created and 1
        or (#plan.frames > 1 and (#sprite.frames + 1) or target.frame.frameNumber)
      if created or #plan.frames > 1 then
        for frameIndex, duration in ipairs(plan.frames) do
          local frameNumber = firstFrame + frameIndex - 1
          if frameNumber > #sprite.frames then
            sprite:newEmptyFrame(frameNumber)
          end
          sprite.frames[frameNumber].duration = duration / 1000
        end
      end
      local nativeVariants
      imported, nativeVariants = createImportLayers(plan, sprite, ids, parent, insertion)
      createImportCels(plan, sprite, firstFrame, imported, nativeVariants)
      active = imported[#imported]
      for i = #imported, 1, -1 do
        if imported[i].isVisible then
          active = imported[i]
          break
        end
      end
      if consent.stamps and active then
        local id = Model.meta(active).fontProfileId
        local index = Profile.index(sprite, id)
        local primary, secondary = Profile.defaultStamps(index)
        Profile.variant(
          sprite,
          id,
          primary,
          consent.stamps.foregroundRGBA,
          consent.stamps.backgroundRGBA
        )
        Profile.variant(
          sprite,
          id,
          secondary,
          consent.stamps.foregroundRGBA,
          consent.stamps.backgroundRGBA
        )
      end
      if original and active then
        sprite:deleteLayer(original)
      end
    end)
  end)
  Profile.invalidate()
  if not ok then
    if created then
      sprite:close()
    end
    if previousSprite and previousSprite.isValid then
      app.sprite = previousSprite
      app.layer = previousLayer
    end
    error(err, 0)
  end
  plan.committed = true
  if active then
    app.layer = active
  end
  return { sprite = sprite, layers = imported }
end

return M
