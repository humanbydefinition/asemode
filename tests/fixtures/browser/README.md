# Browser interoperability fixtures

Captured through the local web interfaces on 2026-10-25 and converted from v3 to v4 with @textmode/document 4.0.0. The hashes identify the converted fixtures.

| Fixture | Producer checkout | Authored input | SHA-256 |
| --- | --- | --- | --- |
| export.textmode.json | export.textmode.art f195789 plus existing local changes | export-source.svg; default BESCII conversion; JSON download | `0b6221f60d48fa810635a5d01fa5a6bd276d7f4b888e6ea83aa92bd6ddb1f111` |
| create.textmode.json | create.textmode.art 05f13c6 plus existing local changes | Fresh 32×32 project; two painted A cells; second rotated 90°; File > Export > Textmode document | `b60ce6b9296599ab7c10481aa30e5105f3ae7755feaef37c3adc64f89a4d1acc` |
| export-rotation.textmode.json | export.textmode.art f195789 plus existing local changes | export-source.svg; default BESCII conversion; glyph rotation slider set to 90°; JSON download encodes 90.35° | `75fcdebb74ff79b8fa539d88137632ef31550b277afcf78a5a20ac0045a34f66` |

The host-independent portable tests compare these fixtures with the
`@textmode/document` decoder and schema. The framebuffer rotation fixture is
valid protocol input; its 90.35° rotation is preserved in the fixture.
