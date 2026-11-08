# Lua Language Server Definitions

This directory contains development-only definitions for Lua Language Server. They provide type information, autocomplete, and diagnostics; Asemode does not load these files at runtime.

## Files

| File | Purpose |
| :--- | :--- |
| [`aseprite.lua`](aseprite.lua) | Aseprite scripting API definitions. The file header records their source and generator revision. |
| [`asemode.lua`](asemode.lua) | Shared types used at Asemode module interfaces. |

Both files use `---@meta` to identify them as definition files. The editor configuration in [`.luarc.json`](../../.luarc.json) and the CI configuration in [`.luarc.ci.json`](../../.luarc.ci.json) load this directory through `workspace.library`.

## Maintenance

Keep Asemode definitions aligned with the corresponding module interfaces. When updating the Aseprite definitions, check them against the supported scripting API and retain their source and attribution information. See [Third-Party Notices](../../THIRD_PARTY_NOTICES.md) for the Aseprite definition attribution.

Run the Lua checks from the repository root after installing the dependencies described in the [Contributing Guide](../../CONTRIBUTING.md):

```sh
mise exec -- npm run check:lua
```

The checks include formatting, Lua Language Server diagnostics, and the pure Lua tests. See the [check scripts guide](../../scripts/check/README.md) for individual commands.
