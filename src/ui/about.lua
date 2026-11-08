local U = require("src.core.util")
local Fonts = require("src.fonts.bundled")
local TTF = require("src.fonts.truetype")
local Metrics = require("src.core.metrics")
local Render = require("src.fonts.render")
local Loader = require("src.fonts.loader")
local Theme = require("src.ui.theme")
local M = {}
local TITLE, REEL = "ASEMODE", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
local STEP_SECONDS, STAGGER_SECONDS = 0.048, 0.013
local SPECIMEN_ROW_GAP = 4

-- Render only the specimen, without creating a document, tileset, or brush.
---Render a text specimen image from a font without altering the document.
---@param id string Font identifier.
---@param text string|string[] Specimen sample lines.
---@param bytes? string Optional font byte content.
---@return Image image Rendered specimen raster.
local function specimen(id, text, bytes)
  local font = TTF.parse(bytes or Loader.resource(id).bytes)
  local rows, supported, width = {}, {}, 0
  for _, line in ipairs(type(text) == "table" and text or { text }) do
    local row = {}
    for _, cp in utf8.codes(line) do
      local key = utf8.char(cp)
      row[#row + 1] = key
      if font.mapping[cp] then
        supported[#supported + 1] = key
      end
    end
    rows[#rows + 1] = row
    width = math.max(width, #row)
  end
  local keys = table.concat(supported)
  U.check(keys ~= "", "No specimen characters available")
  local glyphs = font:characters(keys)
  local profile = Metrics.measure(font, glyphs, { pixelSize = 8 })
  local masks = {}
  for _, glyph in ipairs(glyphs) do
    masks[glyph.glyphKey] = Render.mask(glyph, profile)
  end
  local image = Image(
    (profile.cellWidth + 1) * width - 1,
    profile.cellHeight * #rows + SPECIMEN_ROW_GAP * (#rows - 1),
    ColorMode.RGB
  )
  for rowIndex, row in ipairs(rows) do
    for columnIndex, key in ipairs(row) do
      if masks[key] then
        image:drawImage(
          masks[key],
          Point(
            (columnIndex - 1) * (profile.cellWidth + 1),
            (rowIndex - 1) * (profile.cellHeight + SPECIMEN_ROW_GAP)
          )
        )
      end
    end
  end
  return image
end

---Paint a font specimen into a canvas context.
---@param ev table Canvas paint event with graphics context.
---@param image Image? Rendered specimen image.
---@param maxScale number Maximum allowable scale factor.
local function paintSpecimen(ev, image, maxScale)
  local gc = ev.context
  Theme.previewSurface(gc)
  if not image then
    gc.color = Theme.placeholderColor(gc.theme.color)
    local text = "Preview unavailable"
    Theme.drawCenteredText(gc, { x = 0, y = 0, width = gc.width, height = gc.height }, text)
    return
  end
  local _, w, h = Theme.fitScale(maxScale, gc.width - 24, gc.height - 24, image.width, image.height)
  gc:drawImage(
    image,
    Rectangle(0, 0, image.width, image.height),
    Rectangle((gc.width - w) // 2, (gc.height - h) // 2, w, h)
  )
end

---Open the About dialog for the controller.
---@param controller table Controller providing the dialog and font library.
function M.open(controller)
  if controller.focusDialog and controller:focusDialog("about") then
    return
  end
  if controller.aboutPanel then
    controller.aboutPanel:show({ wait = false })
    return
  end
  local d, animationTimer, banner, reel, sample
  local cache = {}

  ---Stop header animation timer if active.
  local function stopAnimation()
    if animationTimer then
      animationTimer:stop()
      animationTimer = nil
    end
  end
  d = controller:dialog("About", {
    singleton = "about",
    onclose = function()
      stopAnimation()
      cache, banner, reel, sample = {}, nil, nil, nil
      controller.aboutPanel = nil
    end,
  })
  controller.aboutPanel = d
  local options, byName, authors = {}, {}, {}
  for _, registered in ipairs(Fonts) do
    local font = U.copy(registered)
    font.userId = controller.library:matchingUser(font)
    local suffix = font.userId and " (User)"
      or (font.available == false and " (Not installed)" or "")
    local label = font.name .. suffix
    options[#options + 1] = label
    byName[label] = font
    authors[font.author] = true
  end
  local authorCount = 0
  for _ in pairs(authors) do
    authorCount = authorCount + 1
  end
  banner = specimen("unscii-8", TITLE)
  reel = specimen("unscii-8", REEL)
  local run, nextRun, flutter = nil, 0, 0
  local positions = {}
  for i = 1, #TITLE do
    positions[i] = REEL:find(TITLE:sub(i, i), 1, true) - 1
  end

  ---Paint animated or static wordmark header.
  ---@param ev table Canvas paint event with graphics context.
  local function paintWordmark(ev)
    if not run or not reel then
      paintSpecimen(ev, banner, 2)
      return
    end
    local gc = ev.context
    Theme.previewSurface(gc)
    local cellWidth, cellHeight = (reel.width + 1) // #REEL - 1, reel.height
    local scale = math.max(1, math.min(2, math.floor((gc.width - 24) / banner.width)))
    local width, height = cellWidth * scale, cellHeight * scale
    local left, top = (gc.width - banner.width * scale) // 2, (gc.height - height) // 2
    local elapsed = os.clock() - run.started
    for i, position in ipairs(positions) do
      local localTime = math.max(0, elapsed - (run.single and 0 or (i - 1) * STAGGER_SECONDS))
      local steps = (not run.single or run.single == i) and #REEL or 0
      local count = math.min(steps, math.floor(localTime / STEP_SECONDS))
      local current = (position + count) % #REEL
      local x = left + (i - 1) * (cellWidth + 1) * scale
      gc:drawImage(
        reel,
        Rectangle(current * (cellWidth + 1), 0, cellWidth, cellHeight),
        Rectangle(x, top, width, height)
      )
    end
  end

  ---Start or stop header reel flutter animation.
  ---@param enabled boolean Whether animation is active.
  local function setAnimation(enabled)
    stopAnimation()
    run = nil
    if enabled and banner and reel and app.isUIAvailable then
      nextRun, flutter = os.clock() + 0.9, 0
      animationTimer = Timer({
        interval = 0.024,
        ontick = function()
          local now = os.clock()
          if not run and now >= nextRun then
            run =
              { started = now, single = flutter > 0 and ((flutter * 7 + 3) % #TITLE + 1) or nil }
            flutter = flutter + 1
          end
          if run then
            local duration = #REEL * STEP_SECONDS
              + (run.single and 0 or (#TITLE - 1) * STAGGER_SECONDS)
            if now - run.started >= duration then
              run = nil
              nextRun = now + 2.2
            end
            d:repaint()
          end
        end,
      })
      animationTimer:start()
    end
    d:repaint()
  end

  ---Retrieve font definition currently selected in the dialog combobox.
  ---@return table font Selected font descriptor.
  local function selectedFont()
    return byName[d.data.font] or Fonts[1]
  end

  ---Resolve cached font specimen raster.
  ---@param font table Font descriptor.
  ---@return Image? specimen Cached or rendered specimen image.
  local function resolveSpecimen(font)
    if cache[font.file] == nil then
      if font.userId then
        local ok, resource = pcall(function()
          return controller.library:resource(font.userId, font.sourceSha256)
        end)
        if ok then
          cache[font.file] = specimen(font.id, { "AaBb 0123", "CcDd @#?!" }, resource.bytes)
        end
      elseif font.available ~= false then
        cache[font.file] = specimen(font.id, { "AaBb 0123", "CcDd @#?!" })
      end
    end
    return cache[font.file]
  end

  ---Update dialog UI with details of the selected font.
  local function updateFont()
    local font = selectedFont()
    sample = resolveSpecimen(font)
    d:modify({ id = "fontAuthor", text = string.format("Created by %s", font.author) })
    d:modify({
      id = "sampleInfo",
      text = sample and "A little of this font's personality, at 8 pixels."
        or "Visit the font source or check your Library.",
    })
    d:repaint()
  end

  ---Launch external URL associated with the selected font.
  ---@param key string Property key for URL ("authorUrl" or "sourceUrl").
  local function openLink(key)
    app.command.Launch({ path = selectedFont()[key] })
  end
  local animateHeader = controller.plugin.preferences.aboutAnimation
  if animateHeader == nil then
    animateHeader = controller.plugin.preferences.creditsAnimation
  end
  sample = resolveSpecimen(Fonts[1])
  d:canvas({
    id = "wordmark",
    width = 200,
    height = 64,
    vexpand = false,
    onpaint = paintWordmark,
  })
    :tab({ id = "asemode", text = "Asemode" })
    :label({ text = "A home for textmode art in Aseprite." })
    :separator({ text = "Created by" })
    :label({ text = "humanbydefinition" })
    :separator({ text = "Made possible by" })
    :label({ text = "The artists behind the registered fonts." })
    :newrow()
    :label({
      text = string.format("%d fonts, %d authors, a whole lot of character.", #Fonts, authorCount),
    })
    :newrow()
    :label({ text = "Explore their work in the Fonts tab." })
    :button({
      text = "Third-party notices",
      onclick = controller:guard(function()
        app.command.Launch({ path = controller.plugin.path .. "/THIRD_PARTY_NOTICES.md" })
      end),
    })
    :separator({ text = "Find us online" })
    :button({
      text = "GitHub",
      onclick = controller:guard(function()
        app.command.Launch({ path = "https://github.com/humanbydefinition/Asemode" })
      end),
    })
    :button({
      text = "itch.io",
      onclick = controller:guard(function()
        app.command.Launch({ path = "https://humanbydefinition.itch.io/asemode" })
      end),
    })
    :button({
      text = "Discord",
      onclick = controller:guard(function()
        app.command.Launch({ path = "https://discord.gg/sjrw8QXNks" })
      end),
    })
    :tab({ id = "fonts", text = "Fonts" })
    :combobox({
      id = "font",
      options = options,
      option = options[1],
      onchange = updateFont,
    })
    :label({ id = "fontAuthor", text = string.format("Created by %s", Fonts[1].author) })
    :canvas({
      id = "fontSpecimen",
      width = 180,
      height = 80,
      vexpand = false,
      onpaint = function(ev)
        paintSpecimen(ev, sample, 4)
      end,
    })
    :label({ id = "sampleInfo", text = "Choose a font to explore its characters." })
    :button({
      text = "Author website",
      onclick = controller:guard(function()
        openLink("authorUrl")
      end),
    })
    :button({
      text = "Font source",
      onclick = controller:guard(function()
        openLink("sourceUrl")
      end),
    })
    :endtabs({ id = "aboutTab", selected = "asemode" })
    :newrow()
    :label({ text = "", hexpand = true })
    :samerow()
    :check({
      id = "animateHeader",
      text = "Animate header",
      hexpand = false,
      selected = animateHeader ~= false,
      onclick = function()
        local enabled = d.data.animateHeader
        controller.plugin.preferences.aboutAnimation = enabled
        controller.plugin.preferences.creditsAnimation = nil
        setAnimation(enabled)
      end,
    })
  updateFont()
  d:show({ wait = false })
  setAnimation(animateHeader ~= false)
end

return M
