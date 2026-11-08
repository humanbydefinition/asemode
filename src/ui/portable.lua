local U = require("src.core.util")
local Codec = require("src.portable.codec")
local PortableImport = require("src.document.portable_import")
local PortableExport = require("src.document.portable_export")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Task = require("src.core.task")
local ImportLayerPager = require("src.ui.import_layer_pager")
local M = {}

---Append wrapped message labels to a dialog to prevent wide text overflows.
---@param dialog Dialog Destination dialog.
---@param message string Message string to format.
local function labels(dialog, message)
  -- Native labels do not wrap. Keep the review readable on small displays.
  local chars, line = U.characters(message), {}
  for _, char in ipairs(chars) do
    line[#line + 1] = char
    if #line == 88 then
      dialog:label({ text = table.concat(line) }):newrow()
      line = {}
    end
  end
  if #line > 0 then
    dialog:label({ text = table.concat(line) }):newrow()
  end
end

---Sanitize text for display in native dialog labels and truncate if needed.
---@param text string Raw string.
---@param maxChars integer Maximum character length.
---@return string? sanitized Cleaned and clamped string, or nil if invalid UTF-8.
local function sanitizeLabel(text, maxChars)
  local clean = text:gsub("[%z\1-\31]", "?")
  if not utf8.len(clean) then
    return nil
  end
  local chars = U.characters(clean)
  return #chars > maxChars and table.concat(chars, "", 1, maxChars) .. "…" or clean
end

---Render a warning icon canvas and label row inside a dialog.
---@param dialog Dialog Destination dialog.
---@param message string Warning message text.
local function warningLabel(dialog, message)
  dialog
    :canvas({
      width = 12,
      height = 12,
      hexpand = false,
      vexpand = false,
      autoscaling = true,
      onpaint = function(ev)
        local gc = ev.context
        gc.color = gc.theme.color.window_face
        gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
        gc.color = gc.theme.color.text
        for y = 0, 9 do
          local half = y // 2
          gc:fillRect(Rectangle(5 - half, y + 1, 1 + half * 2, 1))
        end
        gc.color = gc.theme.color.window_face
        gc:fillRect(Rectangle(5, 4, 1, 3))
        gc:fillRect(Rectangle(5, 8, 1, 1))
      end,
    })
    :samerow()
    :label({ text = message })
    :newrow()
end

---Create the portable import and export UI workflow.
---@param deps table Dialog, task, library, and drawing dependencies.
---@return table workflow Portable document workflow.
function M.new(deps)
  local self = { tasks = deps.tasks, library = deps.library, drawing = deps.drawing }
  ---Run a background task for portable import/export with progress reporting.
  ---@param title string Task display title.
  ---@param run fun(checkpoint: fun(msg: string, frac: number)): any Task execution callback.
  ---@param complete fun(result: any) Completion callback.
  ---@param onCancel? fun() Cancellation callback.
  ---@param onError? fun(err: any) Error handler callback.
  ---@param cleanup? fun() Final cleanup callback.
  ---@return (fun())? cancel Cancellation trigger closure, or nil if UI unavailable.
  local function runPortableTask(title, run, complete, onCancel, onError, cleanup)
    self.drawing:flush()
    self.drawing:flushDeferred(app.sprite)
    local handle = self.tasks:start(Task.new(run), {
      title = title,
      blocksDrawing = true,
      complete = complete,
      cancel = onCancel,
      error = onError,
      cleanup = cleanup,
    })
    if not app.isUIAvailable then
      return nil
    end
    return function()
      handle:cancel()
    end
  end

  ---Show the import review dialog with summary statistics and diagnostic warnings.
  ---@param plan table Prepared import plan.
  ---@param warnings table[] List of warning records.
  local function reviewPortableImport(plan, warnings)
    local d = deps.dialog("Review Textmode Import")
    d:label({
      label = "Target:",
      text = plan.target.mode == "new" and "New textmode sprite" or "Current sprite",
    }):newrow()
    d:label({ label = "Frames:", text = tostring(#plan.frames) }):newrow()
    d:label({ label = "Layers:", text = tostring(#plan.layerVariants) }):newrow()
    d:label({ label = "Grid:", text = plan.maxCols .. " × " .. plan.maxRows .. " cells" }):newrow()
    d:label({
      label = "Cell size:",
      text = plan.geometry.cellWidth .. " × " .. plan.geometry.cellHeight .. " px",
    }):newrow()
    local fontNames = {}
    for _, font in ipairs(plan.fonts) do
      fontNames[#fontNames + 1] = font.job.profile.name
    end
    if #fontNames > 0 then
      d:label({ label = "Fonts:", text = table.concat(fontNames, ", ") }):newrow()
    end
    for _, warning in ipairs(warnings or {}) do
      labels(d, warning.message)
    end
    for _, item in ipairs(plan.diagnostics) do
      if
        item.code == "FONT_CLIPPING"
        or item.code == "CELL_ROTATION_ROUNDED"
        or item.code == "LAYER_VARIANTS"
        or item.code == "MISSING_GLYPHS_AS_SPACES"
        or item.code == "CELL_METRICS_CHANGED"
        or item.code == "LAYER_PRESENTATION_DISCARDED"
        or item.code == "OPACITY_QUANTIZED"
        or item.code == "LAYER_LABEL_CHANGED"
        or item.code == "HIDDEN_IMPORTED_CELLS"
      then
        warningLabel(
          d,
          item.code == "FONT_CLIPPING"
              and "Some glyphs may be clipped by the selected cell size. Review the font preview."
            or item.message
        )
      else
        labels(d, item.message)
      end
    end
    for _, font in ipairs(plan.fonts) do
      if font.job.profile.clippedGlyphs > 0 then
        d:button({
          text = "Preview <" .. font.job.profile.name .. ">...",
          onclick = function()
            deps.font:preview(font.job, function() end, plan.target.sprite)
          end,
        }):newrow()
      end
    end
    d
      :button({
        text = "Import",
        focus = true,
        onclick = deps.guard(function()
          local drawing = self.drawing:snapshot()
          ---Execute the prepared import plan within an optional suppression context.
          ---@return table result Committed import result.
          local function commit()
            return PortableImport.commitImport(plan, {
              allowClipping = true,
              stamps = plan.target.mode == "new" and {
                foregroundRGBA = drawing.fg,
                backgroundRGBA = drawing.bg,
              } or nil,
            })
          end
          local result = plan.target.mode == "new" and self.drawing:withSuppression(commit)
            or commit()
          if #result.layers == 0 then
            d:close()
            return
          end
          local index = Profile.index(result.sprite, Model.meta(app.layer).fontProfileId)
          local primary, secondary = Profile.defaultStamps(index)
          if plan.target.mode ~= "new" then
            secondary = primary
          end
          if plan.target.mode ~= "new" then
            self.drawing:setImportedStamps(primary, secondary, {
              destination = "existing",
              paintCount = #index.paint,
            })
          end
          d:close()
          deps.positionPanel()
          deps.openPanel()
          if plan.target.mode == "new" then
            self.drawing:setColors(nil, drawing.fg, drawing.bg)
            self.drawing:setImportedStamps(primary, secondary, { destination = "new" })
            self.drawing:prepareBoth()
          end
        end),
      })
      :button({
        text = "Cancel",
        onclick = function()
          d:close()
        end,
      })
      :show({ wait = false, autoscrollbars = true })
  end

  ---Display an import error or issue modal with an action to return to options.
  ---@param message string Problem description message.
  local function portableImportProblem(message)
    local d = deps.dialog("Import needs changes")
    for line in (message .. "\n"):gmatch("([^\n]*)\n") do
      labels(d, line)
    end
    d:button({
      text = "Back to options",
      focus = true,
      onclick = function()
        d:close()
      end,
    }):show({ wait = false, autoscrollbars = true })
  end

  ---Show the configuration dialog for selecting import target and font mappings.
  ---@param document table Decoded portable document.
  ---@param warnings table[] Document warning entries.
  ---@param invalidFonts? table<integer, boolean> Map of invalid font indices.
  ---@param resolvedCatalog? table[] Pre-resolved font catalog.
  local function portableImportOptions(document, warnings, invalidFonts, resolvedCatalog)
    if not resolvedCatalog then
      runPortableTask("Match document fonts", function(checkpoint)
        local catalog = self.library:catalog()
        local total = math.max(1, #catalog)
        for index, font in ipairs(catalog) do
          local base = (index - 1) / total
          local nextFrac = index / total
          checkpoint("Matching " .. font.name .. "...", (base + nextFrac) * 0.5)
          local ok, reference = pcall(function()
            return self.library:portableReference(font, function(msg, subFrac)
              checkpoint(msg, base + (subFrac or 0.5) / total)
            end)
          end)
          if ok then
            font.portableFont = reference
          end
          checkpoint("Matching " .. font.name .. "...", nextFrac)
        end
        return catalog
      end, function(catalog)
        portableImportOptions(document, warnings, invalidFonts, catalog)
      end)
      return
    end
    local pending, closed
    local d = deps.dialog("Import Textmode Layers", {
      onclose = function()
        closed = true
        if pending then
          pending()
        end
      end,
    })
    local controls = {
      "destination",
      "font",
      "size",
      "sizeIncrease",
      "sizeDecrease",
      "width",
      "widthIncrease",
      "widthDecrease",
      "height",
      "heightIncrease",
      "heightDecrease",
      "prepare",
    }
    local controlsReady, updatePrepare, updatePage = false, nil, nil
    local fixedGeometry, savedWidth, savedHeight, syncing = false, nil, nil, false
    ---Enable or disable interactive form controls during background operations.
    ---@param value boolean Enabled state.
    local function enable(value)
      if not closed then
        for _, id in ipairs(controls) do
          d:modify({ id = id, enabled = value })
        end
        if value and updatePage then
          updatePage()
        end
        if value and updatePrepare then
          updatePrepare()
        end
      end
    end
    local catalog, labelsByFont, fontsByLabel = resolvedCatalog, {}, {}
    for _, font in ipairs(catalog) do
      labelsByFont[#labelsByFont + 1] = font.label
      fontsByLabel[font.label] = font
    end
    local layers, sourceLabels = {}, {}
    for frameIndex, frame in ipairs(document.frames) do
      for layerIndex, layer in ipairs(frame.layers) do
        layers[#layers + 1] = layer
        sourceLabels[#sourceLabels + 1] = "Frame " .. frameIndex .. ", layer " .. layerIndex
      end
    end
    local first = layers[1] and layers[1].grid or { cellWidth = 8, cellHeight = 8 }
    local matches = {}
    for i, layer in ipairs(layers) do
      if layer.font then
        for _, font in ipairs(catalog) do
          if font.portableFont and font.portableFont.id == layer.font.id then
            matches[i] = font.label
            break
          end
        end
      end
    end
    invalidFonts = invalidFonts or {}
    local pageSize = 2
    local pages = math.max(1, math.ceil(#layers / pageSize))
    local layerState = {}
    for i = 1, #layers do
      layerState[i] = {
        selected = true,
        font = invalidFonts[i] and "Choose a font" or matches[i] or "Use default font",
      }
    end
    local overrides, recoveryOverrides = { "Use default font" }, { "Choose a font" }
    for _, label in ipairs(labelsByFont) do
      overrides[#overrides + 1] = label
      recoveryOverrides[#recoveryOverrides + 1] = label
    end
    updatePrepare = function()
      if not controlsReady or closed or syncing then
        return false
      end
      local data, selected, valid, missingFont = d.data, {}, true, false
      for i, layer in ipairs(layers) do
        if layerState[i].selected then
          selected[#selected + 1] = i
          local chosen = layerState[i].font
          local label = chosen == "Use default font" and data.font or chosen
          if not fontsByLabel[label] or (invalidFonts[i] and chosen == "Use default font") then
            valid, missingFont = false, true
          end
        end
      end
      if pages > 1 then
        d:modify({ id = "fontChoicesNotice", visible = missingFont })
      end
      if #selected == 0 and #layers > 0 then
        valid = false
      end
      local size = data.size
      if type(size) ~= "number" or size ~= size or size <= 0 or size > 128 or size == math.huge then
        valid = false
      end
      local target
      if data.destination == "New sprite" then
        target = { mode = "new" }
      elseif data.destination == "Add layers to active sprite" and app.sprite then
        local ok, result = pcall(PortableImport.captureTarget, app.sprite, app.layer, app.frame)
        if ok then
          target = result
        else
          valid = false
        end
      else
        valid = false
      end
      local geometry = target and target.geometry
      syncing = true
      if geometry and not fixedGeometry then
        savedWidth, savedHeight = data.width, data.height
      elseif not geometry and fixedGeometry then
        d:modify({ id = "width", text = tostring(savedWidth) })
        d:modify({ id = "height", text = tostring(savedHeight) })
      end
      if geometry then
        d:modify({ id = "width", text = tostring(geometry.cellWidth) })
        d:modify({ id = "height", text = tostring(geometry.cellHeight) })
      end
      fixedGeometry = geometry ~= nil
      deps.controls:setNumericEnabled(d, { "width", "height" }, not fixedGeometry)
      syncing = false
      data = d.data
      local width = target and target.geometry and target.geometry.cellWidth or data.width
      local height = target and target.geometry and target.geometry.cellHeight or data.height
      ---Check whether a given value is a valid positive integer within dimension limits.
      ---@param value any Value to check.
      ---@return boolean isValid True if value is an integer between 1 and 128.
      local function integer(value)
        return type(value) == "number"
          and value == value
          and value ~= math.huge
          and value ~= -math.huge
          and value == math.floor(value)
          and value >= 1
          and value <= 128
      end
      if not integer(width) or not integer(height) then
        valid = false
      end
      if valid then
        for _, i in ipairs(selected) do
          local grid = layers[i].grid
          if grid.cols * width > 65535 or grid.rows * height > 65535 then
            valid = false
            break
          end
        end
      end
      d:modify({ id = "prepare", enabled = valid })
      return valid
    end

    ---Trigger a re-validation and UI update for the prepare button.
    local function refreshPrepare()
      if updatePrepare then
        updatePrepare()
      end
    end
    d:combobox({
      id = "destination",
      label = "Destination",
      options = { "New sprite", "Add layers to active sprite" },
      option = "New sprite",
      onchange = refreshPrepare,
    }):combobox({
      id = "font",
      label = "Default font",
      options = labelsByFont,
      option = "ATASCII",
      onchange = refreshPrepare,
    })
    deps.controls:addFontSizeInput(
      d,
      tostring(math.min(128, first.cellHeight)),
      { min = 1, max = 128, onchange = refreshPrepare }
    )
    deps.controls:addNumericInput(
      d,
      "width",
      "Cell width",
      tostring(math.min(128, first.cellWidth)),
      { min = 1, max = 128, step = 1, onchange = refreshPrepare }
    )
    deps.controls:addNumericInput(
      d,
      "height",
      "Cell height",
      tostring(math.min(128, first.cellHeight)),
      { min = 1, max = 128, step = 1, onchange = refreshPrepare }
    )
    if #layers == 0 then
      deps.controls:addNumericInput(
        d,
        "blankCols",
        "Canvas columns",
        "1",
        { min = 1, max = 1024, step = 1, onchange = refreshPrepare }
      )
      deps.controls:addNumericInput(
        d,
        "blankRows",
        "Canvas rows",
        "1",
        { min = 1, max = 1024, step = 1, onchange = refreshPrepare }
      )
    end
    labels(d, "Unavailable characters appear as spaces.")
    labels(d, "Unicode values are preserved.")
    ---Resolve sanitized layer name and font description for a layer index.
    ---@param index integer Layer index.
    ---@return string name Formatted layer name.
    ---@return string? font Formatted font description.
    local function layerDetails(index)
      local layer = layers[index]
      local clean = sanitizeLabel(layer.id, 64)
      local name = clean and ("Layer name: " .. clean)
        or "Layer name: Source ID contains unsupported text"
      local font
      if invalidFonts[index] then
        font = "Source font ID is invalid. Choose a font."
      elseif layer.font then
        local fontName = sanitizeLabel(layer.font.name or "Font", 64)
        font = "Source font: " .. fontName .. "-" .. layer.font.id:sub(16, 27)
      end
      return name, font
    end

    updatePage = ImportLayerPager.create({
      dialog = d,
      layers = layers,
      sourceLabels = sourceLabels,
      invalidFonts = invalidFonts,
      layerState = layerState,
      controls = controls,
      overrides = overrides,
      recoveryOverrides = recoveryOverrides,
      layerDetails = layerDetails,
      pageSize = pageSize,
      pages = pages,
      isSyncing = function()
        return syncing
      end,
      setSyncing = function(value)
        syncing = value
      end,
      isReady = function()
        return controlsReady
      end,
      onChange = refreshPrepare,
    })
    d:separator({})
    d:button({
      id = "prepare",
      text = "Prepare import..",
      focus = true,
      enabled = false,
      onclick = deps.guard(function()
        U.check(updatePrepare(), "Select at least one source layer and enter valid import options")
        local data, target = d.data
        if data.destination == "New sprite" then
          target = PortableImport.captureTarget()
        else
          target = PortableImport.captureTarget(
            U.check(app.sprite, "Open an RGB sprite first"),
            app.layer,
            app.frame
          )
        end
        local selected, choices, substitutes = {}, {}, {}
        for i, layer in ipairs(layers) do
          selected[i] = layerState[i].selected
          local chosen = layerState[i].font
          local label = chosen == "Use default font" and data.font or chosen
          if selected[i] then
            choices[i] = U.check(fontsByLabel[label], "Choose a font")
            substitutes[i] = invalidFonts[i] ~= nil or (layer.font ~= nil and label ~= matches[i])
          else
            choices[i] = fontsByLabel[data.font]
          end
        end
        local revision, resources = self.library.revision, {}
        local width = target.geometry and target.geometry.cellWidth or data.width
        local height = target.geometry and target.geometry.cellHeight or data.height
        enable(false)
        pending = runPortableTask("Prepare Textmode Import", function(checkpoint)
          local jobs, byId = {}, {}
          local selectedCount, currentSelected = 0, 0
          for i in ipairs(choices) do
            if selected[i] then
              selectedCount = selectedCount + 1
            end
          end
          for i, font in ipairs(choices) do
            if selected[i] then
              currentSelected = currentSelected + 1
              if not byId[font.id] then
                byId[font.id] = deps.library:job(font, {
                  pixelSize = data.size,
                  cellWidth = width,
                  cellHeight = height,
                  checkpoint = checkpoint,
                })
                resources[#resources + 1] = font
              end
              jobs[i] = byId[font.id]
              checkpoint(
                "Reading " .. font.name .. "...",
                0.15 * (currentSelected / math.max(1, selectedCount))
              )
            end
          end
          local blankJob
          if #layers == 0 then
            local font = U.check(fontsByLabel[data.font], "Choose a font")
            blankJob = deps.library:job(font, {
              pixelSize = data.size,
              cellWidth = width,
              cellHeight = height,
              checkpoint = checkpoint,
            })
            resources[#resources + 1] = font
          end
          return PortableImport.prepareImport(document, {
            blankJob = blankJob,
            selected = selected,
            jobs = jobs,
            substitutes = substitutes,
            invalidFonts = invalidFonts,
            cellWidth = width,
            cellHeight = height,
            blankCols = data.blankCols,
            blankRows = data.blankRows,
            checkpoint = checkpoint,
            verifyResources = function()
              U.check(
                self.library.revision == revision,
                "STALE_IMPORT: font library changed; prepare the import again"
              )
              for _, font in ipairs(resources) do
                if font.kind == "user" then
                  self.library:resource(font.id, font.sha256)
                end
              end
            end,
          }, target)
        end, function(plan)
          pending = nil
          d:close()
          reviewPortableImport(plan, warnings)
        end, function()
          pending = nil
          enable(true)
        end, function(err)
          portableImportProblem(tostring(err))
        end)
      end),
    })
    controlsReady = true
    updatePage()
    updatePrepare()
    d:show({ wait = false, autoscrollbars = true })
  end

  ---Open the portable document import workflow.
  function self:importDocument()
    if deps.focusDialog and deps.focusDialog("importDocument") then
      return
    end
    local pending, closed
    local d = deps.dialog("Import Textmode JSON", {
      singleton = "importDocument",
      onclose = function()
        closed = true
        if pending then
          pending()
        end
      end,
    })
    ---Enable or disable file selection and submission controls.
    ---@param value boolean Enabled state.
    local function enable(value)
      local path = d.data.file
      if not closed then
        d:modify({ id = "file", enabled = value })
          :modify({ id = "read", enabled = value and type(path) == "string" and path ~= "" })
      end
    end
    d:file({
      id = "file",
      label = "Artwork JSON",
      title = "Import Textmode JSON",
      open = true,
      filetypes = { "json" },
      onchange = function()
        local path = d.data.file
        if not closed then
          d:modify({ id = "read", enabled = type(path) == "string" and path ~= "" })
        end
      end,
    }):newrow({ always = true })
    d:label({ text = "Open portable artworks from:" }):newrow({ always = true })
    d:label({ text = "- extension.textmode.art" }):newrow({ always = true })
    d:label({ text = "- export.textmode.art" }):newrow({ always = true })
    d:label({ text = "- create.textmode.art" }):newrow({ always = true })
    d:label({ text = "- code.textmode.art" }):newrow({ always = true })
    d:label({ text = "- this extension" }):newrow({ always = true })
    d
      :button({
        id = "read",
        text = "Read document",
        focus = true,
        enabled = false,
        onclick = deps.guard(function()
          local path =
            U.check(d.data.file ~= "" and d.data.file, "Choose an artwork JSON file first")
          U.check(not self.tasks:isActive(), "Finish or cancel the current import first")
          -- The protected host read may open a modal permission window. Finish it
          -- on the main Lua thread before arming the incremental decode timer.
          local read, bytes = pcall(U.read, path, Codec.maxBytes)
          if not read then
            local reason = tostring(bytes):gsub("^.-:%d+: ", "")
            if reason:lower():find("the script doesn't have access to file", 1, true) then
              reason = "The script doesn't have access to the selected file."
            elseif path and path ~= "" then
              local pattern = path:gsub("([%%%^%$%(%)%%.%[%]%*%+%-%?])", "%%%1")
              reason = reason:gsub("^" .. pattern .. ":%s*", "")
              reason = reason:gsub("['\"]" .. pattern .. "['\"]", "the selected file")
              reason = reason:gsub(pattern, "the selected file")
            end
            portableImportProblem(
              "Cannot read artwork JSON: "
                .. reason
                .. ".\nCheck the file and allow read access when Aseprite asks, then try again."
            )
            return
          end
          enable(false)
          pending = runPortableTask("Read Textmode JSON", function(checkpoint)
            return PortableImport.read(bytes, { checkpoint = checkpoint })
          end, function(result)
            pending = nil
            if result.ok then
              d:close()
              portableImportOptions(result.document, result.warnings, result.invalidFonts)
            else
              enable(true)
              portableImportProblem(Codec.message(result))
            end
          end, function()
            pending = nil
            enable(true)
          end)
        end),
      })
      :show({ wait = false })
  end

  ---Prepare and review a portable export before writing the file.
  ---@param sprite Sprite Source document.
  ---@param layer Layer? Selected source layer.
  ---@param frame Frame Source frame.
  ---@param options table Export selection options.
  ---@param path string Destination JSON path.
  function self:exportDocument(sprite, layer, frame, options, path)
    U.check(
      sprite.isValid and app.sprite == sprite and app.frame == frame,
      "The captured export sprite or frame changed"
    )
    U.check(not self.tasks:isActive(), "Finish or cancel the current import first")
    local changed = false
    local subscription = sprite.events:on("change", function()
      changed = true
    end)
    ---Verify that the captured export sprite and frame have not mutated.
    local function check()
      U.check(
        not changed and sprite.isValid and app.sprite == sprite and app.frame == frame,
        "The export source changed; open Export again"
      )
    end
    local subscribed, handedOff = true, false
    ---Unsubscribe from sprite change events and mark subscription as inactive.
    local function unsubscribe()
      if not subscribed then
        return
      end
      subscribed = false
      if sprite.isValid then
        sprite.events:off(subscription)
      end
    end
    local started, startError = pcall(function()
      runPortableTask(
        "Prepare Textmode Export",
        function(checkpoint)
          options.checkpoint = function(message, fraction)
            check()
            checkpoint(message, fraction)
          end
          options.resolveFont = function(id, digest, checkpoint)
            return self.library:resource(id, digest, checkpoint)
          end
          return PortableExport.export(sprite, layer, frame, options)
        end,
        function(result)
          local d = deps.dialog("Review Textmode Export", {
            onclose = function()
              unsubscribe()
            end,
          })
          local frameCount = #result.document.frames
          local frameText = tostring(frameCount)
          if #sprite.frames > 1 then
            if options.frames == "all" then
              frameText = frameText .. " (all)"
            else
              local frameNumber = U.frameNumber(frame)
              frameText = frameText .. " (frame " .. frameNumber .. ")"
            end
          end
          local review = result.review
          local layerText = tostring(review.maxLayers)
          if review.minLayers ~= review.maxLayers then
            layerText = "up to " .. layerText .. " per frame"
          end
          if review.layerName then
            local name = sanitizeLabel(review.layerName, 20)
            if name then
              layerText = layerText .. " (" .. name .. ")"
            end
          end
          d:label({ label = "Frames:", text = frameText }):newrow()
          d:label({ label = "Layers:", text = layerText }):newrow()
          d:label({ label = "Coverage:", text = "Current canvas" }):newrow()
          d:label({ text = "Partial edge cells are included whole." }):newrow()
          if #result.excluded > 0 then
            warningLabel(d, "Native layers are not exported.")
          end
          if result.outside > 0 then
            warningLabel(d, result.outside .. " occupied cell(s) outside the canvas are omitted.")
          end
          d:button({
            text = "Save JSON",
            focus = true,
            onclick = deps.guard(function()
              check()
              U.write(path, result.text)
              d:close()
            end),
          }):show({ wait = false, autoscrollbars = true })
          handedOff = true
        end,
        nil,
        nil,
        function()
          if not handedOff then
            unsubscribe()
          end
        end
      )
    end)
    if not started then
      unsubscribe()
      error(startError, 0)
    end
  end
  return self
end
return M
