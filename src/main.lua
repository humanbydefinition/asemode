local controller

---Initialize the Asemode extension plugin and register menu commands.
---@param plugin Plugin Aseprite plugin instance.
function init(plugin)
  if app.apiVersion < 41 or app.version < Version("1.3.18.6") then
    if app.isUIAvailable then
      app.alert("Asemode requires Aseprite 1.3.18.6 (API 41) or later.")
    end
    return
  end
  local Controller = require("src.ui.controller")
  local Model = require("src.document.model")
  local Stamps = require("src.actions.stamps")
  controller = Controller.new(plugin)
  plugin:newMenuGroup({ id = "asemode_menu", title = "Asemode", group = "sprite_properties" })
  local stampCommands = {}
  for _, action in ipairs(Stamps.definitions) do
    stampCommands[#stampCommands + 1] = {
      action.command,
      action.title,
      function()
        controller.drawing:runAction(action.id)
      end,
      function()
        return controller.drawing:canRunAction(action.id)
      end,
    }
  end
  local commands = {
    {
      "AsemodeNew",
      "New Textmode Sprite..",
      function()
        controller.document:newDocument()
      end,
    },
    {
      "AsemodeImport",
      "Import Textmode JSON..",
      function()
        controller.portable:importDocument()
      end,
    },
    {
      "AsemodePanel",
      "Open/Close Asemode Panel",
      function()
        controller:togglePanel()
      end,
    },
    {
      "AsemodeLayer",
      "Add Textmode Layer..",
      function()
        controller.font:addLayer()
      end,
      function()
        return Model.eligible(app.sprite)
      end,
    },
    { groupId = "asemode_stamps", title = "Stamps", entries = stampCommands },
    {
      groupId = "asemode_selection",
      title = "Selection",
      entries = {
        {
          "AsemodeReplace",
          "Replace..",
          function()
            controller.document:replaceSelection()
          end,
          function()
            return Model.textLayer(app.sprite, app.layer)
          end,
        },
        {
          "AsemodeCopyCells",
          "Copy",
          function()
            controller.document:copyCells()
          end,
          function()
            return controller.document:canCopyCells()
          end,
        },
        {
          "AsemodePasteCells",
          "Paste",
          function()
            controller.document:pasteCells()
          end,
          function()
            return Model.textLayer(app.sprite, app.layer) and controller.document:canPasteCells()
          end,
        },
      },
    },
    {
      "AsemodeFont",
      "Fonts..",
      function()
        controller.font:importFont()
      end,
    },
    {
      "AsemodeRegrid",
      "Grid..",
      function()
        controller.document:regrid()
      end,
      function()
        return Model.supported(app.sprite)
      end,
    },
    {
      "AsemodeExport",
      "Export..",
      function()
        controller.document:export()
      end,
      function()
        return Model.textLayer(app.sprite, app.layer)
      end,
    },
    {
      "AsemodeSettings",
      "Settings..",
      function()
        controller:settings()
      end,
    },
    {
      "AsemodeKeyboardShortcuts",
      "Keyboard Shortcuts...",
      function()
        controller:keyboardShortcuts()
      end,
      function()
        return app.isUIAvailable
      end,
    },
    {
      "AsemodeCredits",
      "About..",
      function()
        controller:about()
      end,
    },
  }
  ---Recursively register command entries and menu groups on the plugin.
  ---@param entries table[] List of command or menu group definitions.
  ---@param group string Parent menu group identifier.
  local function register(entries, group)
    for _, entry in ipairs(entries) do
      if entry.groupId then
        plugin:newMenuGroup({ id = entry.groupId, title = entry.title, group = group })
        register(entry.entries, entry.groupId)
      else
        plugin:newCommand({
          id = entry[1],
          title = entry[2],
          group = group,
          onclick = controller:guard(entry[3]),
          onenabled = entry[4],
        })
      end
    end
  end
  register(commands, "asemode_menu")
  controller:start()
  local pluginName = plugin.name or "asemode"
  for k, v in pairs(package.loaded) do
    local sub = k:match("^" .. pluginName .. "/(.+)$")
    if sub and not package.loaded[sub] then
      package.loaded[sub] = v
    end
  end
end

---Tear down extension resources and release active controllers.
---@param plugin Plugin Aseprite plugin instance.
function exit(plugin)
  if controller then
    controller:close()
    controller = nil
  end
end
