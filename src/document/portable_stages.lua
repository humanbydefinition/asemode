local U = require("src.core.util")
local M = {}

---Create import staging operations with explicit domain dependencies.
---@param deps table Domain module dependencies.
---@return table stages Staging pipeline stages.
function M.new(deps)
  local stages = {}

  ---Gather glyph repertoire across import layers and validate native row constraints.
  ---@param layers table[] Selected layers from the portable document.
  ---@param options table Import options containing jobs and selection flags.
  ---@param frameIndexFor table Map from layer index to frame index.
  ---@param layerIndexFor table Map from layer index to layer index within frame.
  ---@param checkpoint fun(message: string, fraction: number) Progress callback.
  ---@return integer totalSourceRows Total number of rows across selected layers.
  function stages:collectRepertoire(layers, options, frameIndexFor, layerIndexFor, checkpoint)
    -- Gather the union before rendering shared jobs, including invisible semantic cells.
    local required, totalSourceRows, checkedSourceRows = {}, 0, 0
    for i, layer in ipairs(layers) do
      if not options.selected or options.selected[i] then
        totalSourceRows = totalSourceRows + #layer.cells.rows
      end
    end
    for i, layer in ipairs(layers) do
      if not options.selected or options.selected[i] then
        local job =
          U.check(options.jobs and options.jobs[i], "Choose a font for source layer " .. i)
        local keys = required[job] or {}
        required[job] = keys
        local issue = deps.validateNativeRows(layer, frameIndexFor[i], layerIndexFor[i], function(y)
          checkedSourceRows = checkedSourceRows + 1
          checkpoint(
            "Scanning layer " .. i .. ": row " .. y,
            0.15 + 0.2 * (checkedSourceRows / math.max(1, totalSourceRows))
          )
        end, function(cell)
          keys[cell.character] = true
        end)
        deps.requireValid(issue)
      end
    end
    for job, keys in pairs(required) do
      local list = {}
      for key in pairs(keys) do
        list[#list + 1] = key
      end
      deps.loader.ensureCharacters(job, list)
    end
    return totalSourceRows
  end

  ---Build native layer groups in first-appearance order, splitting on font or blend changes.
  ---@param plan AsemodeImportPlan Staged import plan to update.
  ---@param target AsemodeImportTarget Import target descriptor.
  function stages:buildSplitLayerGroups(plan, target)
    -- Build native layer groups in first-appearance order. Entries remain in
    -- source order so per-frame stacking is preserved when cels are created.
    local groupsById, split = {}, false
    for _, entry in ipairs(plan.layers) do
      local source = groupsById[entry.source.id]
      if not source then
        source = { fonts = {}, count = 0 }
        groupsById[entry.source.id] = source
      end
      local byBlend = source.fonts[entry.font]
      if not byBlend then
        byBlend = {}
        source.fonts[entry.font] = byBlend
      end
      local group = byBlend[entry.blendMode]
      if not group then
        if source.count > 0 then
          split = true
        end
        source.count = source.count + 1
        group = { font = entry.font, first = entry, entries = {} }
        byBlend[entry.blendMode] = group
        plan.layerVariants[#plan.layerVariants + 1] = group
      end
      group.entries[#group.entries + 1] = entry
      entry.variant = group
    end
    if #plan.layerVariants == 0 and plan.blankFont then
      plan.layerVariants[1] = { font = plan.blankFont, entries = {}, blank = true }
    end
    plan.layerVariantsSplit = split
    if plan.layerVariantsSplit then
      deps.diagnostic(
        plan,
        "LAYER_VARIANTS",
        "Some source layers were split to preserve font or blend changes."
      )
    end
    if target.mode == "new" then
      U.check(
        plan.maxCols * plan.maxRows <= 4000000,
        "LIMIT_EXCEEDED: the combined canvas exceeds the visible cell budget"
      )
    end
  end

  ---Rasterize font glyph masks and colorize paint variant tiles for staged layers.
  ---@param plan AsemodeImportPlan Staged import plan containing fonts and layer entries.
  ---@param totalSourceRows integer Total source rows for progress reporting.
  ---@param checkpoint fun(message: string, fraction: number) Progress callback.
  function stages:renderStagedTilemaps(plan, totalSourceRows, checkpoint)
    local totalMaskSteps, doneMaskSteps = 0, 0
    for _, font in ipairs(plan.fonts) do
      totalMaskSteps = totalMaskSteps + #font.job.glyphs + #font.variants
    end
    for _, font in ipairs(plan.fonts) do
      local before = font.job.position
      while font.job.position < #font.job.glyphs do
        font.job:step(8)
        checkpoint(
          "Rasterizing " .. font.job.profile.name .. "...",
          0.6 + 0.25 * ((doneMaskSteps + font.job.position) / math.max(1, totalMaskSteps))
        )
      end
      doneMaskSteps = doneMaskSteps + math.max(before, #font.job.glyphs)
      for _, variant in ipairs(font.variants) do
        local mask = font.job.masks[font.glyphs[variant.glyphKey]]
        if variant.orientation ~= 0 then
          mask = deps.transforms.renderMask(mask, variant.orientation, checkpoint)
        end
        variant.image =
          deps.profile.colorize(mask, variant.foregroundRGBA, variant.backgroundRGBA, checkpoint)
        doneMaskSteps = doneMaskSteps + 1
        checkpoint(
          "Colorizing cells...",
          0.6 + 0.25 * (doneMaskSteps / math.max(1, totalMaskSteps))
        )
      end
    end
    local preparedRows = 0
    for _, entry in ipairs(plan.layers) do
      local grid = entry.source.grid
      entry.image = Image(grid.cols, grid.rows, ColorMode.TILEMAP)
      for y, row in ipairs(entry.values) do
        for x, value in pairs(row) do
          entry.image:drawPixel(x - 1, y - 1, value)
        end
        preparedRows = preparedRows + 1
        checkpoint(
          "Building " .. entry.name .. ": row " .. y,
          0.85 + 0.15 * (preparedRows / math.max(1, totalSourceRows))
        )
      end
      entry.values = nil
    end
  end

  return stages
end

return M
