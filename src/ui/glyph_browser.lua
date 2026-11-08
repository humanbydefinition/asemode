local U = require("src.core.util")
local Profile = require("src.document.profile")
local UnicodeBlocks = require("src.unicode.blocks")
local UnicodeNames = require("src.unicode.names")
local Settings = require("src.core.settings")
local Transforms = require("src.document.transforms")
local Theme = require("src.ui.theme")
local M = {}
local GRID_CELL_SIZES, GRID_CELL_DEFAULT = Settings.GRID_CELL_SIZES, Settings.GRID_CELL_DEFAULT
local GRID_PADDING, SCROLL_WIDTH, SCROLL_GAP, SCROLL_GUTTER = 4, 8, 3, 3
local SCROLL_TRACK_WIDTH = 9
local GRID_MIN_COLUMNS = 6
local GRID_DEFAULT_COLUMNS, GRID_DEFAULT_ROWS = 8, 6
local GRID_MIN_WIDTH = GRID_MIN_COLUMNS * GRID_CELL_DEFAULT
  + 2 * GRID_PADDING
  + SCROLL_TRACK_WIDTH
  + SCROLL_GAP
  + SCROLL_GUTTER
local GRID_MIN_ROWS = 4
local GRID_MIN_HEIGHT = GRID_MIN_ROWS * GRID_CELL_DEFAULT + 2 * GRID_PADDING

---Find the nearest valid grid cell size from supported presets.
---@param value any Target numeric size.
---@return integer size Closest supported grid cell size.
local function validGridCellSize(value)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return GRID_CELL_DEFAULT
  end
  local nearest, distance
  for _, size in ipairs(GRID_CELL_SIZES) do
    local nextDistance = math.abs(value - size)
    if not distance or nextDistance < distance then
      nearest, distance = size, nextDistance
    end
  end
  return nearest
end

---Organize font glyphs into Unicode block groups ordered by first codepoint.
---@param index table Font profile index table.
---@return table[] groups List of groups with name and glyph keys.
local function unicodeGroups(index)
  local byName, first = {}, {}
  for _, key in ipairs(index.supportedOrder) do
    local cp = utf8.codepoint(key)
    for _, block in ipairs(UnicodeBlocks) do
      if cp >= block.first and cp <= block.last then
        local group = byName[block.name]
        if not group then
          group = { name = block.name, glyphs = {} }
          byName[block.name] = group
          first[block.name] = cp
        end
        group.glyphs[#group.glyphs + 1] = key
        break
      end
    end
  end
  local groups = {}
  for _, group in pairs(byName) do
    groups[#groups + 1] = group
  end
  table.sort(groups, function(a, b)
    return first[a.name] < first[b.name]
  end)
  return groups
end

---Create a glyph browser using the supplied selection and repaint callbacks.
---@param options table Grid size and host callbacks.
---@return table browser Glyph browser.
function M.new(options)
  local self = {
    index = nil,
    groupList = {},
    filtered = {},
    previews = {},
    currentScrollRow = 0,
    gridLayoutCellSize = validGridCellSize(options.gridCellSize),
    query = "",
    groupName = "All characters",
  }

  ---Bind an active font profile index and rebuild character groups.
  ---@param index table? Font profile index table or nil.
  function self:setProfile(index)
    if self.index == index then
      return
    end
    self.index, self.groupList, self.filtered, self.previews = index, {}, {}, {}
    self.filterValid = false
    self.previewKey = nil
    if index then
      self.groupList = unicodeGroups(index)
      if #index.missingOrder > 0 then
        self.groupList[#self.groupList + 1] =
          { name = "Missing in font", glyphs = index.missingOrder }
      end
    end
  end

  ---Filter visible glyphs by search query and group category.
  ---@param query? string Substring or codepoint query.
  ---@param groupName? string Category group name.
  function self:setQuery(query, groupName)
    query, groupName = (query or ""):lower(), groupName or "All characters"
    if self.filterValid and self.query == query and self.groupName == groupName then
      return
    end
    self.query, self.groupName, self.filtered, self.filterValid = query, groupName, {}, true
    if self.index then
      local selected
      for _, group in ipairs(self.groupList) do
        if group.name == groupName then
          selected = group
          break
        end
      end
      local order = selected and selected.glyphs or self.index.supportedOrder
      for _, key in ipairs(order) do
        local cp = utf8.codepoint(key)
        local missingMatch = groupName == "Missing in font"
          and (query == key:lower() or tonumber(query:match("^u%+(%x+)$") or "", 16) == cp)
        if self.index.glyphs[key] and (UnicodeNames.matches(cp, query) or missingMatch) then
          self.filtered[#self.filtered + 1] = key
        end
      end
    end
    self.currentScrollRow = math.max(0, math.min(self.currentScrollRow, self:maxScrollRow()))
  end

  ---Change the display size of glyph cells in the grid.
  ---@param value any Target numeric cell size.
  ---@return integer size Applied cell size.
  function self:setGridCellSize(value)
    self.gridLayoutCellSize = validGridCellSize(value)
    return self.gridLayoutCellSize
  end

  ---Find the glyph key under pixel coordinates in the grid.
  ---@param x number Horizontal coordinate relative to canvas.
  ---@param y number Vertical coordinate relative to canvas.
  ---@return string? key Glyph key if hit.
  function self:glyphAt(x, y)
    local grid = self.gridLayout
    if not grid then
      return nil
    end
    x, y = x - grid.x, y - grid.y
    if x < 0 or y < 0 or x >= grid.width or y >= grid.height then
      return nil
    end
    return self.filtered[self.currentScrollRow * grid.columns + y // self.gridLayoutCellSize * grid.columns + x // self.gridLayoutCellSize + 1]
  end

  ---Check whether coordinates fall inside the scrollbar track.
  ---@param grid table Grid layout metrics.
  ---@param x number Horizontal coordinate.
  ---@param y number Vertical coordinate.
  ---@return boolean hit True if hit.
  local function trackAt(grid, x, y)
    return x >= grid.trackX - SCROLL_GAP
      and x < grid.trackX + SCROLL_TRACK_WIDTH
      and y >= grid.trackY
      and y < grid.trackY + grid.trackHeight
  end

  ---Handle mouse down event for glyph selection or scrollbar interaction.
  ---@param ev table Mouse event.
  function self:handleMouseDown(ev)
    local grid = self.gridLayout
    if not grid then
      return
    end
    if trackAt(grid, ev.x, ev.y) then
      local thumbY, thumbHeight = self:scrollMetrics()
      if self:maxScrollRow() == 0 or ev.button ~= MouseButton.LEFT then
        return
      end
      if ev.y >= thumbY and ev.y < thumbY + thumbHeight then
        self.scrollbarDrag = ev.y - thumbY
      else
        self:setScrollRow(self.currentScrollRow + (ev.y < thumbY and -grid.rows or grid.rows))
      end
      return
    end
    local key = self:glyphAt(ev.x, ev.y)
    if key then
      options.select(key, ev.button)
    end
  end

  function self:handleMouseMove(ev)
    local grid = self.gridLayout
    if not grid then
      return
    end
    local key = self:glyphAt(ev.x, ev.y)
    if key ~= self.hoverGlyph then
      self.hoverGlyph = key
      local source = self.index and self.index.glyphs[key]
      if source and source.meta.renderFallback then
        local cp = utf8.codepoint(key)
        options.tooltip(
          string.format(
            "U+%04X · %s · Missing in font · shown as space",
            cp,
            UnicodeNames.name(cp) or "Unnamed character"
          )
        )
      end
    end
    local hot = trackAt(grid, ev.x, ev.y)
    if self.scrollbarHot ~= hot then
      self.scrollbarHot = hot
      options.changed()
    end
    if self.scrollbarDrag ~= nil then
      self:scrollToThumb(ev.y - self.scrollbarDrag)
    end
  end

  ---Handle mouse release to terminate scrollbar thumb drag.
  function self:handleMouseUp()
    self.scrollbarDrag = nil
    options.changed()
  end

  ---Scroll the grid vertically on mouse wheel motion.
  ---@param ev table Mouse wheel event.
  function self:handleWheel(ev)
    if ev.deltaY ~= 0 then
      self:setScrollRow(self.currentScrollRow + (ev.deltaY > 0 and 1 or -1))
    end
  end

  ---Compute grid column, row, and scrollbar layout for given canvas dimensions.
  ---@param width number Canvas pixel width.
  ---@param height number Canvas pixel height.
  function self:layoutGrid(width, height)
    local old = self.gridLayout
    local cell = self.gridLayoutCellSize
    local available =
      math.max(cell, width - 2 * GRID_PADDING - SCROLL_TRACK_WIDTH - SCROLL_GAP - SCROLL_GUTTER)
    local columns = math.max(1, available // cell)
    local rows = math.max(1, (height - 2 * GRID_PADDING) // cell)
    self.gridLayout = {
      columns = columns,
      rows = rows,
      canvasWidth = width,
      canvasHeight = height,
      x = GRID_PADDING + (available - columns * cell) // 2,
      y = GRID_PADDING,
      width = columns * cell,
      height = rows * cell,
      trackX = width - GRID_PADDING - SCROLL_GUTTER - SCROLL_TRACK_WIDTH,
      trackY = GRID_PADDING,
      trackHeight = math.max(1, height - 2 * GRID_PADDING),
    }
    if old and old.columns ~= columns then
      -- Keep the same part of the font in view when columns wrap.
      self.currentScrollRow = self.currentScrollRow * old.columns // columns
    end
    self.currentScrollRow = math.min(self.currentScrollRow, self:maxScrollRow())
    if old and (old.columns ~= columns or old.rows ~= rows) then
      self.scrollbarDrag = nil
    end
  end

  ---Compute maximum vertical scroll row offset.
  ---@return integer maxRow Maximum allowed scroll row.
  function self:maxScrollRow()
    local grid = self.gridLayout
    return math.max(
      0,
      math.ceil(#self.filtered / (grid and grid.columns or GRID_DEFAULT_COLUMNS))
        - (grid and grid.rows or GRID_DEFAULT_ROWS)
    )
  end

  ---Clamp and apply new vertical scroll row position.
  ---@param row number Requested row offset.
  function self:setScrollRow(row)
    self.currentScrollRow = math.max(0, math.min(self:maxScrollRow(), math.floor(row)))
    options.changed()
  end

  ---Calculate vertical geometry and travel distance for the scrollbar thumb.
  ---@return integer thumbY Vertical start coordinate of the thumb.
  ---@return integer thumbHeight Height of thumb in pixels.
  ---@return integer travel Total allowable travel distance.
  ---@return integer maxRow Maximum row offset.
  function self:scrollMetrics()
    local grid = self.gridLayout
    local maxRow = self:maxScrollRow()
    local thumbHeight = math.min(
      grid.trackHeight,
      math.max(
        18,
        math.floor(
          grid.trackHeight
            * grid.rows
            / math.max(grid.rows, math.ceil(#self.filtered / grid.columns))
        ) + 2
      )
    )
    local travel = grid.trackHeight - thumbHeight
    local thumbY = grid.trackY
    if maxRow > 0 and travel > 0 then
      thumbY = thumbY + math.floor(self.currentScrollRow / maxRow * travel + 0.5)
    end
    return thumbY, thumbHeight, travel, maxRow
  end

  ---Scroll the grid according to a pixel coordinate on the scrollbar track.
  ---@param y number Target vertical pixel position.
  function self:scrollToThumb(y)
    local _, _, travel, maxRow = self:scrollMetrics()
    if maxRow == 0 or travel <= 0 then
      return
    end
    local position = math.max(0, math.min(travel, y - self.gridLayout.trackY))
    self:setScrollRow(position / travel * maxRow + 0.5)
  end

  ---Paint the visible grid of glyph cells, active selections, and scrollbar.
  ---@param ev table Canvas paint event with graphics context.
  ---@param drawing table Drawing session snapshot containing selected glyphs and colors.
  function self:paint(ev, drawing)
    local key = drawing.fg
      .. "\0"
      .. drawing.bg
      .. "\0"
      .. drawing.flags
      .. "\0"
      .. (drawing.outline or "none")
    if key ~= self.previewKey then
      self.previews = {}
      self.previewKey = key
    end
    local gc = ev.context
    self:layoutGrid(gc.width, gc.height)
    local grid = self.gridLayout
    Theme.previewSurface(gc, nil, GRID_PADDING)
    if not self.index then
      return
    end
    local cell = self.gridLayoutCellSize
    local visible = {}
    for n = 0, grid.columns * grid.rows - 1 do
      local key = self.filtered[self.currentScrollRow * grid.columns + n + 1]
      if not key then
        break
      end
      local x, y = grid.x + n % grid.columns * cell + 1, grid.y + n // grid.columns * cell + 1
      local source = self.index.glyphs[key]
      if source then
        visible[key] = true
        local image = self.previews[key]
        if not image then
          local mask = source.tile.image
          local transformed = drawing.flags ~= 0 and Transforms.renderMask(mask, drawing.flags)
            or mask
          image = Profile.colorize(transformed, drawing.fg, drawing.bg, drawing.outline)
          self.previews[key] = image
        end
        local previewSize = math.max(1, cell - 4)
        local scale = math.min(previewSize / image.width, previewSize / image.height)
        local w, h =
          math.max(1, math.floor(image.width * scale)),
          math.max(1, math.floor(image.height * scale))
        gc:drawImage(
          image,
          Rectangle(0, 0, image.width, image.height),
          Rectangle(x + (cell - 2 - w) // 2, y + (cell - 2 - h) // 2, w, h)
        )
        Theme.glyphSelection(gc, x, y, cell, key == drawing.glyph, key == drawing.bgGlyph)
      end
    end
    for key in pairs(self.previews) do
      if not visible[key] then
        self.previews[key] = nil
      end
    end
    if self:maxScrollRow() > 0 then
      local thumbY, thumbHeight = self:scrollMetrics()
      local suffix = (self.scrollbarHot or self.scrollbarDrag ~= nil) and "_hot" or ""
      gc.color = gc.theme.color.editor_face
      gc:fillRect(
        Rectangle(grid.trackX + SCROLL_TRACK_WIDTH, grid.trackY, SCROLL_GUTTER, grid.trackHeight)
      )
      gc:drawThemeRect(
        "mini_scrollbar_bg" .. suffix,
        Rectangle(grid.trackX, grid.trackY, SCROLL_TRACK_WIDTH, grid.trackHeight)
      )
      gc:drawThemeRect(
        "mini_scrollbar_thumb" .. suffix,
        Rectangle(grid.trackX, thumbY, SCROLL_WIDTH, thumbHeight)
      )
    end
  end

  ---Format character name and pagination range for the info strip.
  ---@param drawing table Drawing session snapshot.
  ---@return string name Descriptive character or stamp name.
  ---@return string range Formatted pagination count string.
  function self:glyphInfo(drawing)
    local columns = self.gridLayout and self.gridLayout.columns or GRID_DEFAULT_COLUMNS
    local rows = self.gridLayout and self.gridLayout.rows or GRID_DEFAULT_ROWS
    local first = #self.filtered > 0 and self.currentScrollRow * columns + 1 or 0
    local last = math.min(#self.filtered, (self.currentScrollRow + rows) * columns)
    -- Keep this UI text in the native bitmap font: an en dash selects a
    -- fallback font with different baseline metrics in Aseprite.
    local range = first == 0 and "0 glyphs"
      or string.format("%d-%d of %d glyphs", first, last, #self.filtered)
    if drawing.primaryEmpty then
      return "NO PRIMARY STAMP", range
    end
    local codepoint = utf8.codepoint(drawing.glyph)
    local name = UnicodeNames.name(codepoint) or "UNKNOWN CHARACTER"
    if drawing.outline and drawing.outline ~= "none" then
      name = string.format("%s (%s outline)", name, drawing.outline)
    end
    if
      self.index
      and self.index.glyphs[drawing.glyph]
      and self.index.glyphs[drawing.glyph].meta.renderFallback
    then
      name = string.format("U+%04X · %s · Missing in font · shown as space", codepoint, name)
    end
    return name, range
  end

  ---Handle keyboard navigation shortcuts across grid pages and rows.
  ---@param ev table Key event.
  ---@return boolean handled True if key navigated the browser.
  function self:navigateGlyphs(ev)
    if
      not self.gridLayout
      or ev.altKey
      or ev.ctrlKey
      or ev.metaKey
      or ev.shiftKey
      or ev.spaceKey
    then
      return false
    end
    local row, code = self.currentScrollRow, ev.code
    if code == "ArrowDown" then
      row = row + 1
    elseif code == "ArrowUp" then
      row = row - 1
    elseif code == "PageDown" then
      row = row + self.gridLayout.rows
    elseif code == "PageUp" then
      row = row - self.gridLayout.rows
    elseif code == "Home" then
      row = 0
    elseif code == "End" then
      row = self:maxScrollRow()
    else
      return false
    end
    self:setScrollRow(row)
    ev:stopPropagation()
    return true
  end

  ---Return the current grid cell size in pixels.
  ---@return integer size Grid cell pixel size.
  function self:cellSize()
    return self.gridLayoutCellSize
  end

  ---Return the minimum allowable width for the glyph canvas.
  ---@return integer width Minimum width in pixels.
  function self:minimumWidth()
    return GRID_MIN_WIDTH
  end

  ---Return default canvas width matching standard column presets.
  ---@return integer width Default width in pixels.
  function self:defaultWidth()
    return GRID_DEFAULT_COLUMNS * GRID_CELL_DEFAULT
      + 2 * GRID_PADDING
      + SCROLL_TRACK_WIDTH
      + SCROLL_GAP
      + SCROLL_GUTTER
      + 3
  end

  ---Return minimum allowable height for the canvas.
  ---@return integer height Minimum height in pixels.
  function self:minimumHeight()
    return GRID_MIN_HEIGHT
  end

  ---Forward layout computation for given dimensions.
  ---@param width number Canvas width.
  ---@param height number Canvas height.
  function self:layout(width, height)
    self:layoutGrid(width, height)
  end

  ---Return a copy of the current grid layout metrics.
  ---@return table? geometry Layout geometry table.
  function self:geometry()
    return self.gridLayout and U.copy(self.gridLayout) or nil
  end

  ---Return names of all available character groups.
  ---@return string[] groups List of group names.
  function self:groups()
    local out = {}
    for i, group in ipairs(self.groupList) do
      out[i] = group.name
    end
    return out
  end

  ---Return list of currently filtered glyph keys.
  ---@return string[] keys Filtered glyph keys.
  function self:keys()
    return U.copy(self.filtered)
  end

  ---Check whether an active font profile is bound.
  ---@return boolean has True if font profile exists.
  function self:hasProfile()
    return self.index ~= nil
  end

  ---Return display name of active font profile.
  ---@return string? name Font display name.
  function self:profileName()
    return self.index and self.index.profile.name
  end

  ---Return current vertical scroll row.
  ---@return integer row Current row offset.
  function self:scrollRow()
    return self.currentScrollRow
  end

  ---Format character information for display.
  ---@param drawing table Drawing session snapshot.
  ---@return string name Character name.
  ---@return string range Pagination range.
  function self:information(drawing)
    return self:glyphInfo(drawing)
  end

  ---Handle key down navigation.
  ---@param ev table Key event.
  ---@return boolean handled True if key was handled.
  function self:handleKeyDown(ev)
    return self:navigateGlyphs(ev)
  end

  ---Clear active profile, cached previews, and scrollbar state.
  function self:clear()
    self:setProfile(nil)
    self.scrollbarDrag, self.scrollbarHot = nil, false
  end

  return self
end

return M
