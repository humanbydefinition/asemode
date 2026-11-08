# Build Scripts

This directory contains scripts that compile static resources, generate Lua data tables, and assemble the `.aseprite-extension` release package.

Run all commands from the repository root after installing dependencies with `npm ci`.

## Scripts Overview

| Script | Command | Purpose |
| :--- | :--- | :--- |
| `font-verification.mjs` | *Module* | Load the font registry and verify portable identities and optional source hashes for build and identity checks. |
| `generate-font-resources.mjs` | `npm run fonts:generate`<br>`npm run fonts:check` | Generate Lua font data tables and metadata from `assets/fonts/registry.json`. With `--check`, verify tables are up to date. |
| `generate-unicode-names.mjs` | `node scripts/build/generate-unicode-names.mjs`<br>`npm run unicode:check` | Generate Unicode name planes and label ranges from `unicode-name`. With `--check`, verify tables are up to date. |
| `package.mjs` | `npm run build` | Update `src/core/version.lua` from `package.json`, bundle extension files into `dist/`, and calculate a SHA-256 checksum file. |
| `itch.mjs` | `npm run itch:dry-run`<br>`npm run itch:publish` | Validate and push the built release archive to itch.io using the Butler CLI. |

## Detailed Workflow

### 1. Font Resource Generation (`generate-font-resources.mjs`)

Asemode embeds TrueType font bytes in generated Lua modules so bundled fonts do not require filesystem reads during drawing.

```sh
# Generate Lua font data and catalog metadata
npm run fonts:generate

# Verify committed font tables match registry without writing
npm run fonts:check
```

- Reads font definitions from `assets/fonts/registry.json` and TrueType binaries from `assets/fonts/`.
- Checks each font identity against the committed fixture.
- Writes byte modules in `src/fonts/data/`, resource metadata in `src/fonts/resources.lua`, and the catalog in `src/fonts/bundled.lua`.
- Automatically removes obsolete or stale generated font files.

### 2. Unicode Data Generation (`generate-unicode-names.mjs`)

Asemode enables searching for glyphs by Unicode name or block range:

```sh
# Generate Unicode plane data in src/unicode/names/
node scripts/build/generate-unicode-names.mjs

# Verify generated Unicode data without writing
npm run unicode:check
```

- Parses character names and code points from the `unicode-name` package.
- Generates plane tables in `src/unicode/names/` and label ranges in `src/unicode/name-label-ranges.lua`.

### 3. Packaging (`package.mjs`)

The packager builds the final `.aseprite-extension` ZIP archive:

```sh
# Build with default fonts or the complete optional set
npm run build
```

- Reads the package version from `package.json` and updates `src/core/version.lua`.
- Validates required files, including `package.json`, `src/main.lua`, and third-party notices.
- Cleans old extension packages and checksum files from `dist/`.
- Packages the extension into `dist/asemode-<version>.aseprite-extension`.
- Computes and writes `dist/asemode-<version>.aseprite-extension.sha256`.

#### Font Bundling Policy

- With no optional fonts present, `npm run build` packages the 11 default fonts committed in `assets/fonts/`.
- If any optional font is present, the build requires all seven optional fonts and validates their identities before packaging all 18. It generates the additional resources in a temporary directory without changing tracked files.
- Maintainers verify the full package locally with `npm run test:package -- --release`; a default-only package cannot pass that check.

### 4. itch.io Deployment (`itch.mjs`)

The project uses [Butler](https://itch.io/docs/butler/) to publish releases to itch.io:

```sh
export ITCH_TARGET="humanbydefinition/asemode:aseprite-extension"

# Run a local dry-run without uploading
npm run itch:dry-run

# Push to a hidden preview channel
npm run itch:preview

# Push the initial build to a hidden channel
npm run itch:publish:first

# Publish to the live channel if the archive has changed
npm run itch:publish

# Check current channel and build status
npm run itch:status
```

> [!NOTE]
> `ITCH_TARGET` must use the format `username/project:channel` (for example, `humanbydefinition/asemode:aseprite-extension`).

See the parent [scripts guide](../README.md) for the complete list of development commands.
