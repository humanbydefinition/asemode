# Font Assets

This directory contains the TrueType font files and registry used to build Asemode's bundled font resources. For the Lua font implementation, see [`src/fonts/`](../../src/fonts/).

## Registry and Distribution

[`registry.json`](registry.json) defines each font's ID, display name, file name, author, source URL, and distribution category. It is the source for the generated bundled catalog.

- **Default fonts**: Eleven font files are committed to the repository and are available in standard builds.
- **Optional fonts**: Seven font files are supplied locally and are ignored by Git. Official release builds require all seven. The registry records the expected SHA-256 of each optional source file.

The [`licenses/`](licenses/) directory contains license files supplied with selected fonts. See [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) for font sources and license terms. Each font has its own terms; the Asemode code license does not replace them.

## Generate and Verify Resources

Run commands from the repository root after installing dependencies with `npm ci`:

```sh
# Generate the default bundled catalog and Lua byte resources
npm run fonts:generate

# Verify generated default resources without changing files
npm run fonts:check

# Verify font identities and generator behavior
npm run test:font-identities
npm run test:fonts
```

The generator reads the registry and font files, checks their portable identities against [`tests/fixtures/font-identities.json`](../../tests/fixtures/font-identities.json), and writes [`src/fonts/bundled.lua`](../../src/fonts/bundled.lua), [`src/fonts/resources.lua`](../../src/fonts/resources.lua), and byte modules under [`src/fonts/data/`](../../src/fonts/data/). Do not edit the generated files directly. Generation also removes obsolete files from the generated data directory.

## Build with Optional Fonts

Obtain the optional fonts from their registered sources and place the exact files named in `registry.json` in this directory. The files remain untracked. The build verifies their portable identities and SHA-256 hashes before packaging:

```sh
npm run build
```

A standard `npm run build` uses the default fonts when no optional fonts are present. If any optional font is present, the build requires the complete optional set and packages all 18 fonts. See the [build scripts guide](../../scripts/build/README.md) and [Contributing Guide](../../CONTRIBUTING.md) for the full build and development workflows.
