# Third-party notices

## Font licenses

Font data is stored as generated Lua byte resources. Each font retains its own
license; the Asemode MIT license applies to Asemode code.

### Default repository fonts

- **[UrsaFont](https://ursafrank.itch.io/ursafont)**
  - Creator: [UrsaFrank](https://ursafrank.itch.io/)
  - License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

- **[ATASCII](https://codeberg.org/Dmian/font-atascii), [BESCII](https://codeberg.org/Dmian/font-bescii), and [CPC464](https://codeberg.org/Dmian/font-cpc464)**
  - Creator: [Damian Vila](https://damianvila.com/)
  - License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

- **[DUNGEON.mode](https://datagoblin.itch.io/dungeonmode)**
  - Creator: [datagoblin](https://datagoblin.itch.io/)
  - License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

- **[UNSCII 8, Alt, MCR, Thin, and Fantasy](https://github.com/viznut/unscii)**
  - Creator: [Viznut](https://viznut.fi/)
  - License: Public domain or CC0, according to the upstream statement

- **[Rook](https://outer-spec.itch.io/rook)**
  - Creator: [Quintin Stokes (Funky Tiger Highsaturn)](https://autojunkio.itch.io/)
  - License: The download page permits use for any purpose but does not specify a formal license

### Additional fonts in official release builds

- **[CHUNKY](https://batfeula.itch.io/chunky)**
  - Creator: [Batfeula](https://batfeula.neocities.org/)
  - License: [CHUNKY license](assets/fonts/licenses/CHUNKY.txt) from the itch.io download

- **[FROGBLOCK](https://polyducks.itch.io/frogblock)**
  - Creator: [Polyducks](https://polyducks.co.uk/)
  - License: [FROGBLOCK license](assets/fonts/licenses/FROGBLOCK.txt) from the V2.1 download

- **[Kitchen Sink](https://polyducks.itch.io/kitchen-sink-textmode-font)**
  - Creators: [Retroshark](https://chasehunter.itch.io/) and [Polyducks](https://polyducks.co.uk/)
  - License: [Kitchen Sink license](assets/fonts/licenses/KITCHEN-SINK.txt) from the V1.2 download

- **[IBM CGA](https://int10h.org/oldschool-pc-fonts/)**
  - Creator: [VileR](https://int10h.org/)
  - License: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

- **[Cultist Script, Mycelium OG, and T64](https://littlebitspace.com/resources/)**
  - Creator: [littlebitspace](https://littlebitspace.com/)
  - License: Included under permission communicated to the project maintainer

> [!NOTE]
> Official release builds *(on GitHub Releases and itch.io)* include all 18 fonts
> for convenience. The seven optional font files remain untracked in the Git
> repository, are not included in the MIT-licensed source tree, and are not
> required to develop or build Asemode from source.
>
> Each optional font has its own terms. Consult the creator's license before
> using or redistributing a font. Inclusion in Asemode does not make a font
> MIT-licensed or CC0.

## Unicode character names

The generated character names, aliases, and code point labels in
[`src/unicode/names/`](src/unicode/names/) and
[`src/unicode/name-label-ranges.lua`](src/unicode/name-label-ranges.lua) are based on
[`unicode-name`](https://www.npmjs.com/package/unicode-name) 1.2.1 by Jan Lelis (MIT). See
[`scripts/build/generate-unicode-names.mjs`](https://github.com/humanbydefinition/Asemode/blob/main/scripts/build/generate-unicode-names.mjs) for the generator.

## TrueType font parser

[Typr.js](https://github.com/photopea/Typr.js) by Photopea was a reference for
the TrueType font parser. Typr.js is licensed under the
[MIT License](https://github.com/photopea/Typr.js/blob/gh-pages/LICENSE).
Asemode implements font parsing and rendering in Lua. See
[`src/fonts/truetype.lua`](src/fonts/truetype.lua) and
[`src/fonts/render.lua`](src/fonts/render.lua).

## Aseprite API type definitions

The development type definitions in [`tools/meta/aseprite.lua`](tools/meta/aseprite.lua)
are derived from the [Aseprite Scripting API](https://github.com/aseprite/api)
documentation (Copyright © 2018–2024 Igara Studio S.A., Copyright © 2015–2018
David Capello), licensed under the
[MIT License](https://github.com/aseprite/api/blob/main/LICENSE.txt), via
[Tsukina-7mochi/aseprite-type-definition](https://github.com/Tsukina-7mochi/aseprite-type-definition).
