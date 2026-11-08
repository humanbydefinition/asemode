# Asemode Documentation

This directory contains user documentation and screenshot assets.

## Contents

| Path | Purpose |
| :--- | :--- |
| [`USER_GUIDE.md`](USER_GUIDE.md) | User guide for Asemode features. The guide is a work in progress. |
| [`SCREENSHOTS.md`](SCREENSHOTS.md) | Gallery of Asemode dialogs in Aseprite's default light and dark themes. |
| [`images/screenshots/`](images/screenshots/) | Generated screenshots used by the gallery. |
| [`images/readme-header.png`](images/readme-header.png) | Header image used by the project README. |

Font license files are stored in [`assets/fonts/licenses/`](../assets/fonts/licenses/). See [Third-Party Notices](../THIRD_PARTY_NOTICES.md) for attribution and licensing information.

## Update Screenshots

Run the screenshot generator from the repository root on macOS with an active, unlocked graphical desktop session:

```sh
ASEPRITE_PATH=/path/to/aseprite npm run docs:screenshots
```

The command captures the dialogs in both themes using isolated Aseprite profiles, validates the captures, and updates `images/screenshots/` and `SCREENSHOTS.md`. `ASEPRITE_PATH` may point to the executable or its `bin` directory. See the [screenshots scripts guide](../scripts/screenshots/README.md) for prerequisites and workflow details.

For the development setup, test commands, and manual UI checks, see the [Contributing Guide](../CONTRIBUTING.md) and [development scripts guide](../scripts/README.md).
