# Portable Interchange & Ecosystem Integration

[← Previous: Canvas, Grids & Regridding](04-canvas-and-grids.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Native Operation Guards & Document Integrity →](06-native-guards-and-safety.md)

---

Asemode is designed as an open creative hub within the **`textmode.art`** ecosystem. By supporting the standard **Textmode Document v4** (`.textmode.json`) format, you can exchange live, editable character-cell artwork between Aseprite and web tools, animation libraries, and external converters.

---

## 1. The Textmode Document v4 Specification

The [Textmode Document format](https://github.com/humanbydefinition/textmode-document) is a platform-independent JSON schema representing multi-layer textmode art:

- **Metadata:** Author credits, canvas dimensions (columns and rows), and schema version.
- **Font Descriptors:** Font identity hashes, families, and glyph bounding boxes.
- **Layer Stacks:** Layer names, opacity, visibility, and per-frame cell matrices.
- **Cell Records:** Unicode code points, 32-bit RGBA ink (foreground) colors, and 32-bit RGBA cell (background) colors.

---

## 2. Exporting Artwork to JSON

1. Choose **Sprite > Asemode > Export..** (Command: `AsemodeExport`).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/export.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/export.png">
  <img alt="Export Textmode Document dialog showing target file selector, layer selection list, and author fields." src="../images/screenshots/dark/export.png" width="500">
</picture>

2. Select the destination file path and choose which textmode layers to include.
3. Review the export summary dialog:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/review-export-warnings.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/review-export-warnings.png">
  <img alt="Review Textmode Export dialog with warnings detailing excluded raster layers and out-of-bounds cells." src="../images/screenshots/dark/review-export-warnings.png" width="520">
</picture>

- Confirms total layer count, cell dimensions, and file destination.
- Highlights any non-textmode raster layers excluded from the export or cells extending beyond bounds.
4. Click **Export** to write the `.textmode.json` file.

---

## 3. Importing JSON Artwork

1. Choose **Sprite > Asemode > Import Textmode JSON..** (Command: `AsemodeImport`).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/import-json.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/import-json.png">
  <img alt="Import Textmode JSON file selection dialog." src="../images/screenshots/dark/import-json.png" width="500">
</picture>

2. Select your `.textmode.json` file. Asemode reads the document and matches fonts asynchronously.
3. In the **Import Textmode Layers** dialog, select the layers you wish to import:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/import-layers-paginated-recovery.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/import-layers-paginated-recovery.png">
  <img alt="Import Textmode Layers dialog with font recovery controls for replacing missing document fonts with local substitutes." src="../images/screenshots/dark/import-layers-paginated-recovery.png" width="520">
</picture>

- **Font Recovery:** If an imported document references a font not installed locally, use the dropdown to assign a local substitute.
- **Pagination:** Multi-layer documents are paginated for easy review.
4. Confirm layer import in the **Review Import** dialog:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/review-import-warnings.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/review-import-warnings.png">
  <img alt="Review Textmode Import dialog showing yellow diagnostic warning box regarding font substitutions and bounds." src="../images/screenshots/dark/review-import-warnings.png" width="520">
</picture>

---

## 4. Troubleshooting Import Issues

If an imported file predates schema version 4, contains invalid syntax, or lacks filesystem permissions, Asemode displays a diagnostic resolution modal:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/screenshots/dark/import-needs-changes.png">
  <source media="(prefers-color-scheme: light)" srcset="../images/screenshots/light/import-needs-changes.png">
  <img alt="Import needs changes dialog explaining schema validation issues and recommending fixes." src="../images/screenshots/dark/import-needs-changes.png" width="520">
</picture>

- **Schema Issues:** Ensure the document was exported using Textmode Document v4 or updated via [`textmode.art`](https://textmode.art).
- **File Permissions:** If access is denied by OS sandboxing, move the file into a standard folder (e.g. Documents) and grant file access when prompted by Aseprite.

---

## 5. Ecosystem Recipes

- **[create.textmode.art](https://create.textmode.art/):** Export a `.textmode.json` from the web canvas and open it in Aseprite to add detailed pixel art layers, shading, and multi-frame animation.
- **[export.textmode.art](https://export.textmode.art/):** Convert photos, pixel art, or video frames into textmode representations, download the `.textmode.json`, and import directly into Aseprite.
- **[textmode.js](https://github.com/humanbydefinition/textmode.js):** Use [textmode.export.js](https://github.com/humanbydefinition/textmode.export.js) in your JavaScript sketches to export animated text cels for editing in Aseprite.
- **[Textmode Overlay](https://extension.textmode.art/):** Capture browser textmode sessions and inspect them directly in Aseprite.

---

[← Previous: Canvas, Grids & Regridding](04-canvas-and-grids.md) • [User Guide Home](../USER_GUIDE.md) • [Next: Native Operation Guards & Document Integrity →](06-native-guards-and-safety.md)
