# Tests

This directory contains Asemode's Lua and Node.js tests and test documents. Run commands from the repository root. See the [Contributing Guide](../CONTRIBUTING.md) for the development prerequisites and setup.

## Directories

| Path | Purpose |
| :--- | :--- |
| [`pure/`](pure/) | Lua tests for application logic and UI helpers without an Aseprite UI. `run.lua` is the test entry point; `cases.lua` supports the portable-document parity runner. |
| [`node/`](node/) | Node.js tests for packaging utilities, Lua Language Server checks, and screenshot publishing. |
| [`fixtures/portable/`](fixtures/portable/README.md) | Portable-format fixtures, including older versions used to verify rejection. |
| [`fixtures/browser/`](fixtures/browser/README.md) | Documents captured from textmode.art web tools for interoperability checks. |
| [`fixtures/artwork/`](fixtures/artwork/README.md) | Compressed artwork fixtures used by the portable tests. |
| [`fixtures/font-identities.json`](fixtures/font-identities.json) | Expected portable identities of registered font files. |
| [`test-documents/`](test-documents/README.md) | Documents for manual testing of import warnings, recovery, and errors. Some are intentionally invalid. |

## Run Tests

Install dependencies with `npm ci` and use the Lua 5.4.6 and Lua Language Server setup in the [Contributing Guide](../CONTRIBUTING.md#prerequisites).

```sh
# Run the repository test suite, including build and package checks
mise exec -- npm test

# Run Lua formatting, diagnostics, and pure Lua tests
mise exec -- npm run check:lua

# Check portable-document compatibility
npm run test:portable

```

The automated suite does not launch Aseprite. To run all host scripts, set `ASEPRITE_PATH` to an Aseprite executable and use an isolated user folder. This prevents installed extensions from registering duplicate event handlers:

```sh
(
  set -e
  ASEPRITE_TEST_PROFILE=$(mktemp -d)
  trap 'rm -rf "$ASEPRITE_TEST_PROFILE"' EXIT
  for script in tests/host/*.lua; do
    ASEPRITE_USER_FOLDER="$ASEPRITE_TEST_PROFILE" "$ASEPRITE_PATH" -b --script-param root="$PWD" --script "$script"
  done
)
```

Use the [test-document guide](test-documents/README.md) for manual import testing in Aseprite.

If Lua 5.4.6 is installed outside `PATH`, set `LUA_BIN` to its executable path. See the [check scripts guide](../scripts/check/README.md) for individual checks, environment variables, and output locations.

## Working with Fixtures

Use the [test-document guide](test-documents/README.md) to reproduce import warnings and errors in Aseprite. The portable, browser, and artwork fixture guides record their provenance and, where applicable, hashes. Preserve intentionally invalid inputs and update their documented expectations when changing behavior.
