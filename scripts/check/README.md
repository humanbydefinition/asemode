# Check and Test Scripts

This directory contains automated scripts that validate Lua code quality, test font generation, verify portable document compatibility, and inspect package archives.

Run all commands from the repository root after installing dependencies with `npm ci`.

## Scripts Overview

| Script | Command | Purpose |
| :--- | :--- | :--- |
| `lint-lua.mjs` | `mise exec -- npm run lint:lua` | Run Lua Language Server diagnostics against `.luarc.ci.json`. Logs are written to `.test-output/luals/`. |
| `test-lua.mjs` | `npm run test:lua` | Execute the pure Lua unit test suite (`tests/pure/run.lua`) under Lua 5.4.6. |
| `test-portable.mjs` | `npm run test:portable` | Validate Lua portable document decoding against the `@textmode/document` reference library using fixtures and mutation cases. |
| `test-font-resources.mjs` | `npm run test:fonts` | Test font table generation and parser logic using temporary test fixtures. |
| `test-font-identities.mjs` | `npm run test:font-identities` | Verify cryptographic and metric identities of default fonts against committed fixtures. Outputs `.test-output/font-identities.json`. |
| `check-package.mjs` | `npm run test:package` | Validate package structure, manifest entries, bundled fonts, and SHA-256 checksums in `dist/`. |
| `extension-archive.mjs` | *Module* | Shared utility for reading and validating `.aseprite-extension` archives. Used by `check-package.mjs` and tooling tests. |

## Detailed Checks

### 1. Lua Quality and Diagnostics (`lint-lua.mjs`)

Static analysis uses the pinned Lua Language Server configured by `.luarc.ci.json`:

```sh
mise exec -- npm run lint:lua
```

- Uses the Aseprite API definitions and checks error-level diagnostics, including incomplete annotated signatures and invalid documented parameter names.
- Directs diagnostic logs to `.test-output/luals/`.
- Fails the build on diagnostics at error severity. It does not require every function to have annotations, and warnings do not fail this command.

### 2. Pure Lua Unit Tests (`test-lua.mjs`)

The pure Lua test suite verifies business logic without running an Aseprite UI instance:

```sh
npm run test:lua
```

- Exercises core math, cell geometry, font metrics, TrueType decoding, document models, and stamp operations.
- Requires Lua 5.4.6. If `lua` is not in your `PATH`, set `LUA_BIN` to your executable path.

### 3. Portable Document Parity (`test-portable.mjs`)

Asemode exchanges artwork with web tools across the `textmode.art` ecosystem using `.textmode.json` files:

```sh
npm run test:portable
```

- Compares Asemode's Lua portable document reader against `@textmode/document` (v4.0.0).
- Tests valid document fixtures, layer order, color conversions, transforms, and negative edge cases.
- Validates that invalid documents and schema violations are rejected cleanly.

### 4. Font Verification (`test-font-resources.mjs` & `test-font-identities.mjs`)

Ensure font tables are reproducible and structurally correct:

```sh
# Test generator logic with temporary fixtures
npm run test:fonts

# Verify font hashes and metrics against committed baselines
npm run test:font-identities
```

- `test-font-resources.mjs` exercises the generator with synthetic and edge-case fonts.
- `test-font-identities.mjs` verifies that bundled font files have not mutated unexpectedly. Results are written to `.test-output/font-identities.json`.

### 5. Package Archive Verification (`check-package.mjs`)

Before releasing, verify that the built `.aseprite-extension` archive in `dist/` is structurally sound:

```sh
# Build the package first
npm run build

# Validate the package archive
npm run test:package

# For releases, verify all 18 fonts are packaged
npm run test:package -- --release
```

- Validates that `package.json` contains valid extension metadata.
- Confirms `src/main.lua` exists at the expected archive entry point.
- Checks that all required runtime files, fonts, and notices are present.
- Verifies the integrity of the generated SHA-256 checksum file.

## Environment Variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `LUA_BIN` | `lua` | Path to the Lua 5.4 executable used by `test-lua.mjs`. |
| `LUA_LANGUAGE_SERVER` | Managed by `mise` | Path to the `lua-language-server` binary for `lint-lua.mjs` and tooling tests. |

See the parent [scripts guide](../README.md) for full commands and test suite execution.
