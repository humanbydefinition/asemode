# The Asemode Panel & Drawing Workflow

[← Previous: Getting Started](00-getting-started.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Multi-Layer Architecture & Composition →](02-layers-and-composition.md)

---

The **Asemode Panel** is your command center for textmode drawing. It connects Aseprite's native drawing tools with character cells, allowing you to paint glyphs, swap ink/cell colors, transform stamps, and browse Unicode characters seamlessly.

Toggle the panel at any time via **Sprite > Asemode > Open/Close Asemode Panel** (Command: `AsemodePanel`).

---

## 1. Anatomy of the Panel

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/asemode.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/asemode.png">
  <img alt="The Asemode main dockable panel showing active primary and secondary stamps, color selectors, stamp transform icons, and the glyph grid." src="../images/screenshots/dark/asemode.png" width="560">
</picture>

1. **Stamp Preview & Orientation:** Displays active **Primary** (left-click) and **Secondary** (right-click) stamps along with flip/rotation indicators.
2. **Color Wells:** Two synchronized color selectors:
   - **Ink Color:** Foreground color rendering the glyph strokes.
   - **Cell Color:** Background color filling the rectangular cell behind the glyph.
3. **Stamp Transform Controls:** Quick-action buttons to swap colors, flip stamps horizontally/vertically, and rotate 90° clockwise or counter-clockwise.
4. **Interactive Glyph Browser:** Searchable character grid with Unicode block filtering.

---

## 2. Drawing with Native Aseprite Tools

- **Pencil (`B`):** Left-click paints the **Primary Stamp**; right-click paints the **Secondary Stamp**.
- **Paint Bucket (`G`):** Fills contiguous cells sharing matching glyphs or colors.
- **Line & Shapes (`L`, `U`):** Draws straight borders, hollow boxes, or filled areas using the active stamp.
- **Selection (`M`, Lasso):** Selects cell regions for copying, pasting, or search-and-replace.

> [!TIP]
> Turn on Aseprite's grid (**View > Show > Grid**) to see character boundaries as you paint.

---

## 3. The Dual Stamp & Color System

```text
┌─────────────────────────┐
│ Cell Background Color   │
│   ┌─────────────────┐   │
│   │  Ink Glyph (█)  │   │
│   │                 │   │
│   └─────────────────┘   │
└─────────────────────────┘
```

- **Primary Stamp:** Bound to your primary brush action (left mouse button).
- **Secondary Stamp:** Bound to your secondary brush action (right mouse button)—ideal for shadow fills, solid blocks, or background clears.
- **Ink Color:** Synchronizes with Aseprite's palette **Foreground Color**.
- **Cell Color:** Synchronizes with Aseprite's palette **Background Color**.
- **Transparent Cells:** Set Cell Color opacity to `0` to let underlying pixel art or backdrop layers show through cleanly.

---

## 4. Stamp Orientation Transforms

Manipulate stamps using the panel buttons or menu commands under **Sprite > Asemode > Stamps**:

| Action | Command Identifier | Description |
| :--- | :--- | :--- |
| **Swap Colors** | `AsemodeSwapColors` | Inverts foreground and background colors. |
| **Flip Horizontal** | `AsemodeFlipHorizontal` | Mirrors glyph across the vertical axis. |
| **Flip Vertical** | `AsemodeFlipVertical` | Inverts glyph across the horizontal axis. |
| **Rotate 90° CW** | `AsemodeRotateClockwise` | Rotates the stamp 90° clockwise. |
| **Rotate 90° CCW** | `AsemodeRotateCounterclockwise` | Rotates the stamp 90° counter-clockwise. |
| **Reset Orientation**| `AsemodeResetOrientation` | Clears all rotation and flip states. |

> [!NOTE]
> All transform actions can target the **Primary Stamp**, **Secondary Stamp**, or **Both Stamps** via their respective submenus.

---

## 5. The Glyph Browser & Unicode Navigation

1. **Selecting Glyphs:** Left-click any grid cell to set the **Primary Stamp**; right-click to set the **Secondary Stamp**.
2. **Filtering by Unicode Block:** Use the category dropdown to jump between standard blocks:
   - *Basic Latin (ASCII)*
   - *Latin-1 Supplement*
   - *Box Drawing* (single, double, and rounded borders)
   - *Block Elements* (shading tiles, half-blocks, quadrant blocks)
   - *Geometric Shapes & Arrows*
3. **Searching:** Type names or codes (e.g., `heart`, `arrow`, `box`, `U+2588`) to filter instantly.

---

## 6. Panel Status Banners

When document state requires user attention, the panel displays a contextual notification banner:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/asemode-panel-locked.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/asemode-panel-locked.png">
  <img alt="Asemode panel showing yellow status banner indicating that the active layer is locked and cannot be edited." src="../images/screenshots/dark/asemode-panel-locked.png" width="560">
</picture>

| Status Banner | Cause | Recommended Action |
| :--- | :--- | :--- |
| **Locked Layer** | Active layer is locked in the timeline. | Click the padlock icon in the timeline to unlock. |
| **Layer Unavailable** | Active layer is an ordinary raster layer. | Select a Textmode layer or choose `Add Textmode Layer..`. |
| **Missing Stamp** | Stamp character is missing in the active font. | Click any character in the glyph grid to recreate the stamp. |
| **Unsupported Version** | Project metadata requires a newer Asemode build. | Update Asemode to restore full editing support. |

---

[← Previous: Getting Started](00-getting-started.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Multi-Layer Architecture & Composition →](02-layers-and-composition.md)
