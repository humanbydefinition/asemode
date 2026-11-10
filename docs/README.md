# Asemode Documentation

This directory contains user documentation, guides, and screenshot assets.

## Contents

| Path | Purpose |
| :--- | :--- |
| [`guide/`](guide/) | User guide portal, pathways, and architecture overview, plus modular chapters (00-08) covering tutorials, workflows, typography, grids, JSON interop, safety guards, settings, and quick reference. |
| [`SCREENSHOTS.md`](SCREENSHOTS.md) | Complete gallery of Asemode dialogs in Aseprite's default light and dark themes. |
| [`images/`](images/) | Header image used by the project README and guide hub, plus generated screenshots used across the guide and gallery. |

Font license files are stored in [`assets/fonts/licenses/`](../assets/fonts/licenses/). See [Third-Party Notices](../THIRD_PARTY_NOTICES.md) for attribution and licensing information.

## User Guide Modules

- [Chapter 00: Getting Started](guide/00-getting-started.md)
- [Chapter 01: The Asemode Panel & Drawing Workflow](guide/01-panel-and-drawing.md)
- [Chapter 02: Multi-Layer Architecture & Composition](guide/02-layers-and-composition.md)
- [Chapter 03: Fonts & Typography System](guide/03-fonts-and-typography.md)
- [Chapter 04: Canvas, Grids & Regridding](guide/04-canvas-and-grids.md)
- [Chapter 05: Portable Interchange & Ecosystem Integration](guide/05-portable-interchange.md)
- [Chapter 06: Native Operation Guards & Document Integrity](guide/06-native-guards-and-safety.md)
- [Chapter 07: Settings, Customization & Shortcuts](guide/07-settings-and-shortcuts.md)
- [Chapter 08: Quick Reference & Command Palette](guide/08-quick-reference.md)

## Update Screenshots

Run the screenshot generator from the repository root on macOS with an active, unlocked graphical desktop session:

```sh
ASEPRITE_PATH=/path/to/aseprite npm run docs:screenshots
```

The command captures the dialogs in both themes using isolated Aseprite profiles, validates the captures, and updates `images/screenshots/` and `SCREENSHOTS.md`. `ASEPRITE_PATH` may point to the executable or its `bin` directory. See the [screenshots scripts guide](../scripts/screenshots/README.md) for prerequisites and workflow details.

For the development setup, test commands, and manual UI checks, see the [Contributing Guide](../CONTRIBUTING.md) and [development scripts guide](../scripts/README.md).
