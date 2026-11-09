# Fonts & Typography System

[← Previous: Multi-Layer Architecture & Composition](02-layers-and-composition.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Canvas, Grids & Regridding →](04-canvas-and-grids.md)

---

Typography is the core visual engine of textmode art. Asemode pairs **18 bundled retro pixel typefaces** with an extensible **TrueType font importer**, allowing you to bring classic or custom typefaces into your artwork.

---

## 1. Bundled Retro Font Catalog

Asemode comes pre-packaged with curated bitmap fonts representing computing history and textmode culture:

| Font Identifier | Display Name | Cell Size | Vintage Origin / Aesthetic |
| :--- | :--- | :--- | :--- |
| `atascii` | ATASCII | 8×8 | Atari 8-bit home computers (400/800/XL/XE). |
| `bescii` | Bescii Mono | 8×8 | BESCII textmode standard. |
| `cpc464` | Amstrad CPC 464 | 8×8 | Classic 1980s British 8-bit microcomputer. |
| `dungeonmode` | Dungeon Mode | 8×8 | Roguelike fantasy symbols and gothic runes. |
| `rook` | Rook | 8×8 | Minimalist geometric bitmap font. |
| `t64` | T64 | 8×8 | Commodore 64 / PETSCII-inspired character set. |
| `ursafont` | UrsaFont | 8×8 | Stylized arcade bitmap font. |
| `unscii-8` | Unscii Standard | 8×8 | Comprehensive Unicode block and box drawing font. |
| `unscii-8-thin` | Unscii Thin | 8×8 | Lightweight delicate strokes for high density. |
| `unscii-8-alt` | Unscii Alternate | 8×8 | Alternate stylized glyph variants. |
| `unscii-8-mcr` | Unscii Micro | 8×8 | Dense technical computing character set. |
| `unscii-8-fantasy`| Unscii Fantasy | 8×8 | Ornate decorative lettering. |

### Font Specimens & Licenses
Inspect character specimens, author attributions, and open-source licenses for any font under **Sprite > Asemode > About..** on the **Fonts** tab:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/about-fonts.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/about-fonts.png">
  <img alt="About dialog Fonts tab showing specimen preview, font description, and open source license credits." src="../images/screenshots/dark/about-fonts.png" width="540">
</picture>

---

## 2. Managing Fonts

Open the font manager via **Sprite > Asemode > Fonts..** (Command: `AsemodeFont`).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/font.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/font.png">
  <img alt="Fonts dialog Library tab listing bundled and user fonts with details, cell size, and action buttons." src="../images/screenshots/dark/font.png" width="540">
</picture>

The **Library** tab lists all registered fonts, their cell dimensions, origin (`bundled` or `user`), and quick actions to apply them to your active layer.

---

## 3. Importing Custom TrueType (.ttf) Fonts

Asemode rasterizes static TrueType vector fonts into 1-bit pixel masks suitable for character cells:

1. In the Fonts dialog, switch to the **Upload .ttf** tab.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/font-upload.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/font-upload.png">
  <img alt="Fonts dialog Upload .ttf tab showing file browser, font size input, baseline offset, and rasterization options." src="../images/screenshots/dark/font-upload.png" width="540">
</picture>

2. Choose a `.ttf` file from your computer.
3. Configure rasterization parameters:
   - **Font Size (px):** Target pixel height (typically `8`, `12`, `16`, or `24`).
   - **Baseline Offset:** Adjust vertical alignment within the cell box.
4. Click **Next** to proceed to the metrics preview.

---

## 4. Font Metrics Preview & Clipping Diagnostics

Before finalizing an import, Asemode analyzes character cell bounds and displays the **Font Metrics Preview**:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/font-metrics-preview.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/font-metrics-preview.png">
  <img alt="Font Metrics Preview dialog displaying glyph specimen, bounding box, ascent, descent, and cell size." src="../images/screenshots/dark/font-metrics-preview.png" width="520">
</picture>

### Resolving Clipping Warnings
If character outlines exceed cell bounds (e.g. descenders in `g`, `j`, `y` or tall accents in `Â`, `Ê`), Asemode flags the clipping in red:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/font-metrics-preview-clipping.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/font-metrics-preview-clipping.png">
  <img alt="Font Metrics Preview dialog highlighting clipped glyph outlines in red with warning diagnostics." src="../images/screenshots/dark/font-metrics-preview-clipping.png" width="520">
</picture>

> [!WARNING]
> Clipped glyphs will have outer pixels cropped on the canvas. If clipping warnings appear, return to the upload tab to increase the font size or adjust baseline offsets.

---

## 5. User Font Management

Click **Manage User Fonts** in the Fonts dialog to audit, delete, or clean up custom typefaces:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/manage-user-fonts-populated.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/manage-user-fonts-populated.png">
  <img alt="Manage User Fonts dialog listing custom installed user fonts with author metadata and delete buttons." src="../images/screenshots/dark/manage-user-fonts-populated.png" width="520">
</picture>

- **Deleting Fonts:** Click **Delete** next to any user font. Active layers using this font will fall back to default typography.
- **Resetting Library:** Click **Reset** to restore a clean font library if preferences become damaged.
- **Corrupt Font Handling:** If a custom font file becomes corrupted or unreadable, Asemode displays a recovery notice, allowing you to delete the broken entry without affecting other fonts.

---

[← Previous: Multi-Layer Architecture & Composition](02-layers-and-composition.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Canvas, Grids & Regridding →](04-canvas-and-grids.md)
