---@meta
-- Describes values at module interfaces. These annotations are never loaded at runtime.
---@class AsemodeFontSource
---@field kind 'bundled'|'user'|'file'
---@field id? string
---@field path? string
---@field sha256? string

---@class AsemodeFontProfile
---@field kind 'truetype'|'bitmap'
---@field name string
---@field source? AsemodeFontSource
---@field cellWidth integer
---@field cellHeight integer
---@field clippedGlyphs integer

---@class AsemodeFontJob
---@field profile AsemodeFontProfile
---@field glyphs table[]
---@field masks Image[]
---@field position integer
---@field resolveCharacters? fun(keys: string[]): table[]
---@field step fun(self: AsemodeFontJob, batch?: integer): boolean
---@field finish fun(self: AsemodeFontJob): AsemodeFontJob

---@class AsemodeCell
---@field glyphKey string
---@field foregroundRGBA string
---@field backgroundRGBA string
---@field flags integer

---@class AsemodeStampSnapshot
---@field sprite any Captured native target; verify before applying.
---@field layer any
---@field profileId string

---@class AsemodeImportTarget
---@field mode 'new'|'add'
---@field sprite? Sprite Captured destination, invalidated by native changes.
---@field anchor? Layer Insertion anchor.
---@field frame? Frame Captured active frame.
---@field geometry? table Captured grid geometry.

---@class AsemodeImportPlan
---@field target AsemodeImportTarget
---@field layers table[] Staged data; owned by the import operation until commit or cancellation.
---@field layerVariants table[] Native layer groups in first-appearance order.
---@field layerVariantsSplit boolean Whether a source layer needs more than one native layer.
---@field committed? boolean

---@class AsemodeValidationIssue
---@field message string
---@field layer? string
---@field col? integer
---@field row? integer

---@class AsemodeTask
---@field done boolean
---@field canceled boolean
---@field running? boolean
---@field progress string
---@field fraction number
---@field result? any
---@field step fun(self: AsemodeTask, milliseconds?: number): boolean
---@field cancel fun(self: AsemodeTask)
---@field finish fun(self: AsemodeTask): any
