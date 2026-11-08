local M = {}

-- Manage the two visible layer slots while retaining choices for every page.
function M.create(args)
  local d, layers, sourceLabels = args.dialog, args.layers, args.sourceLabels
  local invalidFonts, layerState = args.invalidFonts, args.layerState
  local controls, overrides, recoveryOverrides =
    args.controls, args.overrides, args.recoveryOverrides
  local layerDetails = args.layerDetails
  local pageSize, page, pages = args.pageSize, 1, args.pages
  local updatePage
  local function changePage(nextPage)
    if args.isSyncing() or not args.isReady() then
      return
    end
    nextPage = tonumber(nextPage)
    if not nextPage or nextPage ~= nextPage or nextPage == math.huge or nextPage == -math.huge then
      return
    end
    page = math.max(1, math.min(pages, math.floor(nextPage)))
    updatePage()
    args.onChange()
  end
  if pages > 1 then
    d:separator({ text = "Layers and frames" })
    controls[#controls + 1] = "page"
    controls[#controls + 1] = "previousPage"
    controls[#controls + 1] = "nextPage"
    d:number({
      id = "page",
      label = "Page",
      text = "1",
      decimals = 0,
      onchange = function()
        changePage(d.data.page)
      end,
    })
      :samerow()
      :label({ text = "of " .. pages })
      :samerow()
      :button({
        id = "previousPage",
        text = "Previous",
        onclick = function()
          changePage(page == 1 and pages or page - 1)
        end,
      })
      :samerow()
      :button({
        id = "nextPage",
        text = "Next",
        onclick = function()
          changePage(page == pages and 1 or page + 1)
        end,
      })
      :newrow()
    d:label({
      id = "fontChoicesNotice",
      text = "Choose a font for each selected layer.",
      visible = false,
    }):newrow()
  end
  local slotCount = math.min(pageSize, #layers)
  local hasFontDetail = {}
  for slot = 1, slotCount do
    local index = slot
    local name, font = layerDetails(index)
    controls[#controls + 1] = "source" .. slot
    controls[#controls + 1] = "font" .. slot
    d:separator({ id = "layerHeading" .. slot, text = sourceLabels[index] })
    d:label({ id = "layerName" .. slot, text = name }):newrow()
    if pages > 1 or font then
      hasFontDetail[slot] = true
      d:label({ id = "layerFont" .. slot, text = font or "", visible = font ~= nil }):newrow()
    end
    d:check({
      id = "source" .. slot,
      text = "Import " .. sourceLabels[index],
      selected = layerState[index].selected,
      onclick = function()
        if args.isSyncing() then
          return
        end
        local current = (page - 1) * pageSize + slot
        layerState[current].selected = d.data["source" .. slot]
        args.onChange()
      end,
    }):combobox({
      id = "font" .. slot,
      label = "Font override",
      options = invalidFonts[index] and recoveryOverrides or overrides,
      option = layerState[index].font,
      onchange = function()
        if args.isSyncing() then
          return
        end
        local current = (page - 1) * pageSize + slot
        layerState[current].font = d.data["font" .. slot]
        args.onChange()
      end,
    })
  end
  updatePage = function()
    args.setSyncing(true)
    if pages > 1 then
      d:modify({ id = "page", text = tostring(page) })
    end
    for slot = 1, slotCount do
      local index = (page - 1) * pageSize + slot
      local exists = layers[index] ~= nil
      local name, font
      if exists then
        name, font = layerDetails(index)
      end
      d:modify({
        id = "layerHeading" .. slot,
        visible = exists,
        text = exists and sourceLabels[index] or "",
      })
      d:modify({ id = "layerName" .. slot, visible = exists, text = name or "" })
      if hasFontDetail[slot] then
        d:modify({ id = "layerFont" .. slot, visible = exists and font ~= nil, text = font or "" })
      end
      d:modify({
        id = "source" .. slot,
        visible = exists,
        text = exists and ("Import " .. sourceLabels[index]) or "",
        selected = exists and layerState[index].selected or false,
      })
      d:modify({
        id = "font" .. slot,
        visible = exists,
        options = exists and (invalidFonts[index] and recoveryOverrides or overrides) or overrides,
        option = exists and layerState[index].font or "Use default font",
      })
    end
    args.setSyncing(false)
  end
  return updatePage
end

return M
