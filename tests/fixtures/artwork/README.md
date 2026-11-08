# Textmode Tycoon artwork regression

`textmode-tycoon.textmode.json.gz` contains v4 JSON converted with @textmode/document 4.0.0 from a v3 export of the user's `draw-textmode-art-event-8-textmode-tycoon-2.textmode` project
with create.textmode.art's project decoder and portable exporter on 2026-10-25.
Gzip is only a development fixture container. The portable tests decompress
this file and the 15-frame `textmode-export-animation.json.gz` fixture before
comparing the Lua decoder with `@textmode/document`. The extension does not read
gzip files.

Earlier validation imported this artwork in Aseprite and checked save and reopen.
The current automated suite does not run Aseprite.

Decompressed JSON SHA-256:
`25a554401a13ae3a83a8895aa1fbe900dbd46a78ad70fba513c5aa463ca7d8e2`.
