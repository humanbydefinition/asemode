local U = require("src.core.util")
local Model = require("src.document.model")
local Profile = require("src.document.profile")
local Repertoire = require("src.fonts.repertoire")
local Transforms = require("src.document.transforms")
local M = {}
local pc = app.pixelColor

---Validate a document using an optional export-scoped cache.
---@param sprite Sprite Document to validate.
---@param onlyLayer Layer? Restrict validation to this layer.
---@param options table? Validation options.
---@param context table? Export-scoped validation cache.
---@return AsemodeValidationIssue[] issues Validation issues in display order.
local function run(sprite, onlyLayer, options, context)
  options = options or {}
  local issues = {}
  ---Record a validation issue with optional coordinate context.
  ---@param message string Problem description.
  ---@param layer? Layer Layer containing the issue.
  ---@param col? integer Cell grid column.
  ---@param row? integer Cell grid row.
  local function issue(message, layer, col, row)
    issues[#issues + 1] = { message = message, layer = layer and layer.name, col = col, row = row }
  end
  local ok, geometry = pcall(Model.geometry, sprite)
  if not ok then
    issue(tostring(geometry))
    return issues
  end
  local w, h = geometry.cellWidth, geometry.cellHeight
  local covered, coverageError = pcall(Model.coverage, sprite, geometry)
  if not covered then
    issue(tostring(coverageError))
  end
  if sprite.tileManagementPlugin then
    issue("Custom tile management forces pixel mode; remove its binding")
  end
  if context then
    U.check(context.sprite == sprite, "Export validation context belongs to another sprite")
  else
    Profile.invalidate()
  end
  local profiles = {}
  local selectedId = onlyLayer and Model.meta(onlyLayer).fontProfileId
  local requiredTiles, requiredGlyphs = {}, {}
  local scopedResources = options.frame and onlyLayer
  if scopedResources then
    local cel = onlyLayer:cel(options.frame)
    if cel and cel.image.colorMode == ColorMode.TILEMAP then
      for pixel in cel.image:pixels() do
        local ti = pc.tileI(pixel())
        requiredTiles[ti] = true
        local tile = onlyLayer.tileset:tile(ti)
        local key = tile and Model.meta(tile).glyphKey
        if key then
          requiredGlyphs[key] = true
        end
      end
    end
  end
  for _, entry in ipairs(Profile.profiles(sprite)) do
    if not onlyLayer or entry.id == selectedId then
      local index = context and context.profiles[entry.id]
      local good = index ~= nil
      if not good then
        good, index = pcall(Profile.index, sprite, entry.id)
        if good and context then
          context.profiles[entry.id] = index
        end
      end
      if good then
        profiles[entry.id] = index
      else
        issue(tostring(index))
      end
    end
  end
  local tileIssues = {}
  for id, index in pairs(profiles) do
    if index.profile.cellWidth ~= w or index.profile.cellHeight ~= h then
      issue("Font profile grid differs: " .. index.profile.name)
    end
    for _, role in ipairs({ "masks", "paint" }) do
      local ts = index[role]
      if ts.grid.tileSize.width ~= w or ts.grid.tileSize.height ~= h then
        issue("Tileset dimensions differ: " .. ts.name)
      end
      local empty = ts:tile(0)
      if empty and not empty.image:isEmpty() then
        issue("Tile zero must remain empty: " .. ts.name)
      end
      for i = 1, #ts - 1 do
        if i % 32 == 0 and options.checkpoint then
          options.checkpoint()
        end
        local tile, meta = ts:tile(i), Model.meta(ts:tile(i))
        if
          not scopedResources
          or (role == "paint" and requiredTiles[i])
          or (role == "masks" and requiredGlyphs[meta.glyphKey])
        then
          local cache
          if context then
            local byProfile = context.tiles[index]
            if not byProfile then
              byProfile = {}
              context.tiles[index] = byProfile
            end
            cache = byProfile[role]
            if not cache then
              cache = {}
              byProfile[role] = cache
            end
          end
          local problem = cache and cache[i]
          if problem == nil then
            if
              (meta.schemaVersion ~= 1 and not (role == "paint" and meta.schemaVersion == 2))
              or not meta.glyphKey
            then
              problem = "Missing glyph metadata"
            elseif
              meta.schemaVersion == 2
              and (not Transforms.validFlags(meta.orientation) or meta.orientation == 0)
            then
              problem = "Invalid tile orientation"
            elseif not pcall(Repertoire.scalar, meta.glyphKey) then
              problem = "Invalid glyph identity"
            elseif
              meta.renderFallback ~= nil and (role ~= "masks" or meta.renderFallback ~= "space")
            then
              problem = "Invalid glyph fallback marker"
            elseif meta.renderFallback == "space" and not tile.image:isEmpty() then
              problem = "Fallback mask must be blank"
            elseif tile.image.width ~= w or tile.image.height ~= h then
              problem = "Edited tile dimensions"
            elseif meta.imageHash ~= U.hash(tile.image.bytes) then
              problem = "Glyph pixels were edited"
            elseif role == "paint" then
              if meta.fontProfileId ~= id or not index.glyphs[meta.glyphKey] then
                problem = "Unknown glyph or font binding"
              elseif
                not pcall(U.rgba, meta.foregroundRGBA) or not pcall(U.rgba, meta.backgroundRGBA)
              then
                problem = "Invalid cell colors"
              end
            end
            if cache then
              cache[i] = problem or false
            end
          end
          if problem then
            issue(problem .. " in " .. ts.name .. " tile " .. i)
            if role == "paint" then
              tileIssues[id .. ":" .. i] = problem
            end
          end
        end
      end
    end
  end
  for _, layer in ipairs(Model.layers(sprite)) do
    if
      (not onlyLayer or layer == onlyLayer)
      and Model.meta(layer).schemaVersion == 1
      and not layer.isTilemap
    then
      issue("Managed text layer is no longer a tilemap", layer)
    elseif Model.layerManaged(layer) and (not onlyLayer or layer == onlyLayer) then
      local id = Model.meta(layer).fontProfileId
      local index = profiles[id]
      local binding = Model.meta(layer.tileset)
      if not index or binding.fontProfileId ~= id or binding.role ~= "paint" then
        issue("Missing or foreign font tileset", layer)
      else
        for _, cel in ipairs(layer.cels) do
          if not options.frame or cel.frameNumber == options.frame then
            if
              (cel.position.x - geometry.originX) % w ~= 0
              or (cel.position.y - geometry.originY) % h ~= 0
            then
              issue("Cel is not aligned in frame " .. cel.frameNumber, layer)
            end
            if cel.image.colorMode ~= ColorMode.TILEMAP then
              issue("Cel is no longer a tilemap", layer)
            else
              local baseCol, baseRow = Model.celOrigin(cel, geometry)
              for pixel in cel.image:pixels() do
                if pixel.x == 0 and options.checkpoint then
                  options.checkpoint()
                end
                local value = pixel()
                local ti, flags = pc.tileI(value), pc.tileF(value)
                local col, row = baseCol + pixel.x, baseRow + pixel.y
                if ti > 0 then
                  if not index.paint:tile(ti) or not Model.meta(index.paint:tile(ti)).glyphKey then
                    issue("Foreign tile in frame " .. cel.frameNumber, layer, col, row)
                  elseif tileIssues[id .. ":" .. ti] then
                    issue(
                      tileIssues[id .. ":" .. ti] .. " in frame " .. cel.frameNumber,
                      layer,
                      col,
                      row
                    )
                  end
                  if (flags & pc.TILE_DFLIP) ~= 0 and geometry.cellWidth ~= geometry.cellHeight then
                    issue("Native diagonal transforms require square cells", layer, col, row)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return issues
end

---Validate an Asemode document or one of its layers.
---@param sprite Sprite Document to validate.
---@param onlyLayer Layer? Restrict validation to this layer.
---@param options table? Validation options.
---@return AsemodeValidationIssue[] issues Validation issues in display order.
function M.run(sprite, onlyLayer, options)
  return run(sprite, onlyLayer, options)
end

-- This closure owns its cache for one export operation.
---Create an export-scoped validation context with a fresh profile cache.
---@param sprite Sprite Document to validate.
---@return table context Context providing a layer validation method.
function M.exportContext(sprite)
  Profile.invalidate()
  local state = { sprite = sprite, profiles = {}, tiles = {} }
  return {
    run = function(_, layer, options)
      return run(sprite, layer, options, state)
    end,
  }
end

---Format validation issues as a short user-facing summary.
---@param issues AsemodeValidationIssue[] Validation issues.
---@return string text Summary with at most five issues.
function M.text(issues)
  if #issues == 0 then
    return "Textmode document is valid."
  end
  local lines = { #issues .. " issue(s) found in Asemode data." }
  for i = 1, math.min(5, #issues) do
    local e = issues[i]
    lines[#lines + 1] = (e.layer and e.layer .. ": " or "")
      .. e.message
      .. (e.col and (" at cell " .. e.col .. "," .. e.row) or "")
  end
  if #issues > 5 then
    lines[#lines + 1] = (#issues - 5) .. " additional issue(s) not shown."
  end
  lines[#lines + 1] = "Try undoing recent edits or restoring an earlier .aseprite file."
  return table.concat(lines, "\n")
end

---Raise an error when a document or layer fails validation.
---@param sprite Sprite Document to validate.
---@param layer Layer? Restrict validation to one layer.
function M.requireValid(sprite, layer)
  local issues = M.run(sprite, layer)
  U.check(#issues == 0, M.text(issues))
end

return M
