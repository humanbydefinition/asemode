# Quick Reference & Command Palette

[← Previous: Settings, Customization & Shortcuts](07-settings-and-shortcuts.md) | [User Guide Home](../USER_GUIDE.md)

---

This reference chapter provides a complete lookup matrix of all Asemode menu entries, Lua command IDs, font specifications, Unicode blocks, and troubleshooting answers.

---

## 1. Master Command Matrix

All commands listed below can be triggered from the Aseprite menu, mapped to keyboard shortcuts in **Edit > Keyboard Shortcuts**, or executed via the Command Palette (**View > Run Command**).

### Document & Workspace Commands

| Menu Path | Title | Command ID | Enabled Condition | Description |
| :--- | :--- | :--- | :--- | :--- |
| `Sprite > Asemode` | **New Textmode Sprite..** | `AsemodeNew` | Always | Opens new textmode sprite wizard. |
| `Sprite > Asemode` | **Import Textmode JSON..** | `AsemodeImport` | Always | Imports `.textmode.json` document. |
| `Sprite > Asemode` | **Open/Close Asemode Panel** | `AsemodePanel` | Always | Toggles dockable drawing panel. |
| `Sprite > Asemode` | **Add Textmode Layer..** | `AsemodeLayer` | RGB Sprite active | Adds a new textmode tilemap layer. |
| `Sprite > Asemode` | **Fonts..** | `AsemodeFont` | Always | Opens font manager & TTF upload. |
| `Sprite > Asemode` | **Grid..** | `AsemodeRegrid` | Textmode sprite | Opens cell & grid dimension editor. |
| `Sprite > Asemode` | **Export..** | `AsemodeExport` | Textmode layer | Exports layer(s) to `.textmode.json`. |
| `Sprite > Asemode` | **Settings..** | `AsemodeSettings` | Always | Opens preferences & sprite defaults. |
| `Sprite > Asemode` | **Keyboard Shortcuts...** | `AsemodeKeyboardShortcuts`| UI available | Opens Aseprite shortcut manager. |
| `Sprite > Asemode` | **About..** | `AsemodeCredits` | Always | Displays credits, specimens & licenses.|

---

### Selection & Clipboard Commands

| Menu Path | Title | Command ID | Enabled Condition | Description |
| :--- | :--- | :--- | :--- | :--- |
| `Sprite > Asemode > Selection` | **Replace..** | `AsemodeReplace` | Textmode layer active | Replaces glyphs, ink, or cell colors. |
| `Sprite > Asemode > Selection` | **Copy** | `AsemodeCopyCells` | Active selection on text layer | Copies selected cells to clipboard. |
| `Sprite > Asemode > Selection` | **Paste** | `AsemodePasteCells` | Text layer & cells in clipboard | Pastes copied cells snapping to grid. |

---

### Stamp Transform Actions (Primary, Secondary, Both)

Stamp actions can be triggered for the **Primary Stamp** (prefix `Asemode`), **Secondary Stamp** (prefix `AsemodeSecondary`), or **Both Stamps** (prefix `AsemodeBoth`).

| Action | Primary Stamp Command | Secondary Stamp Command | Both Stamps Command |
| :--- | :--- | :--- | :--- |
| **Swap Colors** | `AsemodeSwapColors` | `AsemodeSecondarySwapColors` | `AsemodeBothSwapColors` |
| **Flip Horizontally** | `AsemodeFlipHorizontal` | `AsemodeSecondaryFlipHorizontal` | `AsemodeBothFlipHorizontal` |
| **Flip Vertically** | `AsemodeFlipVertical` | `AsemodeSecondaryFlipVertical` | `AsemodeBothFlipVertical` |
| **Rotate 90° Clockwise** | `AsemodeRotateClockwise` | `AsemodeSecondaryRotateClockwise`| `AsemodeBothRotateClockwise` |
| **Rotate 90° Counterclockwise** | `AsemodeRotateCounterclockwise`| `AsemodeSecondaryRotateCounterclockwise` | `AsemodeBothRotateCounterclockwise` |
| **Reset Orientation** | `AsemodeResetOrientation`| `AsemodeSecondaryResetOrientation` | `AsemodeBothResetOrientation` |

---

## 2. Bundled Retro Font Specifications

| Font ID | Display Name | Native Cell Size | Best For | Character Set |
| :--- | :--- | :--- | :--- | :--- |
| `atascii` | ATASCII | 8×8 px | Atari 8-bit demos, retro gaming | Atari standard character set |
| `bescii` | Bescii Mono | 8×8 px | BESCII textmode art | Monospace Latin & box drawing |
| `cpc464` | Amstrad CPC 464 | 8×8 px | European 8-bit aesthetic | CPC 464 system characters |
| `dungeonmode` | Dungeon Mode | 8×8 px | Roguelike games, gothic maps | Fantasy symbols, runes, borders |
| `rook` | Rook | 8×8 px | Minimalist micro-graphics | Geometric icons & Latin |
| `t64` | T64 | 8×8 px | C64 / PETSCII style art | PETSCII-inspired graphics |
| `ursafont` | UrsaFont | 8×8 px | Arcade text & UI elements | Pixel display lettering |
| `unscii-8` | Unscii Standard | 8×8 px | General ASCII/Unicode art | Full Basic Latin, Box, Blocks |
| `unscii-8-thin` | Unscii Thin | 8×8 px | High-density text overlays | Thin 1px stroke Latin & symbols |
| `unscii-8-alt` | Unscii Alternate | 8×8 px | Stylized retro computing | Distinct serifs and glyph curves |
| `unscii-8-mcr` | Unscii Micro | 8×8 px | Compact tech UI | Condensed technical symbols |
| `unscii-8-fantasy`| Unscii Fantasy | 8×8 px | Narrative titles & lore | Ornate fantasy lettering |

---

## 3. Supported Unicode Blocks & Ranges

Asemode's glyph browser lazy-loads over 170,000 Unicode character names across 5 planes:

- **Basic Latin (ASCII):** Codes `U+0020` to `U+007E` (standard alphanumeric text and punctuation).
- **Latin-1 Supplement:** Codes `U+00A0` to `U+00FF` (accented characters, copyright, currency).
- **Box Drawing:** Codes `U+2500` to `U+257F` (single, double, triple, and rounded line borders).
- **Block Elements:** Codes `U+2580` to `U+259F` (light, medium, dark shades, quadrant blocks).
- **Geometric Shapes:** Codes `U+25A0` to `U+25FF` (triangles, diamonds, circles, stars).
- **Miscellaneous Symbols:** Codes `U+2600` to `U+26FF` (card suits, weather, musical notes).

---

## 4. Frequently Asked Questions (FAQ)

### Q: Why does Aseprite say "Asemode layers require RGB color mode"?
**A:** Asemode stores independent 32-bit RGBA foreground and background colors in each cell. Indexed and Grayscale modes cannot support per-cell dual palettes. Convert your sprite to RGB (**Sprite > Color Mode > RGB Color**) before adding textmode layers.

### Q: Can I animate textmode layers?
**A:** Yes! Asemode layers are native Aseprite tilemap layers. You can add cels, create timeline tags, adjust frame durations, and use onion skinning just like with standard pixel art layers.

### Q: Why did Aseprite block my blur/invert filter?
**A:** Applying raster filters directly to tilesets would distort the 1-bit font glyph masks. To apply filters, add a standard raster layer behind or above your textmode layer.

### Q: Can I export transparent textmode art?
**A:** Yes! When drawing, set your **Cell Color** (background) to transparent (alpha `0`). When you export via **File > Export As...**, only the glyph strokes will be rendered.

### Q: How do I round-trip between Aseprite and `create.textmode.art`?
**A:** Export your Aseprite artwork using **Sprite > Asemode > Export..** as `.textmode.json`. Open `create.textmode.art`, drag the JSON file in, edit in the browser, export again, and use **Sprite > Asemode > Import Textmode JSON..** to bring it back into Aseprite.

---

[← Previous: Settings, Customization & Shortcuts](07-settings-and-shortcuts.md) • [User Guide Home](../USER_GUIDE.md)
