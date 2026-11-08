local M = {}

-- Canvas surfaces are cached by Aseprite, so callers must repaint after a
-- change. Read colors at paint time instead of caching a light or dark palette.
---Build a signature from the theme colors used by Asemode.
---@param theme Theme Aseprite theme to inspect.
---@return string signature Color signature used to detect changes.
function M.signature(theme)
  local values = {}
  for _, id in ipairs({
    "window_face",
    "editor_face",
    "text",
    "selected",
    "selected_text",
    "button_normal_text",
    "button_hot_text",
    "button_selected_text",
    "disabled",
  }) do
    local c = theme.color[id]
    values[#values + 1] = string.format("%d,%d,%d,%d", c.red, c.green, c.blue, c.alpha)
  end
  return table.concat(values, ";")
end

---Paint the themed background of a preview canvas or well.
---@param gc GraphicsContext Canvas graphics context.
---@param rect? Rectangle|table Bounding rectangle or coordinates.
---@param inset? integer Inset border width; defaults to 3.
function M.previewSurface(gc, rect, inset)
  rect = rect or { x = 0, y = 0, width = gc.width, height = gc.height }
  inset = inset or 3
  gc:drawThemeRect("sunken_normal", Rectangle(rect.x, rect.y, rect.width, rect.height))
  gc.color = gc.theme.color.editor_face
  gc:fillRect(
    Rectangle(
      rect.x + inset,
      rect.y + inset,
      math.max(0, rect.width - 2 * inset),
      math.max(0, rect.height - 2 * inset)
    )
  )
end

---Draw text centered within a rectangle, optionally at a fixed y coordinate.
---@param gc GraphicsContext Canvas graphics context.
---@param rect Rectangle|table Bounding container rectangle.
---@param text string Text string to draw.
---@param y? integer Optional fixed vertical coordinate.
function M.drawCenteredText(gc, rect, text, y)
  local measured = gc:measureText(text)
  local x = rect.x + (rect.width - measured.width) // 2
  local textY = y or (rect.y + (rect.height - (measured.height or 8)) // 2)
  gc:fillText(text, x, textY)
end

---Fit source dimensions within the available area using integer enlargement.
---@param maxScale number Maximum allowable scale factor.
---@param availW number Available horizontal pixel width.
---@param availH number Available vertical pixel height.
---@param srcW number Source unscaled width.
---@param srcH number Source unscaled height.
---@return number scale Chosen scale factor.
---@return integer width Scaled integer width.
---@return integer height Scaled integer height.
function M.fitScale(maxScale, availW, availH, srcW, srcH)
  local scale = math.min(maxScale, availW / srcW, availH / srcH)
  if scale >= 1 then
    scale = math.floor(scale)
  end
  return scale, math.max(1, math.floor(srcW * scale)), math.max(1, math.floor(srcH * scale))
end

---Paint a native Aseprite progress bar with split-clipped percentage label.
---@param gc GraphicsContext Canvas graphics context.
---@param fraction number Progress ratio in [0, 1].
function M.progressBar(gc, fraction)
  local w, h = gc.width, gc.height
  local clamped = math.max(0, math.min(1, tonumber(fraction) or 0))
  local percent = math.floor(clamped * 100 + 0.5)
  local splitX = math.floor(w * clamped + 0.5)
  local colors = gc.theme.color

  gc.color = colors.window_face
  gc:fillRect(Rectangle(0, 0, w, h))

  local rect = Rectangle(0, 0, w, h)
  if percent <= 0 then
    gc:drawThemeRect("slider_empty", rect)
  elseif percent >= 100 then
    gc:drawThemeRect("slider_full", rect)
  else
    gc:save()
    gc:beginPath()
    gc:rect(Rectangle(0, 0, splitX, h))
    gc:clip()
    gc:drawThemeRect("slider_full", rect)
    gc:restore()

    gc:save()
    gc:beginPath()
    gc:rect(Rectangle(splitX, 0, w - splitX, h))
    gc:clip()
    gc:drawThemeRect("slider_empty", rect)
    gc:restore()
  end

  local label = tostring(percent) .. "%"
  local measured = gc:measureText(label)
  local textY = math.max(0, (h - (measured.height or 8) - 1) // 2)

  if splitX > 0 then
    gc:save()
    gc:beginPath()
    gc:rect(Rectangle(0, 0, splitX, h))
    gc:clip()
    gc.color = colors.slider_full_text or colors.selected_text or colors.button_selected_text
    M.drawCenteredText(gc, rect, label, textY)
    gc:restore()
  end

  if splitX < w then
    gc:save()
    gc:beginPath()
    gc:rect(Rectangle(splitX, 0, w - splitX, h))
    gc:clip()
    gc.color = colors.slider_empty_text or colors.text or colors.button_normal_text
    M.drawCenteredText(gc, rect, label, textY)
    gc:restore()
  end
end

---Select the themed text color for an action button.
---@param colors table Theme colors.
---@param state string Button state.
---@param enabled boolean Whether the action is enabled.
---@return Color color Color for the current state.
function M.actionColor(colors, state, enabled)
  if not enabled then
    return colors.disabled
  end
  return colors[state .. "_text"]
end

---Select a legible placeholder color for labels drawn on sunken editor surfaces.
---In Aseprite's default dark theme, `disabled` matches `editor_face` (#202125),
---so a muted label color such as `tab_normal_text` or `button_normal_text` is used.
---@param colors table Theme colors.
---@return Color color Legible placeholder text color.
function M.placeholderColor(colors)
  local disabled = colors.disabled
  local surface = colors.editor_face
  if disabled and surface and disabled == surface then
    return colors.tab_normal_text
      or colors.timeline_normal_text
      or colors.text
      or colors.button_normal_text
      or colors.button_selected_text
  end
  return disabled or colors.button_selected_text
end

-- The primary selection has a complete inner outline. The secondary uses
-- four outer corner marks, including when both selections share a glyph.
---Paint primary and secondary selection markers around a glyph.
---@param gc GraphicsContext Canvas graphics context.
---@param x number Cell left edge.
---@param y number Cell top edge.
---@param cell integer Cell size in pixels.
---@param primary boolean Whether to paint the primary selection.
---@param secondary boolean Whether to paint the secondary selection.
function M.glyphSelection(gc, x, y, cell, primary, secondary)
  gc.color = gc.theme.color.selected
  if secondary then
    local length = math.max(2, math.min(4, cell // 3))
    local right, bottom = x + cell - 2, y + cell - 2
    for _, point in ipairs({
      { x - 1, y - 1 },
      { right, y - 1 },
      { x - 1, bottom },
      { right, bottom },
    }) do
      local dx = point[1] == right and -1 or 1
      local dy = point[2] == bottom and -1 or 1
      gc:fillRect(Rectangle(dx < 0 and point[1] - length + 1 or point[1], point[2], length, 1))
      gc:fillRect(Rectangle(point[1], dy < 0 and point[2] - length + 1 or point[2], 1, length))
    end
  end
  if primary then
    gc:strokeRect(Rectangle(x, y, cell - 2, cell - 2))
  end
end

return M
