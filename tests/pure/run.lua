local JSON = require("src.portable.json")
local Codec = require("src.portable.codec")
local Binary = require("src.core.binary")
local Identity = require("src.fonts.identity")
local Names = require("src.fonts.names")
local Repertoire = require("src.fonts.repertoire")
local Task = require("src.core.task")
local count = 0
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    error("FAIL " .. name .. ": " .. tostring(err), 0)
  end
  count = count + 1
  print("PASS " .. name)
end

local function fails(fn)
  assert(not pcall(fn))
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local value = f:read("*a")
  f:close()
  return value
end

test("existing document metadata remains readable and writable", function()
  local Base = require("src.document.base")
  local stored = { schemaVersion = 1, cellWidth = 8 }
  local object = {
    properties = function(namespace, value)
      assert(namespace == "asemode")
      if value then
        stored = value
      end
      return stored
    end,
  }
  assert(Base.meta(object).cellWidth == 8)
  Base.setMeta(object, { schemaVersion = 1, cellWidth = 16 })
  assert(Base.meta(object).cellWidth == 16)
end)

test("shared utilities validate and serialize values", function()
  local U = require("src.core.util")
  assert(U.isHexColor("#12aBcD00") and not U.isHexColor("#123456"))
  assert(U.isSha256(string.rep("a", 64)) and not U.isSha256(string.rep("A", 64)))
  assert(U.key("A", "fg", "bg") == "A\0fgbg")
  assert(U.key("A", "fg", "bg", 0) == "A\0fgbg:0")
  assert(U.frameNumber(3) == 3 and U.frameNumber({ frameNumber = 4 }) == 4)
  assert(U.cleanError("file.lua:12: failed") == "failed")
  local encoded = U.prettyJson({ text = 'a\n"b', values = { 1, 2 } })
  local decoded = JSON.parse(encoded)
  assert(decoded.text == 'a\n"b' and decoded.values[2] == 2 and encoded:sub(-1) == "\n")
end)

test("filesystem mock resolves both path separator styles", function()
  local fs = require("tests.pure.filesystem")
  assert(fs.filePath("./src/unicode/names.lua") == "./src/unicode")
  assert(fs.filePath([[.\src\unicode\names.lua]]) == "./src/unicode")
  assert(fs.filePath("names.lua") == ".")
end)

test("typed JSON retains distinct values", function()
  local v = JSON.parse('{"a":[],"b":{},"n":null,"s":"a\\u0000😀","dup":1,"dup":2}')
  assert(
    JSON.isArray(v.a)
      and JSON.isObject(v.b)
      and v.n == JSON.null
      and v.s == "a\0😀"
      and v.dup == 2
  )
  local again = JSON.parse(JSON.stringify(v))
  assert(again.s == v.s and again.n == JSON.null)
end)

test("JSON rejects malformed input and limits", function()
  for _, value in ipairs({ "[1,]", "01", '"\\q"', "true false" }) do
    fails(function()
      JSON.parse(value)
    end)
  end
  fails(function()
    JSON.parse("[[[]]]", { maxDepth = 1 })
  end)
  fails(function()
    JSON.stringify({ a = "long" }, { maxBytes = 2 })
  end)
  local calls = 0
  JSON.parse('"' .. string.rep("a", 1024) .. '"', {
    checkpoint = function()
      calls = calls + 1
    end,
  })
  assert(calls > 0)
end)

test("duration totals retain fractional tails at the safe integer boundary", function()
  local prefix = '{"format":"textmode.document","formatVersion":"4.0.0","frames":['
  local frames = '{"durationMs":9007199254740990,"layers":[]},'
    .. '{"durationMs":0.5,"layers":[]},{"durationMs":0.5,"layers":[]}'
  assert(Codec.decode(prefix .. frames .. "]}").ok)
  local overflow = Codec.decode(prefix .. frames .. ',{"durationMs":5e-324,"layers":[]}]}')
  assert(not overflow.ok and overflow.error.code == "LIMIT_EXCEEDED")
end)

test("codec rejects older fixture", function()
  local result = Codec.decode(read("tests/fixtures/portable/v3-single-layer.json"))
  assert(not result.ok and result.error.code == "UNSUPPORTED_VERSION")
  local invalid = Codec.decode("[]")
  assert(not invalid.ok and invalid.error.code and invalid.error.path == "$")
  local limited =
    Codec.decode(read("tests/fixtures/portable/v3-single-layer.json"), { maxBytes = 1 })
  assert(not limited.ok and limited.error.code == "LIMIT_EXCEEDED")
end)

test("font ID recovery is opt-in, bounded, and keeps other validation strict", function()
  local content = read("tests/test-documents/invalid-font-id.textmode.json")
  local strict = Codec.decode(content)
  assert(not strict.ok and strict.error.code == "INVALID_DOCUMENT")
  local recovered = {}
  local result = Codec.decodeWithFontRecovery(content, nil, function(id, sourceIndex, name)
    recovered[sourceIndex] = { id = id, name = name }
  end)
  assert(result.ok and recovered[1] and not result.document.frames[1].layers[1].font)
  local doc = JSON.parse(read("tests/fixtures/portable/v4-single-layer.json"))
  doc.frames[1].layers[1].font = JSON.object({ id = string.rep("x", 4097) })
  local tooLong = Codec.decodeWithFontRecovery(JSON.stringify(doc), nil, function()
    error("must not recover")
  end)
  assert(not tooLong.ok and tooLong.error.code == "LIMIT_EXCEEDED")
  doc.frames[1].layers[1].font.id = "invalid"
  doc.frames[1].layers[1].cells.rows[1][1].foreground.r = 256
  local malformed = Codec.decodeWithFontRecovery(JSON.stringify(doc), nil, function() end)
  assert(not malformed.ok and malformed.error.path:find("foreground", 1, true))
  local limited = Codec.decodeWithFontRecovery(content, { maxBytes = 1 }, function() end)
  assert(not limited.ok and limited.error.code == "LIMIT_EXCEEDED")
  fails(function()
    Codec.decodeWithFontRecovery(content, {
      checkpoint = function()
        error("canceled")
      end,
    }, function() end)
  end)
end)

test("base64 and SHA-256", function()
  local bytes = "a\0\255z"
  assert(Binary.decode(Binary.encode(bytes), 32) == bytes)
  assert(Binary.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  fails(function()
    Binary.decode("!===", 32)
  end)
end)

test("font identity matches committed fixture", function()
  local golden = JSON.parse(read("tests/fixtures/font-identities.json"))
  assert(Identity.identify(read("assets/fonts/atascii.ttf")).id == golden["atascii.ttf"])
  fails(function()
    Identity.identify("invalid")
  end)
end)

test("optional font catalog and saved defaults handle missing resources", function()
  local Library = require("src.fonts.library")
  local Settings = require("src.core.settings")
  local library = Library.new({})
  local optional
  for _, entry in ipairs(library:catalog()) do
    if entry.id == "chunky" then
      optional = entry
    end
  end
  assert(optional and optional.available == false and optional.sourceUrl)
  assert(optional.label:find("Not installed", 1, true))
  fails(function()
    library:job(optional, { pixelSize = 8 })
  end)
  local values, missing = Settings.read(
    { newSpriteDefaults = {
      fontKind = "bundled",
      fontId = "chunky",
    } },
    library
  )
  assert(missing and values.fontId == "atascii")
  assert(not Settings.update({}, library, "font", optional))
end)

test("saved optional font replaces its unavailable catalog entry", function()
  local library = require("src.fonts.library").new({})
  local digest = "53ffb5853301ff85d8fdfef0095f65c28f3b7dd1bd29abadb2bf06871764c68e"
  library.records["user-" .. digest] = { displayName = "CHUNKY", sha256 = digest }
  local matches = {}
  for _, entry in ipairs(library:catalog()) do
    if entry.name == "CHUNKY" then
      matches[#matches + 1] = entry
    end
  end
  assert(#matches == 1, "Expected one CHUNKY entry, found " .. #matches)
  assert(matches[1].kind == "user" and matches[1].label == "CHUNKY (User)")
  assert(matches[1].id == "user-" .. digest and matches[1].sourceUrl)
  local Loader = require("src.fonts.loader")
  local originalUser = Loader.user
  rawset(Loader, "user", function(id, _, _, _, sha256)
    assert(id == "user-" .. digest and sha256 == digest)
    return "saved font"
  end)
  local ok, job = pcall(function()
    return library:job(matches[1], {})
  end)
  rawset(Loader, "user", originalUser)
  assert(ok and job == "saved font")
  local registered
  for _, font in ipairs(require("src.fonts.bundled")) do
    if font.id == "chunky" then
      registered = font
    end
  end
  local wasAvailable = registered.available
  registered.available = true
  local entries = library:catalog()
  registered.available = wasAvailable
  local count = 0
  for _, entry in ipairs(entries) do
    if entry.name == "CHUNKY" then
      count = count + 1
      assert(entry.label == "CHUNKY (User)")
    end
  end
  assert(count == 1)
  library.records["user-" .. digest].displayName = "My font"
  for _, entry in ipairs(library:catalog()) do
    assert(entry.label ~= "CHUNKY (Not installed)")
  end
  library.records["user-" .. digest] = nil
  local different = string.rep("a", 64)
  library.records["user-" .. different] = { displayName = "CHUNKY", sha256 = different }
  local labels = {}
  for _, entry in ipairs(library:catalog()) do
    labels[entry.label] = true
  end
  assert(labels["CHUNKY (Not installed)"] and labels["CHUNKY (User)"])
end)

test("missing bundled font can use its saved original", function()
  local Loader = require("src.fonts.loader")
  local originalUser = Loader.user
  local digest = string.rep("a", 64)
  local id = "user-" .. digest
  rawset(Loader, "user", function(foundId, _, _, _, foundDigest)
    assert(foundId == id and foundDigest == digest)
    return "restored"
  end)
  local ok, result = pcall(Loader.fromProfile, {
    source = { kind = "bundled", id = "chunky", sha256 = digest },
    name = "CHUNKY",
  }, {}, function(foundId, foundDigest)
    assert(foundId == id and foundDigest == digest)
    return { sha256 = digest }
  end)
  rawset(Loader, "user", originalUser)
  assert(ok and result == "restored")
end)

test("font names and repertoire", function()
  assert(Names.clean("  Font  Name ") == "Font Name" and Names.clean("bad\nname") == nil)
  assert(Repertoire.scalar("😀") == 0x1f600)
  local missing = Repertoire.missing({ A = true }, { "Z", "B", "Z", "A" })
  assert(table.concat(missing) == "BZ")
  assert(Repertoire.fallback("Z").renderFallback == "space")
  fails(function()
    Repertoire.scalar("AB")
  end)
  fails(function()
    Repertoire.budget({ kind = "truetype", cellWidth = 8, cellHeight = 8 }, 16385)
  end)
end)

test("Unicode names load on demand and handle unpopulated planes gracefully", function()
  local oldApp = app
  app = {
    fs = {
      filePath = require("tests.pure.filesystem").filePath,
      joinPath = require("tests.pure.filesystem").joinPath,
    },
  }
  package.loaded["src.unicode.names"] = nil
  local UnicodeNames = require("src.unicode.names")
  -- Plane 0 (BMP): populated plane
  assert(UnicodeNames.name(0x0041) == "LATIN CAPITAL LETTER A")
  -- Plane 1 (SMP): populated plane
  assert(UnicodeNames.name(0x1f600) == "GRINNING FACE")
  -- Plane 4: unpopulated plane (returns reserved range label)
  assert(UnicodeNames.name(0x40000) == "<reserved-40000>")
  -- Plane 15: private use area (falls back to range label)
  assert(UnicodeNames.name(0xf0000) == "<private-use-F0000>")
  -- Out-of-range codepoints
  assert(UnicodeNames.name(-1) == nil)
  assert(UnicodeNames.name(0x110000) == nil)
  -- Searching / matching
  assert(UnicodeNames.matches(0x0041, "capital"))
  assert(not UnicodeNames.matches(0x0041, "xyz123"))
  package.loaded["src.unicode.names"] = nil
  app = oldApp
end)

test("task completion cancellation errors and re-entry", function()
  local task
  local calls = 0
  task = Task.new(function(checkpoint)
    calls = calls + 1
    assert(not task:step())
    checkpoint()
    return 42
  end)
  assert(task:finish() == 42 and task.done and calls == 1)
  local canceled = Task.new(function()
    return 1
  end)
  canceled:cancel()
  assert(not canceled:step())
  local failed = Task.new(function()
    error("expected")
  end)
  fails(function()
    failed:step()
  end)
  assert(failed.done)
end)

test("new sprite defaults validate and resolve stable font identity", function()
  local Settings = require("src.core.settings")
  local prefs = {}
  local has_user = true
  local library = {
    catalog = function()
      local fonts = { { id = "atascii", kind = "bundled", label = "ATASCII" } }
      if has_user then
        fonts[#fonts + 1] = { id = "user-abc", kind = "user", label = "Renamed" }
      end
      return fonts
    end,
  }
  local defaults = Settings.read(prefs, library)
  assert(
    defaults.columns == 40
      and defaults.rows == 25
      and defaults.size == 8
      and defaults.backgroundColor == "#ffffff00"
  )
  Settings.save(prefs, 100, 30, 12, { id = "user-abc", kind = "user" }, "#11223344")
  local saved, missing = Settings.read(prefs, library)
  assert(
    saved.columns == 100
      and saved.rows == 30
      and saved.size == 12
      and saved.fontId == "user-abc"
      and saved.backgroundColor == "#11223344"
      and not missing
  )
  assert(Settings.update(prefs, library, "backgroundColor", "#AABBCCDD"))
  assert(Settings.read(prefs, library).backgroundColor == "#aabbccdd")
  assert(not Settings.update(prefs, library, "backgroundColor", "invalid"))
  assert(Settings.read(prefs, library).backgroundColor == "#aabbccdd")
  fails(function()
    Settings.save(prefs, 0, 30, 12, { id = "atascii", kind = "bundled" })
  end)
  fails(function()
    Settings.save(prefs, 40, 30, 12, { id = "atascii", kind = "bundled" }, "not-a-color")
  end)
  assert(prefs.newSpriteDefaults.columns == 100)
  has_user = false
  saved, missing = Settings.read(prefs, library)
  assert(missing and saved.fontId == "atascii" and saved.columns == 100)
  local ok = Settings.update(prefs, library, "rows", 31)
  assert(ok and prefs.newSpriteDefaults.fontId == "user-abc")
  has_user = true
  local recovered, stillMissing = Settings.read(prefs, library)
  assert(not stillMissing and recovered.fontId == "user-abc" and recovered.rows == 31)
  ok = Settings.update(prefs, library, "columns", 1024)
  assert(ok)
  ok = Settings.update(prefs, library, "rows", 1024)
  assert(ok)
  ok = Settings.update(prefs, library, "columns", 1025)
  assert(not ok and prefs.newSpriteDefaults.columns == 1024)
  ok = Settings.update(prefs, library, "size", 128)
  assert(ok)
  ok = Settings.update(prefs, library, "size", 129)
  assert(not ok and prefs.newSpriteDefaults.size == 128)
  prefs.newSpriteDefaults.columns, prefs.newSpriteDefaults.rows = 1025, 1025
  local repaired = Settings.read(prefs, library)
  assert(repaired.columns == 40 and repaired.rows == 25)
  fails(function()
    Settings.update(prefs, library, "unknown", 1)
  end)
  Settings.reset(prefs)
  assert(
    prefs.newSpriteDefaults.fontId == "atascii"
      and prefs.newSpriteDefaults.backgroundColor == "#ffffff00"
      and prefs.glyphGridSize == 20
      and prefs.stampClickTarget == "primary"
  )
  prefs.newSpriteDefaults.columns = 0 / 0
  prefs.newSpriteDefaults.backgroundColor = "bad"
  local fallback = Settings.read(prefs, library)
  assert(fallback.columns == 40 and fallback.backgroundColor == "#ffffff00")
end)

test("binary codec preserves all byte values and detects invalid inputs", function()
  local bytes = {}
  for i = 0, 255 do
    bytes[#bytes + 1] = string.char(i)
  end
  bytes = table.concat(bytes)
  for n = 0, 256 do
    local value = bytes:sub(1, n)
    assert(Binary.decode(Binary.encode(value), 256) == value)
  end
  for _, value in ipairs({ "A===", "AB==", "AAA", "AAAA====", "AA=A", "AAA!" }) do
    fails(function()
      Binary.decode(value, 256)
    end)
  end
  fails(function()
    Binary.decode(Binary.encode(bytes), 255)
  end)
  assert(Binary.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
end)

-- Execute modular pure test suites
require("tests.pure.font-names")(test)
require("tests.pure.font-repertoire")(test)
require("tests.pure.font-authors")(test)
require("tests.pure.validation")(test)
require("tests.pure.guard-errors")(test)
require("tests.pure.theme")(test)
require("tests.pure.font-preview")(test)
require("tests.pure.replace-preview")(test)
require("tests.pure.native-operations")(test)
require("tests.pure.font-replacement")(test)
require("tests.pure.import-pagination")(test)
require("tests.pure.export-summary")(test)
require("tests.pure.stamp-state")(test)
require("tests.pure.projects")(test)
require("tests.pure.flatten")(test)
require("tests.pure.cell-clipboard-workflow")(test)

test("numeric inputs auto-clamp upper bound and prevent negative numbers", function()
  local Controls = require("src.ui.controls")
  local controls = Controls.new()
  local modified = {}
  local changed = false
  local d
  d = {
    data = { count = "5000" },
    modify = function(_, arg)
      modified[arg.id] = arg
      d.data[arg.id] = arg.text
    end,
  }
  setmetatable(d, {
    __index = function()
      return function(self, arg)
        if type(arg) == "table" and arg.onchange then
          d.onchange = arg.onchange
        end
        return self
      end
    end,
  })
  controls:addNumericInput(d, "count", "Count", "10", {
    min = 1,
    max = 1024,
    onchange = function()
      changed = true
    end,
  })
  d.onchange()
  assert(modified.count and modified.count.text == "1024")
  assert(d.data.count == "1024")
  assert(changed)

  d.data.count = "-10"
  d.onchange()
  assert(modified.count.text == "1")
  assert(d.data.count == "1")

  d.data.count = "0"
  d.onchange()
  assert(modified.count.text == "1")
  assert(d.data.count == "1")
end)

test("settings panel suppresses range errors and auto-corrects minimums and on close", function()
  local previousApp, previousColor, previousTimer = app, Color, Timer
  local activeTimer
  app = {
    isUIAvailable = true,
    pixelColor = { TILE_XFLIP = 0x10000000, TILE_YFLIP = 0x20000000, TILE_DFLIP = 0x40000000 },
    fs = {
      filePath = require("tests.pure.filesystem").filePath,
      joinPath = require("tests.pure.filesystem").joinPath,
    },
  }
  Color = function(c)
    return c
  end
  Timer = function(opts)
    local t = {
      ontick = opts.ontick,
      start = function(self)
        activeTimer = self
      end,
      stop = function(self)
        if activeTimer == self then
          activeTimer = nil
        end
      end,
    }
    return t
  end
  local ok, err = pcall(function()
    local Controller = require("src.ui.controller")
    local prefs = {}
    local controller = Controller.new({ preferences = prefs })
    local modified = {}
    local registeredClose
    local d
    d = {
      data = {
        defaultColumns = 40,
        defaultRows = 25,
        defaultFont = "ATASCII",
        size = 8,
        defaultBackgroundColor = { red = 255, green = 255, blue = 255, alpha = 0 },
        glyphGridSize = "20",
      },
      modify = function(_, arg)
        modified[arg.id] = arg
        if arg.text and d.data[arg.id] ~= nil then
          d.data[arg.id] = tonumber(arg.text) or arg.text
        end
      end,
      repaint = function() end,
      close = function() end,
      show = function(self)
        return self
      end,
    }
    local controls = {}
    setmetatable(d, {
      __index = function()
        return function(self, arg)
          if type(arg) == "table" and arg.id then
            controls[arg.id] = arg
          end
          return self
        end
      end,
    })
    controller.dialog = function(_, _, options)
      registeredClose = options and options.onclose
      return d
    end

    controller:settings()

    -- Typing 400000 into defaultColumns auto-clamps without error to 1024
    d.data.defaultColumns = "400000"
    controls.defaultColumns.onchange()
    assert(d.data.defaultColumns == 1024)
    assert(modified.defaultColumns and modified.defaultColumns.text == "1024")
    assert(not modified.settingsError or modified.settingsError.visible == false)
    assert(prefs.newSpriteDefaults.columns == 1024)

    -- Typing 5000 into size auto-clamps without error to 128
    d.data.size = "5000"
    controls.size.onchange()
    assert(d.data.size == 128)
    assert(modified.size and modified.size.text == "128")
    assert(not modified.settingsError or modified.settingsError.visible == false)
    assert(prefs.newSpriteDefaults.size == 128)

    -- Typing 0 into defaultColumns immediately resets to 1
    d.data.defaultColumns = 0
    controls.defaultColumns.onchange()
    assert(d.data.defaultColumns == 1)
    assert(modified.defaultColumns and modified.defaultColumns.text == "1")
    assert(not modified.settingsError or modified.settingsError.visible == false)
    assert(prefs.newSpriteDefaults.columns == 1)

    -- Typing 0 into size (min = 8) schedules debounced auto-correction to 8
    d.data.size = 0
    controls.size.onchange()
    assert(activeTimer ~= nil)
    activeTimer.ontick()
    assert(d.data.size == 8)
    assert(modified.size and modified.size.text == "8")
    assert(prefs.newSpriteDefaults.size == 8)

    -- Closing the dialog also guarantees valid bounds
    d.data.size = 2
    registeredClose()
    assert(prefs.newSpriteDefaults.size == 8)
  end)
  app, Color, Timer = previousApp, previousColor, previousTimer
  if not ok then
    error(err)
  end
end)

require("tests.pure.domain-helpers")(test)

print("ASEMODE_PURE_OK " .. count)
