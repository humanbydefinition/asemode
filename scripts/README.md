# Development Scripts

This directory contains automation scripts for building, testing, checking, and documenting Asemode.

Run all commands from the repository root after installing dependencies with `npm ci`. For Lua checks and language server diagnostics, install Lua 5.4.6 and run `mise install`. See the [Contributing Guide](../CONTRIBUTING.md) for environment configuration details.

## Directories

- [**`build/`**](build/README.md): Generate Lua font resources, compile Unicode name tables, package the extension archive, and deploy to itch.io.
- [**`check/`**](check/README.md): Run Lua Language Server diagnostics, pure Lua unit tests, portable document parity tests, and package validation checks.
- [**`screenshots/`**](screenshots/README.md): Capture automated dialog screenshots in light and dark themes using an isolated Aseprite instance.

## Command Reference

| Command | Purpose and Effects |
| :--- | :--- |
| `mise exec -- npm test` | Run the full test suite: formatting and JSDoc checks, Lua diagnostics, portable document parity, font checks, package build, package verification, and tooling tests. |
| `npm run build` | Generate Lua font and Unicode resources, update `src/core/version.lua`, and write the `.aseprite-extension` archive and checksum to `dist/`. |
| `npm run check:jsdoc` | Check JSDoc on named functions and reusable function variables in scripts and Node.js tests. |
| `npm run format` | Format JavaScript, JSON, and configuration files with Prettier. |
| `npm run format:check` | Verify JavaScript, JSON, and configuration formatting without modifying files. |
| `npm run format:lua` | Format all Lua source and test files with StyLua. |
| `npm run format:lua:check` | Verify Lua formatting without modifying files. |
| `mise exec -- npm run check:lua` | Check Lua code formatting, run Lua Language Server diagnostics, and execute the pure Lua test suite. Writes logs to `.test-output/luals/`. |
| `npm run fonts:generate` | Generate Lua font data tables from `assets/fonts/registry.json` and default font files. |
| `npm run fonts:check` | Verify generated font tables match `assets/fonts/registry.json` without rewriting them. |
| `npm run unicode:check` | Verify generated Unicode plane tables match `unicode-name` without rewriting them. |
| `npm run test:portable` | Compare Lua portable document decoding with `@textmode/document` using test fixtures and mutation cases. |
| `npm run test:fonts` | Test font resource generation with temporary fixtures. |
| `npm run test:font-identities` | Verify bundled font identities against committed fixtures. Writes results to `.test-output/font-identities.json`. |
| `npm run test:package` | Validate the built extension archive, manifest, and checksum in `dist/`. Run `npm run build` first. |
| `mise exec -- npm run test:tooling` | Test archive utilities and LuaLS diagnostic gates using temporary files. |
| `ASEPRITE_PATH=... npm run docs:screenshots` | Capture documentation screenshots of all dialogs in light and dark themes. Generates `docs/SCREENSHOTS.md`. |

## Environment Variables

Configure these environment variables to customize script behavior:

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `ASEPRITE_PATH` | `/Applications/Aseprite.app/Contents/MacOS/aseprite` | Path to the Aseprite executable or its `bin` directory. Used by `docs:screenshots`. |
| `ITCH_TARGET` | None (`local-dry-run/...` in dry-run) | itch.io target specification in `username/project:channel` format for Butler deployment. |
| `LUA_BIN` | `lua` (from `PATH`) | Path to the Lua 5.4 executable used by test runners when not using `mise`. |
| `LUA_LANGUAGE_SERVER` | Discovered via `mise` | Absolute path to the `lua-language-server` executable. Used by `lint:lua` and tooling tests. |

## Documentation Screenshots

On macOS, you can regenerate the full screenshot gallery in an active graphical desktop session:

```sh
ASEPRITE_PATH=/path/to/aseprite npm run docs:screenshots
```

This command runs Aseprite in an isolated temporary profile, captures every Asemode dialog in light and dark themes, validates the output PNG files, and updates `docs/SCREENSHOTS.md`. See the [Screenshots Guide](screenshots/README.md) for complete details.

## Release Deployment

On a release from `main`, CI updates the version, checks a package with the
default fonts, and creates a draft GitHub release. A maintainer builds and
publishes the full package locally:

1. Check out the release tag and install dependencies with `npm ci`. Place all
   seven optional fonts in `assets/fonts/` as described in the [font assets guide](../assets/fonts/README.md#build-with-optional-fonts).
2. Run `npm run build` and `npm run test:package -- --release`. This creates
   `dist/asemode-<version>.aseprite-extension` and its `.sha256` file and checks
   that the archive includes all 18 fonts.
3. Upload both files to the matching draft with `gh release upload <tag> dist/asemode-<version>.aseprite-extension dist/asemode-<version>.aseprite-extension.sha256`.
   Review the draft and publish it with `gh release edit <tag> --draft=false`.
4. Publish to itch.io with Butler using the commands below. Replace `<tag>` and
   `<version>` with the release tag and version, such as `v1.0.0` and `1.0.0`.

The project provides Butler deployment commands for publishing to itch.io:

```sh
export ITCH_TARGET="humanbydefinition/asemode:aseprite-extension"
npm run itch:dry-run   # Test packaging and Butler upload locally
npm run itch:preview   # Push changes to preview channel
npm run itch:publish   # Publish release archive if changed
npm run itch:status    # Inspect remote channel status
```

> [!NOTE]
> Publishing commands build the archive and verify that it contains all 18 fonts.
