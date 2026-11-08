return function(test)
  local Library = require("src.fonts.library")
  local Binary = require("src.core.binary")
  local Resources = require("src.fonts.resources")
  local previousTTF = require("src.fonts.truetype")
  local calls = 0
  -- Mock TrueType parser for testing embedded designer metadata
  package.loaded["src.fonts.truetype"] = {
    parse = function(bytes)
      calls = calls + 1
      if bytes == "with designer" then
        return { designer = "An Artist" }
      end
      return {}
    end,
  }
  local preferences = {}
  local library = Library.new(preferences)

  local function add(bytes, name)
    local digest = Binary.sha256(bytes)
    local id = "user-" .. digest
    library.records[id] = {
      sha256 = digest,
      byteLength = #bytes,
      base64 = Binary.encode(bytes),
      displayName = name,
    }
    return { id = id, kind = "user", sha256 = digest, name = name }
  end

  test("TrueType parser exposes embedded designer metadata", function()
    local bytes = Resources.atascii.bytes
    local count = string.unpack(">I2", bytes, 5)
    local offset, length
    for i = 0, count - 1 do
      local tag, _, start, size = string.unpack(">c4I4I4I4", bytes, 13 + i * 16)
      if tag == "name" then
        offset, length = start, size
        break
      end
    end
    local text = "\0A\0r\0t\0i\0s\0t"
    local tableBytes = string.pack(">I2I2I2", 0, 1, 18)
      .. string.pack(">I2I2I2I2I2I2", 3, 1, 0x409, 9, #text, 0)
      .. text
    assert(offset and #tableBytes <= length)
    local changed = bytes:sub(1, offset) .. tableBytes .. bytes:sub(offset + #tableBytes + 1)
    assert(previousTTF.parse(changed).designer == "Artist")
  end)

  test("custom font designer metadata is resolved lazily and cached", function()
    local entry = add("with designer", "ATASCII")
    assert(library:author(entry) == "An Artist")
    assert(library:author(entry) == "An Artist" and calls == 1)
    assert(preferences.userFontLibraryJson == nil)
    entry.name = "Renamed"
    assert(library:author(entry) == "An Artist" and calls == 1)
    local unknown = add("without designer", "Other")
    assert(library:author(unknown) == "Unknown")
    assert(library:author(unknown) == "Unknown" and calls == 2)
    assert(
      library:authorForCandidate({ bytes = "new font", extractedAuthor = "Creator" }) == "Creator"
    )
    assert(library:authorForCandidate({ bytes = "unknown font" }) == "Unknown")
  end)

  test("saved custom fonts retain author after restart and duplicate import", function()
    local previousJson = json
    local JSON = require("src.portable.json")
    json = { encode = JSON.stringify, decode = JSON.parse }
    local saved = {}
    local first = Library.new(saved)
    local candidate =
      { bytes = "with designer", path = "Artist.ttf", extractedAuthor = "An Artist" }
    local stage = first:stage(candidate, "My font")
    first:commit(stage)
    local payload = saved.userFontLibraryJson
    local reopened = Library.new(saved)
    assert(not reopened.error)
    local entry = { kind = "user", id = stage.id, sha256 = stage.sha256 }
    assert(reopened:author(entry) == "An Artist")
    assert(saved.userFontLibraryJson == payload)
    local duplicate = reopened:stage(candidate, "Different name")
    assert(duplicate.duplicate and duplicate.name == "My font")
    reopened:commit(duplicate)
    assert(saved.userFontLibraryJson == payload)
    json = previousJson
  end)

  test("registered author wins for verified exact font bytes", function()
    local resource = Resources.atascii
    local candidate = { bytes = resource.bytes, extractedAuthor = "Incorrect" }
    assert(library:authorForCandidate(candidate) == "Damian Vila")
    assert(candidate.sha256 == resource.sha256)
    local entry = add(resource.bytes, "Renamed copy")
    assert(library:author(entry) == "Damian Vila")
    assert(library:author({ kind = "bundled", author = "Curated" }) == "Curated")
    library.cache[entry.id] = nil
    library.records[entry.id].base64 = Binary.encode("corrupt")
    assert(library:author(entry) == "Unknown")
    assert(not pcall(function()
      library:resource(entry.id, entry.sha256)
    end))
  end)

  -- Teardown: restore previous parser
  package.loaded["src.fonts.truetype"] = previousTTF
end
