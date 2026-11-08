local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Edit = require("src.document.edit")
local CellClipboard = require("src.document.clipboard")
local UnicodeNames = require("src.unicode.names")
local Repertoire = require("src.fonts.repertoire")
local Settings = require("src.core.settings")
local ReplacePreview = require("src.ui.replace_preview")
local Task = require("src.core.task")
local M = {}

---Check whether a given path has both directory and filename components.
---@param path string File path candidate.
---@return boolean valid True if output path is non-empty.
local function hasOutputPath(path)
  return type(path) == "string" and app.fs.filePath(path) ~= "" and app.fs.fileName(path) ~= ""
end

---Ensure a file path has the requested extension.
---@param path string Original path.
---@param extension string Desired extension without dot.
---@return string path Normalized path with extension.
local function withExtension(path, extension)
  return app.fs.fileExtension(path):lower() == extension and path
    or app.fs.filePathAndTitle(path) .. "." .. extension
end

---Create the document creation and editing workflow.
---@param deps table Host services and UI callbacks.
---@return table workflow Document workflow.
function M.new(deps)
  local library = deps.library

  ---Resolve custom user font resource bytes from library.
  ---@param id string Font identifier.
  ---@param digest string Font SHA-256 hash.
  ---@return table resource Font resource record.
  local function resolveUser(id, digest)
    return library:resource(id, digest)
  end
  local self = { drawing = deps.drawing }
  local copiedCells

  ---Find the active marquee selection on the sprite if non-empty.
  ---@param sprite Sprite? Target sprite.
  ---@return Selection? selection Active non-empty selection or nil.
  local function visibleSelection(sprite)
    if not sprite or not sprite.selection then
      return nil
    end
    local selection = sprite.selection
    if selection.isEmpty then
      return nil
    end
    return selection
  end

  ---Check whether cell copy action is currently possible.
  ---@return boolean can True if editable text layer with selection is active.
  function self:canCopyCells()
    local sprite = app.sprite
    if not Model.textLayer(sprite, app.layer) then
      return false
    end
    local selection = visibleSelection(sprite)
    return selection ~= nil and not selection.isEmpty
  end

  ---Copy selected textmode cells into the clipboard buffer.
  function self:copyCells()
    local sprite, layer = self.drawing:target()
    self.drawing:ensureActive()
    self.drawing:flush()
    copiedCells = CellClipboard.copy(sprite, layer, app.frame, visibleSelection(sprite))
    deps.invalidate()
    if app.isUIAvailable then
      local count = #copiedCells.cells
      app.tip("Copied " .. count .. (count == 1 and " Asemode cell" or " Asemode cells"))
    end
  end

  ---Paste cells from clipboard into the active document selection.
  function self:pasteCells()
    local sprite, layer = self.drawing:target()
    self.drawing:ensureActive()
    self.drawing:flush()
    local prepared = CellClipboard.prepare(
      sprite,
      layer,
      app.frame,
      visibleSelection(sprite),
      copiedCells,
      resolveUser
    )
    if prepared.missing > 0 and app.isUIAvailable then
      if
        app.alert({
          title = "Paste Asemode Cells",
          text = {
            prepared.missing
              .. (prepared.missing == 1 and " cell uses" or " cells use")
              .. " characters unavailable in this font.",
            "Replace those characters with spaces?",
          },
          buttons = { "Paste", "Cancel" },
        }) ~= 1
      then
        return
      end
    end
    self.drawing:withSuppression(function()
      CellClipboard.apply(prepared)
    end)
    app.refresh()
    deps.invalidate()
  end
  ---Open the new textmode sprite dialog.
  function self:newDocument()
    if deps.focusDialog and deps.focusDialog("newDocument") then
      return
    end
    local defaults = Settings.read(deps.preferences, library)
    local d = deps.dialog("New Textmode Sprite", { singleton = "newDocument", autofit = 0 })
    local catalog
    deps.controls:addNumericInput(
      d,
      "cols",
      "Columns",
      tostring(defaults.columns),
      { min = 1, max = 1024, step = 1 }
    )
    deps.controls:addNumericInput(
      d,
      "rows",
      "Rows",
      tostring(defaults.rows),
      { min = 1, max = 1024, step = 1 }
    )
    catalog =
      deps.font:libraryControl(d, "font", nil, { id = defaults.fontId, kind = defaults.fontKind })
    deps.controls:addFontSizeInput(d, tostring(defaults.size), { min = 8, max = 128 })
    local getBackground = deps.controls:addBackgroundInput(d, defaults.backgroundColor)
    d:button({
      text = "Create",
      focus = true,
      onclick = deps.guard(function()
        local data = d.data
        local selected = U.check(catalog.selected(), "Choose a library font")
        local cols = deps.controls:clampInt(data.cols, 1, 1024, defaults.columns)
        local rows = deps.controls:clampInt(data.rows, 1, 1024, defaults.rows)
        local sz = deps.controls:clampInt(data.size, 8, 128, defaults.size)
        local job = library:job(selected, { pixelSize = sz }):finish()
        Model.create(job, cols, rows, false, getBackground())
        local primary, secondary = deps.font:defaultBrushes(job.glyphs)
        self.drawing:setImportedStamps(primary, secondary)
        d:close()
        deps.positionPanel()
        deps.openPanel()
        self.drawing:prepareBoth()
      end),
    })
    d:show({ wait = false })
  end

  ---Open the replacement dialog for the active text selection.
  function self:replaceSelection()
    local sprite, layer = self.drawing:target()
    local index = Profile.index(sprite, Model.meta(layer).fontProfileId)
    local selection = { cells = {}, count = 0, columns = 0, rows = 0 }
    local renderer = ReplacePreview.createRenderer(index)
    local snapshot = self.drawing:snapshot()
    local timer, listeners, closed, closeDialog = nil, {}, false, nil
    local spriteListeners, task, maskSnapshot, maskBounds = {}, nil, nil, nil
    local dirty, ready, suspended, scanning, frameNumber = true, false, false, false, nil
    local failure, validated = nil, false

    ---Tear down background tasks, preview timers, and event listeners.
    local function cleanup()
      if closed then
        return
      end
      closed = true
      self.activeReplaceTick = nil
      if task then
        task:cancel()
        task = nil
      end
      if self.closeReplaceSelection == closeDialog then
        self.closeReplaceSelection = nil
      end
      if timer then
        local t = timer
        timer = nil
        pcall(function()
          t:stop()
        end)
      end
      for _, id in ipairs(listeners) do
        pcall(function()
          app.events:off(id)
        end)
      end
      listeners = {}
      if sprite.isValid and sprite.events then
        for _, id in ipairs(spriteListeners) do
          pcall(function()
            sprite.events:off(id)
          end)
        end
      end
      spriteListeners = {}
    end

    if self.closeReplaceSelection then
      self.closeReplaceSelection()
    end
    local d = deps.dialog("Replace selection", { autofit = 0, onclose = cleanup })
    closeDialog = function()
      d:close()
      cleanup()
    end
    self.closeReplaceSelection = closeDialog

    ---Construct current replacement specification from dialog checkboxes and active stamp.
    ---@return table spec Replacement specification with flags and colors.
    local function currentSpec()
      local data = d.data or {}
      local replaceFg = data.changeFg ~= false
      local replaceBg = data.changeBg ~= false
      local glyphEnabled = data.changeGlyph ~= false
      local stamp = self.drawing:snapshot()
      local fg, bg, glyph = stamp.fg, stamp.bg, stamp.glyph or ""
      local hasGlyph = glyph ~= ""
      local replaceGlyph = glyphEnabled
      return {
        replaceFg = replaceFg,
        replaceBg = replaceBg,
        glyphEnabled = glyphEnabled,
        replaceGlyph = replaceGlyph,
        fg = fg,
        bg = bg,
        glyph = glyph,
        flags = stamp.flags or 0,
        glyphValid = hasGlyph and pcall(Repertoire.scalar, glyph),
      }
    end

    ---Check whether the replacement operation can be applied.
    ---@param spec table Current replacement specification.
    ---@return boolean can True if conditions are met.
    local function canApply(spec)
      return ready
        and selection.count > 0
        and (spec.replaceFg or spec.replaceBg or spec.replaceGlyph)
        and (not spec.replaceGlyph or spec.glyphValid)
    end

    ---Compute descriptive status and preview guidance text.
    ---@param spec table Current replacement specification.
    ---@return string message Informational status text.
    local function previewInfoText(spec)
      if suspended then
        return "Select an Asemode layer and a visible selection."
      end
      if failure then
        return "Selection unavailable."
      end
      if not ready then
        return "Updating selection..."
      end
      if selection.count == 0 then
        return "No occupied cells in the selection."
      end
      if not (spec.replaceFg or spec.replaceBg or spec.replaceGlyph) then
        return "Select Foreground, Background, or Glyph."
      end
      local cellCountText = selection.count == 1 and "1 selected cell"
        or (selection.count .. " selected cells")
      if spec.replaceGlyph then
        if not spec.glyphValid then
          return "Select a primary stamp."
        end
        local codepoint = utf8.codepoint(spec.glyph)
        local source = index.glyphs[spec.glyph]
        local missing = not source or source.meta.renderFallback and true
        local glyphName = UnicodeNames.name(codepoint) or "Unnamed character"
        if missing then
          return string.format("%s · Missing in font · shown as space", glyphName)
        end
        return string.format("%s · %s", glyphName, cellCountText)
      end
      local channelText = (spec.replaceFg and spec.replaceBg) and "Foreground and Background"
        or (spec.replaceFg and "Foreground only" or "Background only")
      return string.format("%s · %s", cellCountText, channelText)
    end

    ---Repaint preview canvas and refresh Apply button state.
    local function updatePreview()
      local spec = currentSpec()
      d:modify({ id = "glyphPreviewInfo", text = previewInfoText(spec) })
      d:modify({ id = "applyReplace", enabled = canApply(spec) })
      d:repaint()
    end

    ---Invalidate cached selection scan and cancel running task.
    local function invalidate()
      dirty, ready, failure = true, false, nil
      if task then
        task:cancel()
        task = nil
      end
    end

    ---Invalidate state and trigger preview update.
    local function requestRefresh()
      invalidate()
      updatePreview()
    end

    ---Compare two bounding rectangles for exact coordinate match.
    ---@param a? Rectangle|table First bounds.
    ---@param b? Rectangle|table Second bounds.
    ---@return boolean equal True if both bounds match.
    local function sameBounds(a, b)
      return a and b and a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
    end

    ---Poll host selection and sprite cels, scheduling incremental preview scans.
    local function checkSelection()
      if closed or scanning then
        return
      end
      if not sprite.isValid then
        cleanup()
        return
      end
      scanning = true
      local ok, problem = xpcall(function()
        local active = app.isUIAvailable == nil or (app.sprite == sprite and app.layer == layer)
        local hidden = active and app.isUIAvailable ~= nil and not visibleSelection(sprite)
        if not active or hidden then
          if not suspended then
            suspended = true
            maskSnapshot, maskBounds = nil, nil
            invalidate()
            updatePreview()
          end
          return
        end
        if suspended then
          suspended = false
          invalidate()
        end
        local currentFrame = U.frameNumber(app.frame)
        if currentFrame ~= frameNumber then
          frameNumber = currentFrame
          invalidate()
        end
        local live, changedMask
        if type(Selection) == "function" then
          live = sprite.selection
          local bounds = live.bounds
          changedMask = not maskSnapshot
            or not sameBounds(maskBounds, bounds)
            or maskSnapshot ~= live
          if changedMask then
            local copy = Selection()
            copy:add(live)
            maskSnapshot, maskBounds = copy, bounds
            invalidate()
          end
        else
          -- Host-free test environments do not provide Selection objects.
          invalidate()
        end
        local stamp = self.drawing:snapshot()
        local stampChanged = stamp.glyph ~= snapshot.glyph
          or stamp.fg ~= snapshot.fg
          or stamp.bg ~= snapshot.bg
          or stamp.flags ~= snapshot.flags
        snapshot = stamp
        if dirty and not task then
          local selected, frame = maskSnapshot, currentFrame
          local validationWasReady = validated
          task = Task.new(function(checkpoint)
            local options = {
              selection = selected,
              checkpoint = checkpoint,
              validated = validationWasReady,
            }
            local result = Edit.selectedCells(sprite, layer, frame, options)
            return {
              selection = result,
              index = Profile.index(sprite, Model.meta(layer).fontProfileId),
              validated = options.validated or options.validationComplete,
            }
          end)
          dirty = false
          updatePreview()
        end
        if task and task:step(8) then
          local result = task.result
          task = nil
          selection, index, validated = result.selection, result.index, result.validated
          renderer = ReplacePreview.createRenderer(index)
          ready = true
          updatePreview()
        elseif stampChanged and ready then
          updatePreview()
        end
      end, debug.traceback)
      scanning = false
      if not ok then
        if task then
          task:cancel()
          task = nil
        end
        dirty, ready, failure = false, false, tostring(problem)
        print("[Asemode selection preview] " .. tostring(problem))
        updatePreview()
      end
    end

    local createTimer = deps.timer or (type(Timer) == "function" and Timer or nil)
    if createTimer then
      local ok, t = pcall(createTimer, {
        interval = 0.05,
        ontick = checkSelection,
      })
      if ok and t then
        timer = t
        if timer.start then
          pcall(function()
            timer:start()
          end)
        end
      end
    end
    self.activeReplaceTick = checkSelection

    if app.events and app.events.on then
      pcall(function()
        listeners[#listeners + 1] = app.events:on("sitechange", requestRefresh)
      end)
      pcall(function()
        listeners[#listeners + 1] = app.events:on("aftercommand", function(ev)
          if ev and ev.name == "DeselectMask" then
            suspended = true
            maskSnapshot, maskBounds = nil, nil
            invalidate()
            updatePreview()
          elseif ev and ev.name == "ReselectMask" then
            suspended = false
            requestRefresh()
          end
        end)
      end)
    end
    if sprite.events then
      spriteListeners[#spriteListeners + 1] = sprite.events:on("change", function()
        validated = false
        requestRefresh()
      end)
    end

    ---Build a click handler for attribute checkboxes ensuring at least one remains checked.
    ---@param id string Checkbox identifier.
    ---@return fun() handler Checkbox click handler.
    local function toggleCheckbox(id)
      return function()
        local data = d.data or {}
        if data.changeFg == false and data.changeBg == false and data.changeGlyph == false then
          if type(d.data) == "table" then
            d.data[id] = true
          end
          d:modify({ id = id, selected = true })
        end
        updatePreview()
      end
    end
    local initialSpec = currentSpec()
    d:label({ text = "Applies to occupied cells in the active frame." })
      :check({
        id = "changeFg",
        text = "Foreground",
        selected = true,
        onclick = toggleCheckbox("changeFg"),
      })
      :samerow()
      :check({
        id = "changeBg",
        text = "Background",
        selected = true,
        onclick = toggleCheckbox("changeBg"),
      })
      :samerow()
      :check({
        id = "changeGlyph",
        text = "Glyph",
        selected = true,
        onclick = toggleCheckbox("changeGlyph"),
      })
      :canvas({
        id = "replacePreview",
        width = ReplacePreview.WIDTH,
        height = ReplacePreview.HEIGHT,
        vexpand = false,
        onpaint = function(ev)
          ReplacePreview.paint(
            ev.context,
            index,
            ready and selection or nil,
            currentSpec(),
            renderer
          )
        end,
      })
      :label({ id = "glyphPreviewInfo", text = previewInfoText(initialSpec) })
      :button({
        id = "applyReplace",
        text = "Apply",
        enabled = canApply(initialSpec),
        onclick = deps.guard(function()
          U.check(sprite.isValid, "The document was closed")
          U.check(ready and not suspended, "Wait for the selection preview to finish")
          if app.isUIAvailable ~= nil then
            U.check(
              app.sprite == sprite and app.layer == layer,
              "Select the original Asemode layer"
            )
            local live = U.check(visibleSelection(sprite), "Select an area before applying")
            local currentFrame = U.frameNumber(app.frame)
            if
              currentFrame ~= frameNumber
              or not sameBounds(maskBounds, live.bounds)
              or maskSnapshot ~= live
            then
              invalidate()
              checkSelection()
              return
            end
          end
          local spec = currentSpec()
          U.check(
            spec.replaceFg or spec.replaceBg or spec.replaceGlyph,
            "Choose at least one setting to replace"
          )
          if spec.replaceGlyph then
            U.check(spec.glyphValid, "Select a primary stamp")
          end
          Edit.recolor(
            sprite,
            layer,
            app.frame,
            spec.replaceFg and spec.fg or nil,
            spec.replaceBg and spec.bg or nil,
            spec.replaceGlyph and spec.glyph or nil,
            spec.replaceGlyph and spec.flags or nil
          )
          app.refresh()
          invalidate()
          checkSelection()
        end),
      })
      :show({ wait = false })
    checkSelection()
  end

  ---Open the export options for the active document.
  function self:export()
    if deps.focusDialog and deps.focusDialog("export") then
      return
    end
    local sprite, layer = self.drawing:active()
    U.check(sprite and layer, "Select an Asemode layer for export")
    local frame = app.frame
    local basePath = sprite.filename ~= "" and app.fs.filePathAndTitle(sprite.filename) or "Asemode"
    local d = deps.dialog("Export Textmode Document", { singleton = "export" })
    local ready, selected = false, false

    ---Enable or disable the Export button based on file selection status.
    local function updateExport()
      if not ready then
        return
      end
      d:modify({ id = "export", enabled = selected })
    end

    ---Validate chosen output file path when user modifies the file input.
    local function chooseDocumentFile()
      if not ready then
        return
      end
      selected = hasOutputPath(d.data.documentFile)
      updateExport()
    end
    d:file({
      id = "documentFile",
      label = "Artwork JSON",
      title = "Export Textmode Document",
      filename = basePath .. ".textmode.json",
      save = true,
      filetypes = { "json" },
      onchange = chooseDocumentFile,
    })
      :combobox({
        id = "documentFrames",
        label = "Frames",
        options = { "All frames", "Active frame" },
        option = "All frames",
      })
      :combobox({
        id = "documentTarget",
        label = "Layers",
        options = { "All Asemode layers", "Active Asemode layer" },
        option = "All Asemode layers",
      })
      :button({
        id = "export",
        text = "Export",
        enabled = false,
        focus = true,
        onclick = deps.guard(function()
          U.check(sprite.isValid, "The document was closed")
          U.check(
            selected and hasOutputPath(d.data.documentFile),
            "Choose an artwork JSON filename first"
          )
          local path = d.data.documentFile
          if not path:lower():match("%.json$") then
            path = path .. ".textmode.json"
          end
          deps.portable:exportDocument(sprite, layer, frame, {
            target = d.data.documentTarget == "All Asemode layers" and "all" or "selected",
            frames = d.data.documentFrames == "All frames" and "all" or "selected",
          }, path)
          d:close()
        end),
      })
      :show({ wait = false, autoscrollbars = true })
    ready = true
  end

  ---Open the grid and cell size workflow for the active document.
  function self:regrid()
    if deps.focusDialog and deps.focusDialog("regrid") then
      return
    end
    local sprite = U.check(app.sprite, "Open an Asemode document first")
    U.check(Model.supported(sprite), "Open a valid Asemode document first")
    local g = U.copy(Model.geometry(sprite))
    local extent = Model.coverage(sprite, g)
    local d = deps.dialog("Grid", { singleton = "regrid" })

    ---Present a modal confirmation summary before applying grid or cell resizing.
    ---@param title string Dialog title.
    ---@param sections table[] List of descriptive summary sections.
    ---@param button table Action button descriptor.
    ---@param apply fun(preview: Dialog) Confirmation callback.
    local function openConfirmResizeDialog(title, sections, button, apply)
      local preview = deps.dialog(title)
      for _, section in ipairs(sections) do
        preview:separator({ text = section.title })
        for _, label in ipairs(section.labels) do
          preview:label(label)
        end
      end
      button.onclick = deps.guard(function()
        apply(preview)
      end)
      preview:newrow():button(button):show({ wait = false, autoscrollbars = true })
    end

    ---Prepare and preview font rerendering for modified pixel cell dimensions.
    local function previewCellSize()
      deps.guard(function()
        local data = d.data
        local width = deps.controls:clampInt(data.width, 1, 128, g.cellWidth)
        local height = deps.controls:clampInt(data.height, 1, 128, g.cellHeight)
        local jobs = Edit.prepareRegrid(sprite, width, height, resolveUser)
        deps.font:runJobs(jobs, function()
          local summary = Edit.previewRegrid(sprite, width, height)
          local clipped = 0
          for _, item in ipairs(jobs) do
            clipped = clipped + item.job.profile.clippedGlyphs
          end
          openConfirmResizeDialog("Confirm regrid", {
            {
              title = "Size changes",
              labels = {
                {
                  label = "Cell size",
                  text = string.format(
                    "%d x %d to %d x %d px",
                    g.cellWidth,
                    g.cellHeight,
                    width,
                    height
                  ),
                },
                {
                  label = "Canvas",
                  text = string.format(
                    "%d x %d to %d x %d px",
                    sprite.width,
                    sprite.height,
                    summary.width,
                    summary.height
                  ),
                },
                {
                  label = "Visible grid",
                  text = string.format(
                    "%d x %d to %d x %d cells",
                    extent.columns,
                    extent.rows,
                    summary.coverage.columns,
                    summary.coverage.rows
                  ),
                },
                { label = "Fonts", text = tostring(#jobs) },
                {
                  label = "Preserved",
                  text = summary.mixed and "Canvas and native artwork" or "Columns and rows",
                },
                {
                  label = "Edge cells",
                  text = "Partial cells are included",
                  visible = summary.coverage.partial,
                },
              },
            },
            {
              title = "Content impact",
              labels = {
                { label = "Clipped glyphs", text = tostring(clipped) },
                { label = "Clipped cells", text = tostring(summary.clipped) },
                { label = "Hidden cells", text = tostring(summary.hidden) },
                { label = "Count scope", text = "Cells across all frames" },
                { label = "Hidden data", text = "Retained", visible = summary.hidden > 0 },
              },
            },
          }, { id = "applyRegrid", text = "Regrid" }, function(preview)
            U.check(sprite.isValid, "The document was closed")
            app.sprite = sprite
            self.drawing:flush()
            Edit.regrid(sprite, jobs, width, height, true, true)
            preview:close()
            d:close()
            deps.invalidate()
            self.drawing:invalidateStamps()
          end)
        end)
      end)()
    end

    ---Calculate and confirm canvas resizing while preserving existing textmode cells.
    local function resizeGrid()
      deps.guard(function()
        U.check(sprite.isValid, "The document was closed")
        local columns = deps.controls:clampInt(d.data.columns, 1, 1024, extent.columns)
        local rows = deps.controls:clampInt(d.data.rows, 1, 1024, extent.rows)
        local nextSize = Edit.previewGridSize(sprite, columns, rows)
        local currentExtent = Model.coverage(sprite)
        local oldWidth, oldHeight = sprite.width, sprite.height
        openConfirmResizeDialog("Confirm canvas size", {
          {
            title = "Size changes",
            labels = {
              {
                label = "Canvas",
                text = string.format(
                  "%d x %d to %d x %d px",
                  oldWidth,
                  oldHeight,
                  nextSize.width,
                  nextSize.height
                ),
              },
              {
                label = "Grid",
                text = string.format(
                  "%d x %d to %d x %d cells",
                  currentExtent.columns,
                  currentExtent.rows,
                  columns,
                  rows
                ),
              },
              {
                label = "Cell size",
                text = string.format("%d x %d px (unchanged)", g.cellWidth, g.cellHeight),
              },
              { label = "Anchor", text = "Top-left" },
              { label = "Applies to", text = "All layers" },
            },
          },
          {
            title = "Content impact",
            labels = {
              {
                label = "Right edge",
                text = nextSize.hidesRight and "Hides content"
                  or (nextSize.expandsRight and "Exposes more area" or "Unchanged"),
              },
              {
                label = "Bottom edge",
                text = nextSize.hidesBottom and "Hides content"
                  or (nextSize.expandsBottom and "Exposes more area" or "Unchanged"),
              },
              { label = "Preserved", text = "Stored pixels and cel positions" },
              {
                label = "Hidden data",
                text = "Retained",
                visible = nextSize.hidesRight or nextSize.hidesBottom,
              },
            },
          },
        }, { text = "Apply canvas size" }, function(preview)
          U.check(sprite.isValid, "The document was closed")
          local current = Model.geometry(sprite)
          U.check(
            sprite.width == oldWidth
              and sprite.height == oldHeight
              and current.cellWidth == g.cellWidth
              and current.cellHeight == g.cellHeight
              and current.originX == g.originX
              and current.originY == g.originY,
            "The canvas or grid changed; preview the canvas size again"
          )
          app.sprite = sprite
          Edit.resizeGrid(sprite, columns, rows)
          preview:close()
          d:close()
          deps.invalidate()
        end)
      end)()
    end
    d:tab({ id = "grid", text = "Grid Size" })
    deps.controls:addNumericInput(
      d,
      "columns",
      "Columns",
      tostring(extent.columns),
      { min = 1, max = 1024 }
    )
    deps.controls:addNumericInput(d, "rows", "Rows", tostring(extent.rows), { min = 1, max = 1024 })
    d:label({ text = "Resizes the shared grid dimensions." })
      :button({ id = "resizeGrid", text = "Resize grid..", onclick = resizeGrid })
      :tab({ id = "cell", text = "Cell Size" })
    deps.controls:addNumericInput(
      d,
      "width",
      "Cell width",
      tostring(g.cellWidth),
      { min = 1, max = 128 }
    )
    deps.controls:addNumericInput(
      d,
      "height",
      "Cell height",
      tostring(g.cellHeight),
      { min = 1, max = 128 }
    )
    d:label({ text = "Sets each cell's pixel dimensions." })
      :button({ id = "resizeCells", text = "Resize cells..", onclick = previewCellSize })
      :endtabs({ id = "size", selected = "grid" })
      :show({ wait = false, autoscrollbars = true })
  end

  ---Refresh active replacement previews on a timer tick.
  function self.tick()
    if self.activeReplaceTick then
      self.activeReplaceTick()
    end
  end

  ---Check whether cell paste action is currently possible.
  ---@return boolean can True if copied cell data is available in clipboard.
  function self:canPasteCells()
    return copiedCells ~= nil
  end

  return self
end
return M
