local U = require("src.core.util")
local Binary = require("src.core.binary")
local Names = require("src.fonts.names")
local Bundled = require("src.fonts.bundled")
local Loader = require("src.fonts.loader")
local Identity = require("src.fonts.identity")
local Resources = require("src.fonts.resources")
local TTF = require("src.fonts.truetype")
local M = { MAX_FONT = 16 * 1024 * 1024, MAX_BYTES = 32 * 1024 * 1024, MAX_COUNT = 64 }

---Look up the author of an exact bundled font by its SHA-256 digest.
---@param digest string SHA-256 digest.
---@return string? author Author name if matched in curated fonts.
local function registeredAuthor(digest)
  for _, font in ipairs(Bundled) do
    local resource = Resources[font.id]
    if digest == (font.sourceSha256 or (resource and resource.sha256)) then
      return font.author
    end
  end
end

---Create a user font library backed by plugin preferences.
---@param preferences table Plugin preferences containing saved font data.
---@return table library Font catalog and resource management methods.
function M.new(preferences)
  local self = { preferences = preferences, records = {}, cache = {}, revision = 0 }

  ---Validate saved user font library payload schema and resource bounds.
  ---@param payload table Decoded user font library table.
  local function validate(payload)
    U.check(
      type(payload) == "table" and payload.schemaVersion == 1 and type(payload.fonts) == "table",
      "Unsupported user font library schema"
    )
    local count, total = 0, 0
    for id, r in pairs(payload.fonts) do
      U.check(
        type(r) == "table"
          and U.isSha256(r.sha256)
          and id == "user-" .. r.sha256
          and r.schemaVersion == 1,
        "Invalid user font identity"
      )
      U.check(
        Names.clean(r.displayName) == r.displayName
          and type(r.filename) == "string"
          and #r.filename <= 4096
          and (r.extractedName == nil or Names.clean(r.extractedName) == r.extractedName),
        "Invalid user font metadata"
      )
      U.integer(r.byteLength, "Font length", 1, M.MAX_FONT)
      U.check(
        type(r.base64) == "string"
          and #r.base64 == 4 * ((r.byteLength + 2) // 3)
          and not r.base64:find("[^A-Za-z0-9+/=]"),
        "Invalid encoded user font"
      )
      count, total = count + 1, total + r.byteLength
    end
    U.check(
      count <= M.MAX_COUNT and total <= M.MAX_BYTES,
      "User font library exceeds storage limits"
    )
  end
  local raw = preferences.userFontLibraryJson
  if raw ~= nil then
    local ok, err = pcall(function()
      U.check(
        type(raw) == "string" and #raw <= 48 * 1024 * 1024,
        "Invalid user font library payload"
      )
      local payload = U.decode(raw)
      validate(payload)
      self.records = payload.fonts
    end)
    if not ok then
      self.error = "Saved font library could not be read: " .. tostring(err)
    end
  end

  ---Prepare a rendering job for a catalog entry.
  ---@param entry table Bundled or user font catalog entry.
  ---@param options table? Font measurement options.
  ---@return AsemodeFontJob job Prepared font rendering job.
  function self:job(entry, options)
    if entry.kind == "user" then
      return Loader.user(entry.id, options, function(id, digest)
        return self:resource(id, digest)
      end, entry.name, entry.sha256)
    end
    U.check(
      entry.available ~= false,
      "This font is not bundled. Visit its source and upload the TTF in the Font dialog."
    )
    return Loader.bundled(entry.id, options)
  end

  ---Count saved fonts and their decoded byte sizes.
  ---@return integer count Number of user fonts.
  ---@return integer bytes Total saved font bytes.
  function self:usage()
    local count, total = 0, 0
    for _, r in pairs(self.records) do
      count, total = count + 1, total + r.byteLength
    end
    return count, total
  end

  ---Load and verify a saved font resource, using the in-memory cache.
  ---@param id string User font identifier.
  ---@param digest? string Expected SHA-256 digest.
  ---@param checkpoint? fun(message: string) Cooperative progress callback.
  ---@return table resource Verified font bytes and hashes.
  function self:resource(id, digest, checkpoint)
    U.check(not self.error, self.error)
    local r = self.records[id]
    U.check(r, "Saved font is missing. Import the same font into the Library or replace it.")
    U.check(
      not digest or r.sha256 == digest,
      "Saved font revision differs. Restore the same font or replace it."
    )
    if not self.cache[id] then
      local bytes = Binary.decode(r.base64, M.MAX_FONT, checkpoint)
      U.check(
        #bytes == r.byteLength and Binary.sha256(bytes, checkpoint) == r.sha256,
        "Saved font resource is corrupt. Remove it and import the same font again."
      )
      self.cache[id] =
        { bytes = bytes, sha256 = r.sha256, byteLength = #bytes, sourceHash = U.hash(bytes) }
    end
    return self.cache[id]
  end

  ---Resolve an inspected font author and cache its source digest.
  ---@param candidate table Inspected font candidate.
  ---@return string author Registered or extracted author, or Unknown.
  function self:authorForCandidate(candidate)
    candidate.sha256 = candidate.sha256 or Binary.sha256(candidate.bytes)
    return registeredAuthor(candidate.sha256) or candidate.extractedAuthor or "Unknown"
  end

  ---Resolve the author of a catalog entry.
  ---@param entry table? Font catalog entry.
  ---@return string author Author name, or Unknown.
  function self:author(entry)
    if not entry then
      return "Unknown"
    end
    if entry.kind ~= "user" then
      return entry.author or "Unknown"
    end
    local ok, result = pcall(function()
      local resource = self:resource(entry.id, entry.sha256)
      if not resource.authorResolved then
        local curated = registeredAuthor(resource.sha256)
        if curated then
          resource.author = curated
        else
          local parser = package.loaded["src.fonts.truetype"] or TTF
          resource.author = parser.parse(resource.bytes).designer
        end
        resource.authorResolved = true
      end
      return resource.author
    end)
    return ok and result or "Unknown"
  end

  ---Prepare a user font library update without persisting it.
  ---@param candidate table Inspected font candidate; its digest may be cached.
  ---@param name string Requested display name.
  ---@return table stage Staged record, payload, and library revision.
  function self:stage(candidate, name)
    U.check(not self.error, self.error)
    name = U.check(
      Names.clean(name),
      "Enter a display name of 1–128 characters without control characters"
    )
    U.check(
      type(candidate.bytes) == "string" and #candidate.bytes > 0 and #candidate.bytes <= M.MAX_FONT,
      "Font exceeds 16 MiB"
    )
    local digest = candidate.sha256 or Binary.sha256(candidate.bytes)
    candidate.sha256 = digest
    local id = "user-" .. digest
    local existing = self.records[id]
    if existing then
      return {
        id = id,
        sha256 = digest,
        name = existing.displayName,
        duplicate = true,
        revision = self.revision,
      }
    end
    local count, total = self:usage()
    U.check(
      count < M.MAX_COUNT and total + #candidate.bytes <= M.MAX_BYTES,
      "User Library is full (64 fonts / 32 MiB). Remove a font or clear Save to Library."
    )
    local record = {
      schemaVersion = 1,
      sha256 = digest,
      byteLength = #candidate.bytes,
      base64 = Binary.encode(candidate.bytes),
      displayName = name,
      extractedName = candidate.extractedName,
      filename = U.basename(candidate.path or ""):sub(1, 4096),
    }
    local records = {}
    for key, value in pairs(self.records) do
      records[key] = value
    end
    records[id] = record
    return {
      id = id,
      sha256 = digest,
      name = name,
      record = record,
      records = records,
      payload = json.encode({ schemaVersion = 1, fonts = records }),
      revision = self.revision,
    }
  end

  ---Reject a staged font update if the library changed.
  ---@param stage table Staged font library update.
  function self:checkStage(stage)
    U.check(
      not self.error and stage.revision == self.revision,
      "Library changed while the font preview was open. Import again."
    )
  end

  ---Persist a previously validated staged font update.
  ---@param stage table Staged font library update.
  function self:commit(stage)
    -- Called only after a successful document operation; stage was revalidated before it.
    if stage.duplicate then
      return
    end
    self.preferences.userFontLibraryJson = stage.payload
    self.records = stage.records
    self.revision = self.revision + 1
  end

  ---Serialize and persist user font library records into plugin preferences.
  ---@param records table Map from font ID to font record.
  local function save(records)
    local payload = json.encode({ schemaVersion = 1, fonts = records })
    self.preferences.userFontLibraryJson = payload
    self.records = records
    self.revision = self.revision + 1
  end

  ---Rename a saved user font.
  ---@param id string User font identifier.
  ---@param name string New display name.
  function self:rename(id, name)
    U.check(not self.error, self.error)
    U.check(self.records[id], "Select a user font")
    name = U.check(
      Names.clean(name),
      "Enter a display name of 1–128 characters without control characters"
    )
    local records = U.copy(self.records)
    records[id].displayName = name
    save(records)
  end

  ---Remove a saved user font and its cached resource.
  ---@param id string User font identifier.
  function self:remove(id)
    U.check(not self.error, self.error)
    U.check(self.records[id], "Select a user font")
    local records = {}
    for key, r in pairs(self.records) do
      if key ~= id then
        records[key] = r
      end
    end
    save(records)
    self.cache[id] = nil
  end

  ---Clear the saved font library and any cached error or resources.
  function self:reset()
    save({})
    self.cache = {}
    self.error = nil
  end

  ---Resolve a catalog entry to a portable font identity.
  ---@param entry table Font catalog entry.
  ---@param checkpoint? fun(message: string) Cooperative progress callback.
  ---@return table? reference Portable font identity if available.
  function self:portableReference(entry, checkpoint)
    if entry.kind == "bundled" then
      local resource = Resources[entry.id]
      return resource and resource.portableFont or nil
    end
    local resource = self:resource(entry.id, entry.sha256, checkpoint)
    if not resource.portableFont then
      resource.portableFont = Identity.identify(resource.bytes, checkpoint)
    end
    return resource.portableFont
  end

  ---Find a saved font matching a bundled font source digest.
  ---@param font table Bundled font registry entry.
  ---@return string? id Matching user font identifier.
  ---@return table? record Matching saved font record.
  function self:matchingUser(font)
    local id = font.sourceSha256 and "user-" .. font.sourceSha256
    local record = id and self.records[id]
    if record and record.sha256 == font.sourceSha256 then
      return id, record
    end
  end

  ---List bundled and user fonts with unique display labels.
  ---@return table[] entries Font catalog entries.
  function self:catalog()
    local entries, users, matched = {}, {}, {}
    for _, r in ipairs(Bundled) do
      local e = U.copy(r)
      local userId, saved = self:matchingUser(r)
      if saved then
        e.kind, e.id, e.name = "user", userId, saved.displayName
        e.sha256, e.available = saved.sha256, true
        matched[userId] = true
      else
        e.kind = "bundled"
        e.label = e.name .. (e.available == false and " (Not installed)" or "")
      end
      entries[#entries + 1] = e
    end
    for id, r in pairs(self.records) do
      if not matched[id] then
        users[#users + 1] = { kind = "user", id = id, name = r.displayName, sha256 = r.sha256 }
      end
    end
    table.sort(users, function(a, b)
      local x, y = a.name:lower(), b.name:lower()
      return x == y and a.id < b.id or x < y
    end)
    for _, e in ipairs(users) do
      entries[#entries + 1] = e
    end
    local used = {}
    local frequencies = {}
    for _, e in ipairs(entries) do
      if e.kind == "user" then
        frequencies[e.name] = (frequencies[e.name] or 0) + 1
      else
        used[e.label] = true
      end
    end
    for _, e in ipairs(entries) do
      if e.kind == "user" then
        local suffix = frequencies[e.name] > 1 and (" " .. e.sha256:sub(1, 8)) or ""
        e.label = e.name .. suffix .. " (User)"
        local n = 8
        while used[e.label] and n < 64 do
          n = n + 1
          e.label = e.name .. " " .. e.sha256:sub(1, n) .. " (User)"
        end
        local extra = 0
        local base = e.label
        while used[e.label] do
          extra = extra + 1
          e.label = base .. " (" .. extra .. ")"
        end
        used[e.label] = true
      end
    end
    return entries
  end
  return self
end
return M
