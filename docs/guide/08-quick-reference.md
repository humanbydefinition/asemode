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

| Font ID | Display Name | Native Cell Size |
| :--- | :--- | :--- |
| `atascii` | ATASCII | 8×8 px |
| `bescii` | BESCII | 8×8 px |
| `chunky` | CHUNKY | 8×8 px |
| `cpc464` | CPC464 | 8×8 px |
| `cultist-script` | Cultist Script | 8×8 px |
| `dungeon-mode` | DUNGEON.mode | 8×8 px |
| `frogblock` | FROGBLOCK | 8×8 px |
| `ibm-cga` | IBM CGA | 8×8 px |
| `kitchen-sink` | Kitchen Sink | 6×8 px |
| `mycelium-og` | Mycelium OG | 8×8 px |
| `rook` | Rook | 8×8 px |
| `t64` | T64 | 8×8 px |
| `unscii-8` | UNSCII 8 | 8×8 px |
| `unscii-8-alt` | UNSCII 8 Alt | 8×8 px |
| `unscii-8-fantasy` | UNSCII 8 Fantasy | 8×8 px |
| `unscii-8-mcr` | UNSCII 8 MCR | 8×8 px |
| `unscii-8-thin` | UNSCII 8 Thin | 8×8 px |
| `ursafont` | UrsaFont | 8×8 px |

---

## 3. Supported Unicode Blocks & Ranges

Asemode's glyph browser lazy-loads character names across Unicode planes and indexes glyphs against all 340+ official **Unicode 16.0 blocks**. The panel's category selector dynamically populates with any block present in the active font, including common textmode groups such as:

- **Basic Latin (ASCII):** Codes `U+0000` to `U+007F` (standard alphanumeric text, punctuation, and control symbols).
- **Latin-1 Supplement & Extended:** Codes `U+0080` to `U+024F` (accented characters, currency, and symbols).
- **Arrows & Math Operators:** Codes `U+2190` to `U+22FF` (directional arrows, arithmetic, and logic symbols).
- **Box Drawing:** Codes `U+2500` to `U+257F` (single, double, triple, and rounded line connectors).
- **Block Elements:** Codes `U+2580` to `U+259F` (solid, shaded, half, and quadrant blocks).
- **Geometric Shapes & Symbols:** Codes `U+25A0` to `U+27BF` (geometric forms, miscellaneous symbols, and dingbats).

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
