# Contributing to Asemode

Thank you for contributing to Asemode. We welcome code contributions, bug reports, documentation updates, examples, and feature ideas.

## Prerequisites

Asemode is an Aseprite extension written in Lua. Development, resource generation, and testing require:

- **Node.js**: v24 or later (see [`.nvmrc`](.nvmrc))
- **npm**: v11 or later
- **Lua**: 5.4.6
- **Lua Language Server**: 3.19.2 (managed via [`mise`](https://mise.jdx.dev/))
- **Aseprite**: 1.3.18.6 or later (for manual testing)

## Quick Start

1. Clone the repository and install Node.js dependencies:
   ```sh
   git clone https://github.com/humanbydefinition/Asemode.git asemode
   cd asemode
   npm ci
   ```

2. Install Lua Language Server with `mise` and install Lua 5.4.6 separately:
   ```sh
   mise install
   ```
   > [!TIP]
   > You can also use a system installation of Lua 5.4.6. If `lua` is not in your `PATH`, set the `LUA_BIN` environment variable to the executable path.

3. Run the automated test suite:
   ```sh
   mise exec -- npm test
   ```

## Development Workflow

### Building the Extension

Compile generated resources and build the `.aseprite-extension` package in `dist/`:

```sh
npm run build
```

This command generates Lua font tables from `assets/fonts/registry.json`, generates Unicode character data, updates `src/core/version.lua`, and writes the extension archive and SHA-256 checksum to `dist/`. The 11 default fonts are committed in the repository, so builds work without external font downloads.

### Code Style and Formatting

The repository enforces consistent formatting for both Lua and JavaScript:

- **Lua**: Formatted with StyLua. Run `npm run format:lua` to format Lua files.
- **JavaScript & Config**: Formatted with Prettier. Run `npm run format` to format JavaScript and configured JSON and YAML files.
- **Check formatting**:
  ```sh
  npm run format:check
  npm run format:lua:check
  ```

### Lua readability and documentation

Put one blank line between named functions and methods. Group imports, constants,
and related work within longer functions. Keep documentation comments directly
above the declarations they describe. Do not edit generated Lua resources by hand.
StyLua checks formatting but does not require blank lines between functions;
reviewers check those boundaries and the readability of logical groups.

Use [Lua Language Server annotations](https://github.com/LuaLS/lua-language-server/wiki/Annotations)
to document module interfaces and shared types. Describe parameters, return
values, mutations, and failure behavior when they matter to a caller. Document
internal helpers and test fixtures when their contracts are not obvious. These
comments help the editor and static analysis; they do not validate values at runtime.
Shared interface definitions belong in `tools/meta/asemode.lua` when useful.

CI checks annotation consistency and selected diagnostics, not complete
function documentation coverage. Review documentation and spacing as part of
code review. See the [Lua definitions guide](tools/meta/README.md).

### Running Tests

The test suite validates logic, diagnostics, portable document compatibility, and package integrity:

- **Full test suite**: `mise exec -- npm test`
- **Lua diagnostics and unit tests**: `mise exec -- npm run check:lua`
- **Portable document format parity**: `npm run test:portable`
- **Package archive validation**: `npm run test:package`

See the [scripts guide](scripts/README.md) for individual commands and options. Use the [test documents](tests/test-documents/README.md) to exercise Textmode import warnings and errors.

### Manual Testing in Aseprite

Before submitting user interface changes, test the extension inside Aseprite:

1. Build the archive with `npm run build`.
2. In Aseprite, open **Edit > Preferences... > Extensions**.
3. Click **Add Extension**, select the `.aseprite-extension` file in `dist/`, and enable Asemode.
4. Verify your changes in both **Default** and **Default Dark** themes:
   - Confirm canvases and previews repaint properly when switching themes.
   - Test dialogs and panels at 100% and 200% UI scaling.
   - Verify glyph selection, color pickers, and stamp transformations.

## Pull Request Guidelines

1. **Branch from `dev`**: Create a feature branch from the `dev` branch. All pull requests must target `dev`.
2. **Keep changes focused**: Solve one problem or add one feature per pull request.
3. **Add automated tests**: Include pure Lua unit tests in `tests/pure/` for any new or modified behavior.
4. **Follow Conventional Commits**: Use conventional prefixes (such as `feat:`, `fix:`, `docs:`, or `refactor:`). Commit hooks validate commit messages automatically.
5. **Include visual proof**: Attach before-and-after screenshots or recordings to pull requests that modify the user interface.
6. **Verify locally**: Confirm that `mise exec -- npm test` passes before opening a pull request.

## Community and Security

- **Code of Conduct**: Follow the project [Code of Conduct](CODE_OF_CONDUCT.md) in all community interactions.
- **Security Issues**: Report security vulnerabilities privately following [SECURITY.md](SECURITY.md). Do not report security vulnerabilities in public issues.
