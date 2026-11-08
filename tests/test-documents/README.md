# Textmode Import Test Documents

This directory contains Textmode JSON documents for testing Asemode's import workflow. The files cover warnings, recovery options, and errors. Some contain deliberately invalid data and must not be treated as valid portable documents.

Open these documents manually in Aseprite to inspect the import dialogs and resulting sprites. The pure Lua tests also use the invalid-font example to check decoder recovery.

## Prerequisites

- **Aseprite**: Install a version supported by Asemode and enable the extension. See the [Contributing Guide](../../CONTRIBUTING.md#manual-testing-in-aseprite) for the build and installation steps.
- **Fonts**: The examples below assume the bundled ATASCII font. Other fonts can produce additional missing-character or clipping warnings.

## Manual Testing

1. Open **Asemode > Import Textmode JSON..** in Aseprite.
2. Select a file from `tests/test-documents/` and click **Read document**.
3. If the document is accepted, choose **New sprite**, ATASCII at size 8, and an 8 × 8 cell size in **Import Textmode Layers**, unless the case below specifies otherwise. If a source font is unavailable, choose the default font or a font override. An invalid font ID requires an explicit override for each affected source layer.
4. If the document has more than two source entries, use the page controls to review their selections and font overrides. Your choices remain set when you change pages.
5. Click **Prepare import..**. Check the review warnings, then click **Import** to inspect the resulting sprite. Errors detected during reading appear before the options panel opens.

The review shows applicable warnings once per import. Warning codes below identify the corresponding diagnostics in the automated tests; they are not necessarily displayed in the dialog.

## Frames and Layers

| File | Purpose and expected result |
| :--- | :--- |
| [`many-frames-and-layers.textmode.json`](many-frames-and-layers.textmode.json) | Exercises an import with 24 frames and 12 layers per frame. Choose a new sprite with 8 × 8 cells. The review should show 24 frames, 12 layers, and an 8 × 4 grid; the resulting canvas is 64 × 32 pixels. Each 100 ms frame changes the visible letters, and each layer contributes one colored character. |

## Warning and Recovery Cases

| File | Purpose and expected result |
| :--- | :--- |
| [`arbitrary-cell-rotations.textmode.json`](arbitrary-cell-rotations.textmode.json) | Exercises `CELL_ROTATION_ROUNDED`. Eight angles are rounded to quarter turns, while horizontal and vertical flips remain applied. See [Rotation Mapping](#rotation-mapping). |
| [`combined-warnings.textmode.json`](combined-warnings.textmode.json) | Combines seven warnings in a valid two-frame document: different cell metrics, layer presentation, opacity, layer name, missing glyph, cell rotation, and a blend-mode change. Choose 8 × 8 cells to see all seven. Import creates two Aseprite layers. |
| [`presentation-warnings.textmode.json`](presentation-warnings.textmode.json) | With an 8 × 8 destination cell size, reports `CELL_METRICS_CHANGED`, `LAYER_PRESENTATION_DISCARDED`, `OPACITY_QUANTIZED`, and `LAYER_LABEL_CHANGED`. The source uses 9 × 8 cells, a layer offset and rotation, opacity 0.5, and a control character in its layer name. If the cell size remains 9 × 8, the cell-size warning does not appear. |
| [`missing-glyph.textmode.json`](missing-glyph.textmode.json) | Reports `MISSING_GLYPHS_AS_SPACES` for U+10FFFF with ATASCII. The cell appears as a space, but its Unicode value is retained in the imported data. |
| [`layer-variants.textmode.json`](layer-variants.textmode.json) | Reports `LAYER_VARIANTS`: the same source layer uses Normal blending in frame 1 and Multiply in frame 2. Import creates separate Aseprite layers for the two variants. |
| [`hidden-import-cells.textmode.json`](hidden-import-cells.textmode.json) | Exercises `HIDDEN_IMPORTED_CELLS` when the destination canvas is too small. See [Hidden Cells](#hidden-cells). |
| [`unknown-font.textmode.json`](unknown-font.textmode.json) | Uses a fabricated, well-formed font identity. Choose an available font for the full 64 × 64 artwork. The result can also report missing characters. |
| [`two-layers-known-font.textmode.json`](two-layers-known-font.textmode.json) | Contains two layers with the artwork's font identity. If the exact font is unavailable, choose substitutes. |
| [`two-layers-mixed-fonts.textmode.json`](two-layers-mixed-fonts.textmode.json) | Contains two layers with different font identities, including a fabricated one. Choose substitutes for any unavailable fonts. |
| [`invalid-font-id.textmode.json`](invalid-font-id.textmode.json) | Uses a malformed string font ID. The importer lets you explicitly choose a font for the affected layer; the strict portable decoder rejects the ID. |

### Other Warnings and Limits

- **Font clipping**: Choose a cell size smaller than the glyphs, such as 1 × 1 with ATASCII at size 8. The review offers a font preview and requires clipping confirmation before import.
- **Stale destination**: Prepare an import into an existing sprite. Change its destination, frame, canvas, or insertion layer before confirming the review. The import must be prepared again if the captured destination is no longer valid.
- **Resource and size limits**: These depend on the selected font, cell dimensions, and destination. This directory does not include very large test files.

Font identities describe specific font bytes. A valid identity does not guarantee that the font is installed or contains every character. IDs made of zeroes are fabricated and do not refer to bundled fonts.

## Error Cases

These documents should show an error after **Read document**, before the options panel:

| File | Expected error |
| :--- | :--- |
| [`invalid-cell-coordinate.textmode.json`](invalid-cell-coordinate.textmode.json) | `INVALID_DOCUMENT`: a cell coordinate does not match its grid position. |
| [`invalid-cell-color.textmode.json`](invalid-cell-color.textmode.json) | `INVALID_DOCUMENT`: a color component is outside 0–255. |
| [`unsupported-cell-encoding.textmode.json`](unsupported-cell-encoding.textmode.json) | `UNSUPPORTED_ENCODING`: the cell encoding is not supported. |
| [`unsupported-version.textmode.json`](unsupported-version.textmode.json) | `UNSUPPORTED_VERSION`: version 3 is not supported. |
| [`invalid-cell-inversion.textmode.json`](invalid-cell-inversion.textmode.json) | `UNSUPPORTED_CELL_TRANSFORM`: cell inversion cannot be preserved. |
| [`invalid-multi-scalar-glyph.textmode.json`](invalid-multi-scalar-glyph.textmode.json) | `UNSUPPORTED_GLYPH_STRING`: the cell character contains two Unicode scalars. |
| [`invalid-frame-duration.textmode.json`](invalid-frame-duration.textmode.json) | `INVALID_DURATION`: Aseprite requires at least 1 ms per frame. |
| [`unsupported-blend-mode.textmode.json`](unsupported-blend-mode.textmode.json) | `UNSUPPORTED_BLEND_MODE`: the layer blend mode is not supported. |

## Automated Checks

Run `npm run test:portable` for codec compatibility with `@textmode/document`. It uses the separate portable and browser fixtures rather than running these manual import cases. The pure Lua suite also checks font ID recovery without launching Aseprite. See the [check scripts guide](../../scripts/check/README.md) for the complete test reference.
