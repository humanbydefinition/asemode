# Canvas, Grids & Regridding

[← Previous: Fonts & Typography System](03-fonts-and-typography.md) • [User Guide Home](README.md) • [Next: Portable Interchange & Ecosystem Integration →](05-portable-interchange.md)

---

In textmode art, document dimensions are measured in **character cells** rather than raw pixels. Asemode manages the mathematical relationship between character columns/rows, cell pixel sizes, and the underlying Aseprite canvas.

---

## 1. Understanding Textmode Coordinates

$$\text{Canvas Width (px)} = \text{Columns} \times \text{Cell Width (px)}$$
$$\text{Canvas Height (px)} = \text{Rows} \times \text{Cell Height (px)}$$

Because each tile in Aseprite's tilemap corresponds directly to one character cell, arbitrary pixel resizing can break grid alignment. To resize your artwork safely, always use Asemode's **Grid** command.

---

## 2. The Grid Configuration Dialog

To adjust your grid or cell dimensions, open **Sprite > Asemode > Grid..** (Command: `AsemodeRegrid`).

### Tab 1: Grid Size
Expand or contract the number of character columns and rows:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/grid-size.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/grid-size.png">
  <img alt="Grid dialog Grid Size tab showing columns and rows inputs alongside resize grid button." src="../images/screenshots/dark/grid-size.png" width="500">
</picture>

- **Columns & Rows:** Set new grid dimensions (e.g., expand from 40 to 80 columns). Existing artwork anchors to the top-left.
- Click **Resize grid..** to preview changes in the **Confirm canvas size** dialog.

### Tab 2: Cell Size
Adjust the pixel width and height of each character cell:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/grid.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/grid.png">
  <img alt="Grid dialog Cell Size tab showing Cell width and Cell height inputs for character cells." src="../images/screenshots/dark/grid.png" width="500">
</picture>

- **Cell width & Cell height:** Scales pixel dimensions per cell while preserving total character columns and rows.
- Each textmode layer keeps its font size. Asemode re-renders glyphs for the new cell dimensions, so larger cells can reveal previously clipped parts of a font.
- Useful when migrating artwork to a font with a different aspect ratio (e.g. from 8×8 square to 8×16 tall).
- Click **Resize cells..** to open the **Confirm regrid** dialog.

---

## 3. Regrid Confirmation & Content Protection

When you resize cell dimensions via `Resize cells..`, Asemode evaluates all textmode layers across every animation cel:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/confirm-regrid-warnings.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/confirm-regrid-warnings.png">
  <img alt="Confirm regrid dialog displaying warning banner about truncated cells and content impact." src="../images/screenshots/dark/confirm-regrid-warnings.png" width="500">
</picture>

- The dialog summarizes cell size changes, visible grid dimensions, and the number of fonts used by textmode layers. Font sizes remain unchanged.
- It reports glyph outlines that may be clipped separately from artwork cells that become clipped or hidden. The glyph count covers the prepared repertoire of each used font.
- For mixed documents, the canvas and native artwork remain unchanged; resizing cells can change which textmode cells are visible.
- Click **Regrid** to apply.

> [!NOTE]
> Hidden cells remain in the layer and can be brought back into view by changing the canvas or grid. Review clipping warnings before confirming.

---

## 4. Canvas Size Interception

If you invoke Aseprite's native **Sprite > Canvas Size** while working on a textmode document, Asemode intercepts the command to prevent accidental grid misalignment:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/confirm-canvas-size-warnings.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/confirm-canvas-size-warnings.png">
  <img alt="Confirm canvas size dialog with warnings about cell clipping from canvas resize." src="../images/screenshots/dark/confirm-canvas-size-warnings.png" width="500">
</picture>

- Dimensions are validated to ensure they are exact multiples of the active cell dimensions.
- If the proposed resize would crop active cells, an off-grid content warning is displayed before applying.

---

[← Previous: Fonts & Typography System](03-fonts-and-typography.md) • [User Guide Home](README.md) • [Next: Portable Interchange & Ecosystem Integration →](05-portable-interchange.md)
