# Multi-Layer Architecture & Composition

[← Previous: The Asemode Panel & Drawing Workflow](01-panel-and-drawing.md) | [User Guide Home](../USER_GUIDE.md) | [Next: Fonts & Typography System →](03-fonts-and-typography.md)

---

One of Asemode's most powerful capabilities is its **hybrid layer architecture**. Rather than restricting you to a single monolithic text canvas, Asemode allows you to mix standard Aseprite pixel art layers, animation frames, and multiple textmode layers—each with its own independent typography, opacity, and blending mode.

---

## 1. Adding Textmode Layers

You can add any number of textmode layers to an existing RGB sprite.

### How to Add a Textmode Layer

1. Open or focus on an RGB sprite.
2. Select **Sprite > Asemode > Add Textmode Layer..** (Command: `AsemodeLayer`).
3. In the dialog, configure your layer preferences:
   - **Layer Name:** A descriptive label (e.g., `HUD_Text`, `Foreground_ASCII`, `Dialogue`).
   - **Font:** Select any bundled retro font or user-installed TrueType font.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/add-layer.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/add-layer.png">
  <img alt="Add Textmode Layer dialog showing layer name field and font selection options." src="../images/screenshots/dark/add-layer.png" width="480">
</picture>

4. Click **OK**. Asemode creates a new tilemap layer bound to your chosen font and seamlessly aligns it to your canvas grid.

> [!TIP]
> You can assign different fonts to different layers! For example, use a bold headline font like `dungeonmode` for chapter banners, paired with a readable mono font like `atascii` or `unscii-8` for narrative copy.

---

## 2. Hybrid Compositions: Mixing Pixel Art and Textmode

Asemode documents are fully compatible with Aseprite's timeline and layer stack:

```text
Layer Stack Hierarchy:
┌───────────────────────────────────────────────┐
│ [Textmode Layer] "UI_HUD"       (Font: unscii)│
├───────────────────────────────────────────────┤
│ [Raster Layer]   "Character_Sprite" (Pixel Art)│
├───────────────────────────────────────────────┤
│ [Textmode Layer] "ASCII_Backdrop" (Font: t64) │
├───────────────────────────────────────────────┤
│ [Raster Layer]   "Background_Gradient"        │
└───────────────────────────────────────────────┘
```

- **Layer Ordering:** Drag layers up or down in Aseprite's timeline. Textmode layers can sit above or below pixel art.
- **Blending Modes:** Adjust layer blending modes (Multiply, Screen, Overlay, Addition) directly in Aseprite's layer properties.
- **Layer Opacity:** Set layer opacity slider to create subtle ghostly text overlays or shaded scanline effects.
- **Transparent Cells:** When cell background color opacity is 0, only glyph strokes are visible, letting underlying raster layers shine through cleanly.

---

## 3. Cell-Aware Clipboard: Copy & Paste

Standard Aseprite clipboard commands (`Ctrl+C` / `Ctrl+V` or `Cmd+C` / `Cmd+V`) operate on raw pixel bitmaps. On textmode layers, raw pixel pasting would break character-cell identity. 

To preserve character semantics, Asemode provides **dedicated cell clipboard actions**:

### Copying Cells
1. Make a marquee selection using Aseprite's Rectangular Marquee (`M`) or Lasso tool.
2. Choose **Sprite > Asemode > Selection > Copy** (Command: `AsemodeCopyCells`).
3. The selected character cells, glyph IDs, ink colors, and cell background colors are captured into Asemode's clipboard buffer.

### Pasting Cells
1. Move your cursor to the desired target position or switch to another textmode layer.
2. Choose **Sprite > Asemode > Selection > Paste** (Command: `AsemodePasteCells`).
3. The copied cells are placed into the active layer, snapping perfectly to grid cells.

### Handling Missing Glyphs on Paste
If you copy text cells from a layer using a comprehensive font (such as `unscii-8`) and paste them into a layer using an 8-bit retro font (such as `atascii`) that lacks certain characters, Asemode detects the mismatch and opens a safety alert:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/alert-paste-missing-glyphs.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/alert-paste-missing-glyphs.png">
  <img alt="Alert modal warning that pasted cells contain characters missing in the active layer's font, offering substitute options." src="../images/screenshots/dark/alert-paste-missing-glyphs.png" width="500">
</picture>

> [!WARNING]
> Characters not present in the destination font will be substituted with a fallback glyph (typically a space or replacement marker). Review the preview before confirming to avoid unwanted character substitution.

---

## 4. Search and Replace in Selections

The **Replace** tool provides surgical substitution of characters and color channels across a region or the whole layer.

### Step 1: Open the Replace Dialog
Make an active marquee selection, then choose **Sprite > Asemode > Selection > Replace..** (Command: `AsemodeReplace`).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/replace-selection.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/replace-selection.png">
  <img alt="Replace selection dialog showing source glyph and color fields on the left and target replacement fields on the right, with live preview." src="../images/screenshots/dark/replace-selection.png" width="540">
</picture>

### Step 2: Configure Search & Replacement Targets
The dialog lets you specify any combination of three search criteria:
- **Glyph Replacement:** Find character `A` and replace with character `B`.
- **Ink Color Replacement:** Change all red foreground strokes to cyan.
- **Cell Color Replacement:** Change all black cell backgrounds to dark blue.

### Step 3: Scope & Empty Selection Behavior
If you invoke the command without an active selection box, Asemode displays an empty selection notice:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/replace-selection-empty.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/replace-selection-empty.png">
  <img alt="Replace selection dialog when no marquee selection is active, indicating apply is disabled until a selection or layer scope is chosen." src="../images/screenshots/dark/replace-selection-empty.png" width="540">
</picture>

To apply replacements across the entire layer, simply press `Ctrl+A` (or `Cmd+A`) to select all canvas cells before launching the dialog.

---

## 5. Next Steps

- [Proceed to Chapter 3: Fonts & Typography System →](03-fonts-and-typography.md)
- [Jump to Chapter 4: Canvas, Grids & Regridding →](04-canvas-and-grids.md)
- [Back to User Guide Overview](../USER_GUIDE.md)
