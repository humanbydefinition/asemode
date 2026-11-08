return function(test)
  local Names = require("src.fonts.names")
  local function equal(a, b)
    assert(a == b, tostring(a) .. " ~= " .. tostring(b))
  end

  local function naming(records, format, tags)
    local body, rows = {}, {}
    local length = 0
    for _, r in ipairs(records) do
      local text = r[5]
      rows[#rows + 1] = string.pack(">I2I2I2I2I2I2", r[1], r[2], r[3], r[4], #text, length)
      body[#body + 1] = text
      length = length + #text
    end
    local tagRows = {}
    for _, tag in ipairs(tags or {}) do
      tagRows[#tagRows + 1] = string.pack(">I2I2", #tag, length)
      body[#body + 1] = tag
      length = length + #tag
    end
    local tagHeader = format == 1 and (string.pack(">I2", #tagRows) .. table.concat(tagRows)) or ""
    local data = string.pack(">I2I2I2", format or 0, #records, 6 + #rows * 12 + #tagHeader)
      .. table.concat(rows)
      .. tagHeader
      .. table.concat(body)
    local t = {}
    function t:at(o, n)
      assert(o >= 0 and n >= 0 and o + n <= #data, "bounds")
      return o + 1
    end

    function t:u8(o)
      return data:byte(self:at(o, 1))
    end

    function t:u16(o)
      return string.unpack(">I2", data, self:at(o, 2))
    end
    return t
  end

  local function utf16(text)
    local out = {}
    for _, cp in utf8.codes(text) do
      if cp >= 0x10000 then
        cp = cp - 0x10000
        out[#out + 1] = string.pack(">I2I2", 0xd800 + (cp >> 10), 0xdc00 + (cp & 1023))
      else
        out[#out + 1] = string.pack(">I2", cp)
      end
    end
    return table.concat(out)
  end

  test(
    "font naming decodes Unicode, styles, language priorities, Roman and damaged records",
    function()
      equal(Names.read(naming({ { 3, 1, 0x409, 4, utf16(" Example 😀 ") } })), "Example 😀")
      equal(
        Names.read(
          naming({ { 3, 1, 0x407, 4, utf16("German") }, { 3, 1, 0x409, 4, utf16("English") } })
        ),
        "English"
      )
      equal(
        Names.read(naming({ { 0, 4, 0, 16, utf16("Family") }, { 0, 4, 0, 17, utf16("Bold") } }, 1)),
        "Family Bold"
      )
      equal(
        Names.read(
          naming({ { 3, 1, 0x409, 1, utf16("Family") }, { 3, 1, 0x409, 2, utf16("Regular") } })
        ),
        "Family"
      )
      equal(Names.read(naming({ { 1, 0, 0, 4, string.char(128) .. " Font" } })), "Ä Font")
      equal(
        Names.read(naming({ { 3, 1, 0x409, 4, "\216\0" }, { 0, 4, 0, 1, utf16("Fallback") } })),
        "Fallback"
      )
      equal(
        Names.read(
          naming({ { 3, 1, 0x409, 16, utf16("Family") }, { 3, 1, 0x407, 17, utf16("Fett") } })
        ),
        "Family"
      )
      equal(
        Names.read(
          naming(
            { { 0, 4, 0x8000, 4, utf16("French") }, { 0, 4, 0x8001, 4, utf16("English tag") } },
            1,
            { utf16("fr"), utf16("en-US") }
          )
        ),
        "English tag"
      )
      equal(Names.read(naming({ { 0, 4, 0, 4, "a" }, { 3, 1, 0x409, 1, utf16("Safe") } })), "Safe")
      equal(Names.clean("  A  B  "), "A B")
      equal(Names.clean("a\0b"), nil)
      equal(Names.clean("a\nb"), nil)
      equal(Names.clean(string.rep("a", 129)), nil)
      equal(Names.fallback("/fonts/My Font.ttf"), "My Font")
      equal(Names.fallback(""), "Untitled Font")
      equal(Names.fallback("/fonts/"), "Untitled Font")
      equal(Names.read(naming({})), nil)
    end
  )

  test("font designer metadata uses supported localized name records", function()
    local name, author = Names.read(naming({
      { 3, 1, 0x407, 9, utf16("Deutsch") },
      { 3, 1, 0x409, 9, utf16("  Designer 😀  ") },
      { 3, 1, 0x409, 4, utf16("Font") },
      { 3, 1, 0x409, 8, utf16("Manufacturer") },
    }))
    equal(name, "Font")
    equal(author, "Designer 😀")
    name, author = Names.read(naming({ { 1, 0, 0, 9, string.char(128) .. " Artist" } }))
    equal(author, "Ä Artist")
    name, author = Names.read(naming({
      { 0, 4, 0x8000, 9, utf16("Français") },
      { 0, 4, 0x8001, 9, utf16("English") },
    }, 1, { utf16("fr"), utf16("en-US") }))
    equal(author, "English")
    name, author = Names.read(naming({
      { 3, 1, 0x409, 9, "\216\0" },
      { 0, 4, 0, 9, utf16("Valid") },
    }))
    equal(author, "Valid")
    name, author = Names.read(naming({ { 3, 1, 0x409, 8, utf16("Manufacturer") } }))
    equal(author, nil)
    name, author = Names.read(naming({ { 3, 1, 0x409, 9, utf16("Bad\nName") } }))
    equal(author, nil)
    name, author = Names.read(naming({ { 3, 1, 0x409, 9, utf16(string.rep("A", 129)) } }))
    equal(author, nil)
    name, author = Names.read(naming({ { 3, 1, 0x409, 9, utf16("   ") } }))
    equal(author, nil)
    name, author = Names.read(naming({ { 0, 4, 0x8000, 9, utf16("Invalid tag") } }, 1))
    equal(author, nil)
    equal(
      Names.read({
        u16 = function()
          error("truncated")
        end,
      }),
      nil
    )
  end)
end
