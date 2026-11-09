# Canvas, Grids & Regridding

[← Previous: Fonts & Typography System](03-fonts-and-typography.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Portable Interchange & Ecosystem Integration →](05-portable-interchange.md)

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

### Tab 1: Cell Size
Adjust the pixel width and height of each character cell:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/grid.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/grid.png">
  <img alt="Grid dialog Cell Size tab showing width and height inputs for individual character cells." src="../images/screenshots/dark/grid.png" width="500">
</picture>

- Scales overall canvas pixel dimensions while preserving the total number of character columns and rows.
- Useful when migrating artwork to a font with a different aspect ratio (e.g. from 8×8 square to 8×16 tall).

### Tab 2: Grid Size
Expand or contract the number of character columns and rows:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/grid-size.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/grid-size.png">
  <img alt="Grid dialog Grid Size tab showing columns and rows inputs alongside anchor point controls." src="../images/screenshots/dark/grid-size.png" width="500">
</picture>

- **Columns & Rows:** Set new grid boundaries (e.g., expand from 40 to 80 columns).
- **Anchor Positioning:** Choose which corner or center point to anchor existing artwork during expansion or cropping.

---

## 3. Regrid Confirmation & Content Protection

When you apply changes, Asemode evaluates all textmode layers across every animation cel:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/confirm-regrid-warnings.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/confirm-regrid-warnings.png">
  <img alt="Confirm regrid dialog displaying yellow warning banner about truncated cells and content impact." src="../images/screenshots/dark/confirm-regrid-warnings.png" width="500">
</picture>

- If expanding the canvas, the dialog summarizes new dimensions and applies changes cleanly.
- If contracting the canvas, a yellow warning banner alerts you to any cells that will be cropped, identifying affected layers and cell counts.

> [!CAUTION]
> Truncated cells outside new boundaries cannot be recovered once saved. Always review content warnings before confirming.

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

[← Previous: Fonts & Typography System](03-fonts-and-typography.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Portable Interchange & Ecosystem Integration →](05-portable-interchange.md)
