local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Loader = require("src.fonts.loader")
local Edit = require("src.document.edit")
local Validate = require("src.document.validate")
local FontNames = require("src.fonts.names")
local Task = require("src.core.task")
local Settings = require("src.core.settings")
local FontPreview = require("src.ui.font_preview")
local M = {}

---Check whether a given layer exists within a target sprite.
---@param sprite Sprite? Target sprite.
---@param layer Layer? Candidate layer.
---@return boolean exists True if candidate is among sprite layers.
local function documentHasLayer(sprite, layer)
  if not (sprite and sprite.isValid and layer) then
    return false
  end
  for _, candidate in ipairs(Model.layers(sprite)) do
    if candidate == layer then
      return true
    end
  end
  return false
end

---Create the font library and font preparation workflow.
---@param deps table Font library, tasks, drawing, and UI callbacks.
---@return table workflow Font workflow.
function M.new(deps)
  local library = deps.library
  local self = { libraryViews = {}, tasks = deps.tasks, drawing = deps.drawing }

  ---Choose primary and secondary glyphs from a font repertoire.
  ---@param glyphs table[] Prepared glyphs.
  ---@return string primary Primary glyph key.
  ---@return string secondary Secondary glyph key.
  function self:defaultBrushes(glyphs)
    return Profile.defaultStamps(glyphs)
  end

  ---Add a font catalog selector and register it for library refreshes.
  ---@param d Dialog Destination dialog.
  ---@param id string Control identifier.
  ---@param metadata? fun() Callback after catalog refresh.
  ---@param initialFont table? Initial selected font.
  ---@param onchange? fun() Selection change callback.
  ---@return table state Selector state and refresh methods.
  function self:libraryControl(d, id, metadata, initialFont, onchange)
    local state = { entries = {}, byLabel = {} }
    local refreshing = false

    ---Query library catalog and assemble labels and default selection.
    ---@param old? table Previously selected font.
    ---@return string[] labels Formatted font labels.
    ---@return string? selected Label to select.
    local function choices(old)
      state.entries, state.byLabel = library:catalog(), {}
      local labels, fallback, selected = {}, nil, nil
      local defaultFont = Settings.defaults()
      for _, entry in ipairs(state.entries) do
        labels[#labels + 1] = entry.label
        state.byLabel[entry.label] = entry
        if entry.id == defaultFont.fontId and entry.kind == defaultFont.fontKind then
          fallback = entry.label
        end
        if old and entry.id == old.id and entry.kind == old.kind then
          selected = entry.label
        end
      end
      return labels, selected or fallback
    end

    ---Repaint and update the font selector combobox.
    local function refresh()
      local old = state.byLabel[d.data[id]] or initialFont
      local labels, selected = choices(old)
      refreshing = true
      d:modify({ id = id, options = labels, option = selected })
      refreshing = false
      if metadata then
        metadata()
      end
    end
    local labels, selected = choices(initialFont)
    d:combobox({
      id = id,
      label = "Font",
      options = labels,
      option = selected,
      onchange = function()
        if not refreshing and onchange then
          onchange()
        end
      end,
    })
    state.selected = function()
      return state.byLabel[d.data[id]]
    end
    state.refresh = refresh
    local view = { dialog = d, refresh = refresh }
    self.libraryViews[#self.libraryViews + 1] = view
    if deps.onDialogClose then
      deps.onDialogClose(d, function()
        for i = #self.libraryViews, 1, -1 do
          if self.libraryViews[i] == view then
            table.remove(self.libraryViews, i)
            break
          end
        end
      end)
    end
    return state
  end

  ---Trigger refresh across all open library font combobox views.
  local function refreshLibraries()
    local views = {}
    for _, view in ipairs(self.libraryViews) do
      if deps.isDialogOpen(view.dialog) then
        view.refresh()
        views[#views + 1] = view
      end
    end
    self.libraryViews = views
  end

  ---Open dialog for renaming and removing user-imported fonts.
  local function manageUserFonts()
    if deps.focusDialog and deps.focusDialog("manageUserFonts") then
      return
    end
    local d = deps.dialog("Manage User Fonts", { singleton = "manageUserFonts" })
    local selected, entries
    local function refresh()
      entries = {}
      local labels = {}
      for _, entry in ipairs(library:catalog()) do
        if entry.kind == "user" then
          labels[#labels + 1] = entry.label
          entries[entry.label] = entry
        end
      end
      local option = labels[1]
      for label, entry in pairs(entries) do
        if entry.id == selected then
          option = label
        end
      end
      d:modify({
        id = "userFont",
        options = #labels > 0 and labels or { "No user fonts" },
        option = option or "No user fonts",
      })
      local entry = entries[option]
      selected = entry and entry.id
      d:modify({
        id = "name",
        text = entry and entry.name or "",
        enabled = entry ~= nil and not library.error,
      })
      for _, id in ipairs({ "rename", "remove" }) do
        d:modify({ id = id, enabled = entry ~= nil and not library.error })
      end
      local count, bytes = library:usage()
      d:modify({
        id = "usage",
        text = string.format("%d / 64 fonts · %.2f / 32 MiB", count, bytes / 1024 / 1024),
      })
      refreshLibraries()
    end
    d:combobox({
      id = "userFont",
      label = "User font",
      options = { "No user fonts" },
      onchange = function()
        local entry = entries[d.data.userFont]
        selected = entry and entry.id
        d:modify({ id = "name", text = entry and entry.name or "" })
      end,
    })
      :entry({ id = "name", label = "Display name", text = "" })
      :label({ id = "usage", text = "" })
      :button({
        id = "rename",
        text = "Rename",
        onclick = deps.guard(function()
          library:rename(selected, d.data.name)
          refresh()
        end),
      })
      :button({
        id = "remove",
        text = "Remove",
        onclick = deps.guard(function()
          if
            app.alert({
              title = "Remove User Font",
              text = {
                "Remove this font from the local Library?",
                "Existing artwork and source files are preserved.",
              },
              buttons = { "Remove", "Cancel" },
            }) == 1
          then
            library:remove(selected)
            refresh()
          end
        end),
      })
    if library.error then
      d:label({ text = "The saved Library is unreadable." })
        :newrow()
        :label({ text = "Its original data has been preserved." })
        :newrow()
        :button({
          id = "resetUserLibrary",
          text = "Reset User Library",
          onclick = deps.guard(function()
            if
              app.alert({
                title = "Reset User Library",
                text = "Discard the unreadable saved font library?",
                buttons = { "Reset", "Cancel" },
              }) == 1
            then
              library:reset()
              d:close()
              refreshLibraries()
              manageUserFonts()
            end
          end),
        })
    end
    refresh()
    d:show({ wait = false, autoscrollbars = true })
  end

  ---Run font preparation jobs and invoke a completion callback.
  ---@param items table[] Jobs or records containing jobs.
  ---@param complete fun(items: table[]) Completion callback.
  ---@return table? handle Task handle, or nil for an empty list.
  function self:runJobs(items, complete)
    U.check(not self.tasks:isActive(), "Finish or cancel the current import first")
    if #items == 0 then
      complete(items)
      return
    end
    local task = Task.new(function(checkpoint)
      local totalGlyphs, completedGlyphs = 0, 0
      for _, item in ipairs(items) do
        local job = item.job or item
        totalGlyphs = totalGlyphs + math.max(1, #job.glyphs)
      end
      for current, item in ipairs(items) do
        local job = item.job or item
        repeat
          local done = job:step(16)
          checkpoint(
            string.format("Font %d/%d · glyph %d/%d", current, #items, job.position, #job.glyphs),
            (completedGlyphs + job.position) / math.max(1, totalGlyphs)
          )
          if done then
            break
          end
        until false
        completedGlyphs = completedGlyphs + math.max(1, #job.glyphs)
      end
      return items
    end)
    return self.tasks:start(
      task,
      { title = "Build Glyph Masks", progress = "Preparing font...", complete = complete }
    )
  end

  ---Show a completed font job and invoke the callback after confirmation.
  ---@param job AsemodeFontJob Completed font job.
  ---@param complete function Confirmation callback.
  ---@param target Sprite? Destination sprite for canvas preview.
  function self:preview(job, complete, target)
    if deps.focusDialog and deps.focusDialog("fontMetrics") then
      return
    end
    local d, p = nil, job.profile
    local sample = FontPreview.sample(job)
    d = deps.dialog("Font Metrics Preview", { singleton = "fontMetrics" })
    if target and target.isValid then
      local g = Model.managed(target) and U.copy(Model.geometry(target))
        or { originX = 0, originY = 0 }
      g.cellWidth, g.cellHeight = p.cellWidth, p.cellHeight
      local extent = Model.coverage(target, g)
      d:label({
        label = "Canvas",
        text = string.format(
          "%d×%d px · %d×%d cells%s",
          target.width,
          target.height,
          extent.columns,
          extent.rows,
          extent.partial and " · partial edges" or ""
        ),
      })
    end
    local missing = 0
    for _, glyph in ipairs(job.glyphs) do
      if glyph.renderFallback then
        missing = missing + 1
      end
    end
    if missing > 0 then
      d:label({
        label = "Missing",
        text = missing .. " shown as spaces; Unicode kept",
      })
    end
    d:label({ label = "Font", text = p.name })
      :label({
        label = "Grid",
        text = string.format("%d glyphs · %d×%d cells", #job.glyphs, p.cellWidth, p.cellHeight),
      })
      :label({
        label = "Natural",
        text = string.format(
          "%d×%d px · baseline %.2f px from top%s",
          p.naturalWidth,
          p.naturalHeight,
          p.baseline,
          (p.baseline < 0 or p.baseline > p.cellHeight) and " (outside cell)" or ""
        ),
      })
      :label({
        label = "Fit",
        text = p.clippedGlyphs > 0 and (p.clippedGlyphs .. " glyph(s) may clip")
          or (p.kind == "bitmap" and "Bitmap masks use the full cell" or "All glyph outlines fit"),
      })
      :canvas({
        width = FontPreview.WIDTH,
        height = FontPreview.HEIGHT,
        onpaint = function(ev)
          FontPreview.paint(ev.context, job, sample)
        end,
      })
      :button({
        text = "Use font",
        focus = true,
        onclick = deps.guard(function()
          complete(job, true)
          d:close()
        end),
      })
      :show({ wait = false })
  end

  ---Replace font profile and rerender text cells on an existing layer.
  ---@param sprite Sprite Target document.
  ---@param layer Layer Target text layer.
  ---@param job table Completed font preparation job.
  ---@param allowClipping boolean Whether clipping is accepted.
  ---@param committed? fun() Callback after replacement is committed.
  local function replaceLayerWithJob(sprite, layer, job, allowClipping, committed)
    U.check(documentHasLayer(sprite, layer), "The document or layer was closed")
    Validate.requireValid(sprite, layer)
    local captured = job.replacementContext
    if captured then
      U.check(
        captured.sprite == sprite
          and captured.layer == layer
          and captured.signature == Edit.layerSignature(sprite, layer),
        "The layer changed after preparation; choose the replacement font again"
      )
    else
      Loader.ensureCharacters(job, Edit.characters(sprite, layer))
      job:finish()
    end
    app.sprite, app.layer = sprite, layer
    self.drawing:ensureActive()
    self.drawing:flush()
    app.transaction("Replace Textmode Font", function()
      local id = Profile.install(sprite, job, allowClipping)
      Edit.replaceFont(sprite, layer, id)
    end)
    self.drawing:invalidateStamps()
    self.drawing:ensureActive()
    self.drawing:prepareBoth()
    if committed then
      committed()
    end
    deps.invalidate()
  end

  ---Add a new textmode layer or create a sprite with the prepared font.
  ---@param target Sprite? Destination sprite or nil for new sprite.
  ---@param job table Completed font preparation job.
  ---@param allowClipping boolean Whether clipping is accepted.
  ---@param context? table Target geometry and layer context.
  ---@param committed? fun() Callback after layer is attached.
  local function addFontLayer(target, job, allowClipping, context, committed)
    local foregroundGlyph, backgroundGlyph = Profile.defaultStamps(job.glyphs)
    if target then
      local first = not Model.managed(target)
      context = context
        or {
          geometry = Model.managed(target) and U.copy(Model.geometry(target)) or nil,
          unmanaged = first,
          anchor = app.sprite == target and app.layer or nil,
        }
      context.foregroundGlyph, context.backgroundGlyph = foregroundGlyph, backgroundGlyph
      local drawing = self.drawing:snapshot()
      context.fg, context.bg = drawing.fg, first and "#00000000" or drawing.bg
      Model.attach(target, job, allowClipping, context)
      self.drawing:setColors(nil, nil, context.bg)
    else
      local defaults = Settings.read(deps.preferences or {}, library)
      Model.create(job, defaults.columns, defaults.rows, allowClipping)
    end
    if committed then
      committed()
    end
    self.drawing:setImportedStamps(foregroundGlyph, backgroundGlyph)
    deps.openPanel()
    self.drawing:prepareBoth()
  end

  -- Both add-layer entry points share target capture, sizing, preview, and commit.
  ---Open the font import workflow for a new or existing destination.
  ---@param libraryOnly boolean Whether the workflow requires an existing sprite.
  function self:importFont(libraryOnly)
    local key = libraryOnly and "addLayer" or "fonts"
    if deps.focusDialog and deps.focusDialog(key) then
      return
    end
    local target = app.sprite
    if target then
      Model.requireEligible(target)
    end
    if libraryOnly then
      U.check(target, "Open an RGB sprite first")
    end
    local g = target and Model.managed(target) and U.copy(Model.geometry(target)) or nil
    local sprite, layer = target, target and app.layer or nil
    local canReplace = target and Model.textLayer(target, layer) or false
    local context = target and { geometry = g, unmanaged = not g, anchor = layer } or nil
    local currentProfile = canReplace
        and Profile.index(sprite, Model.meta(layer).fontProfileId).profile
      or nil
    local d = deps.dialog(libraryOnly and "Add Textmode Layer" or "Fonts", { singleton = key })
    local catalog, candidate

    ---Retrieve currently chosen font entry from catalog combobox.
    ---@return table? font Catalog entry.
    local function selectedLibraryFont()
      return catalog and catalog.selected()
    end

    ---Update author label, links, and library error messages.
    local function updateLibraryMetadata()
      local font = selectedLibraryFont()
      d:modify({
        id = "fontAuthor",
        text = font and library:author(font) or "",
      })
      d:modify({ id = "authorLink", visible = font and font.authorUrl ~= nil or false })
      d:modify({ id = "sourceLink", visible = font and font.sourceUrl ~= nil or false })
      d:modify({ id = "libraryError", visible = library.error ~= nil })
      d:modify({ id = "libraryErrorDetail", visible = library.error ~= nil })
      if not libraryOnly then
        d:modify({ id = "saveToLibrary", enabled = not library.error })
      end
    end

    ---Inspect uploaded TTF file and extract metadata.
    ---@return table candidate Inspected font candidate.
    local function inspectUpload()
      local path = d.data.path
      if not candidate or candidate.path ~= path then
        candidate = nil
        d:modify({ id = "uploadAuthor", text = "Unknown" })
      end
      U.check(path ~= "" and path:lower():match("%.ttf$"), "Choose a .ttf font file")
      if not candidate or candidate.path ~= path then
        candidate = Loader.inspect(path)
        d:modify({ id = "displayName", text = candidate.name })
        d:modify({ id = "uploadAuthor", text = library:authorForCandidate(candidate) })
      end
      return candidate
    end

    ---Open author or source URL in default web browser.
    ---@param key string Link property ("authorUrl" or "sourceUrl").
    local function openLibraryLink(key)
      local font = selectedLibraryFont()
      U.check(font and font[key], "This font has no link for that field")
      app.command.Launch({ path = font[key] })
    end

    ---Toggle numeric cell dimension inputs based on sizing mode.
    local function updateCellInputs()
      local enabled = d.data.cellSizing == "Custom"
      deps.controls:setNumericEnabled(d, { "cellWidth", "cellHeight" }, enabled)
    end

    ---Commit font import or replacement after review.
    ---@param action string "replace" or "add".
    ---@param job table Prepared font job.
    ---@param staged? table Staged user font record.
    ---@param allowClipping boolean Whether clipping is allowed.
    local function finishImport(action, job, staged, allowClipping)
      if staged then
        library:checkStage(staged)
      end
      local function committed()
        if staged then
          library:commit(staged)
          refreshLibraries()
        end
      end
      if action == "replace" then
        replaceLayerWithJob(sprite, layer, job, allowClipping, committed)
      else
        addFontLayer(target, job, allowClipping, context, committed)
      end
      d:close()
    end

    local startImport = deps.guard(function(action)
      local data = d.data
      if target then
        Model.requireEligible(target)
      end
      if action == "replace" then
        U.check(
          canReplace and documentHasLayer(sprite, layer),
          "Select an Asemode layer to replace"
        )
      end
      local required, replacementSignature
      if action == "replace" then
        required = Edit.characters(sprite, layer)
        replacementSignature = Edit.layerSignature(sprite, layer)
      end
      local uploaded, selected, staged
      if not libraryOnly and data.source == "upload" then
        uploaded = inspectUpload()
        data = d.data
        local name = U.check(
          FontNames.clean(data.displayName),
          "Enter a display name of 1–128 characters without control characters"
        )
        if data.saveToLibrary then
          staged = library:stage(uploaded, name)
        end
      else
        selected = U.check(selectedLibraryFont(), "Choose a library font")
      end
      local geometry = action == "replace" and Model.geometry(sprite) or g
      local options = {
        cellWidth = geometry and geometry.cellWidth or nil,
        cellHeight = geometry and geometry.cellHeight or nil,
        pixelSize = data.size,
        antialias = data.aa,
      }
      if not geometry and data.cellSizing == "Custom" then
        options.cellWidth = U.integer(data.cellWidth, "Cell width", 1, 128)
        options.cellHeight = U.integer(data.cellHeight, "Cell height", 1, 128)
      end
      local job
      if uploaded then
        job = Loader.candidate(
          uploaded,
          staged and staged.name or FontNames.clean(data.displayName),
          options,
          staged and { kind = "user", id = staged.id, sha256 = staged.sha256 } or nil
        )
        if staged and staged.duplicate then
          app.alert({
            text = {
              "This font is already in your Library.",
              "Its existing name will be used.",
            },
          })
        end
      else
        job = library:job(selected, options)
      end
      if required then
        Loader.ensureCharacters(job, required)
        job.replacementContext =
          { sprite = sprite, layer = layer, signature = replacementSignature }
      end
      self:runJobs({ job }, function()
        self:preview(job, function(_, allowClipping)
          finishImport(action, job, staged, allowClipping)
        end, target)
      end)
    end)
    if not libraryOnly then
      d:tab({ id = "library", text = "Library" })
    end
    catalog =
      self:libraryControl(d, "bundledFont", updateLibraryMetadata, nil, updateLibraryMetadata)
    d:label({ id = "fontAuthor", label = "Author", text = "" })
      :button({
        id = "authorLink",
        text = "Author website",
        onclick = function()
          openLibraryLink("authorUrl")
        end,
      })
      :button({
        id = "sourceLink",
        text = "Font source",
        onclick = function()
          openLibraryLink("sourceUrl")
        end,
      })
    if not libraryOnly then
      d:tab({ id = "upload", text = "Upload .ttf" })
        :file({
          id = "path",
          label = "TTF font",
          title = "Choose a TrueType font",
          open = true,
          filetypes = { "ttf" },
          onchange = deps.guard(inspectUpload),
        })
        :entry({ id = "displayName", label = "Display name", text = "" })
        :label({ id = "uploadAuthor", label = "Author", text = "Unknown" })
        :check({ id = "saveToLibrary", text = "Save to Library", selected = true })
        :endtabs({ id = "source", selected = "library" })
    end
    deps.controls
      :addFontSizeInput(d, currentProfile and tostring(currentProfile.pixelSize) or "8")
      :check({
        id = "aa",
        label = "Rendering",
        text = "Antialias outlines",
        selected = currentProfile and currentProfile.antialias or false,
      })
    if not g then
      d:combobox({
        id = "cellSizing",
        label = "Cell dimensions",
        options = { "Automatic", "Custom" },
        option = "Automatic",
        onchange = updateCellInputs,
      })
      deps.controls:addNumericInput(
        d,
        "cellWidth",
        "Cell width (pixels)",
        "8",
        { min = 1, max = 128, enabled = false }
      )
      deps.controls:addNumericInput(
        d,
        "cellHeight",
        "Cell height (pixels)",
        "8",
        { min = 1, max = 128, enabled = false }
      )
    end
    d:newrow()
    d:button({
      id = "addLayer",
      text = "Add layer..",
      enabled = target ~= nil,
      focus = true,
      onclick = function()
        startImport("add")
      end,
    })
    if not libraryOnly then
      d:samerow():button({
        id = "replaceLayerFont",
        text = "Replace layer font..",
        enabled = canReplace,
        onclick = function()
          startImport("replace")
        end,
      })
    end
    if not libraryOnly then
      d:newrow():button({
        id = "manageUserFonts",
        text = "Manage user fonts..",
        onclick = function()
          manageUserFonts()
        end,
      })
    elseif library.error then
      d:newrow()
    end
    d:label({
      id = "libraryError",
      text = "Saved Library unavailable.",
      visible = library.error ~= nil,
    })
    d:newrow()
    d:label({
      id = "libraryErrorDetail",
      text = "Open <Manage user fonts..> to reset it.",
      visible = library.error ~= nil,
    })
    if library.error and not libraryOnly then
      d:modify({ id = "saveToLibrary", selected = false, enabled = false })
    end
    catalog.refresh()
    d:show({ wait = false, autoscrollbars = true })
  end

  ---Open the font workflow for adding a text layer.
  function self:addLayer()
    self:importFont(true)
  end

  return self
end
return M
