import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { gunzipSync } from 'node:zlib';
import { parseTextmodeDocumentJSON } from '@textmode/document';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const cases = [];
/**
 * Add a document and optional decoding limits to the comparison cases.
 * @param {string} name Case label.
 * @param {string} text Document JSON.
 * @param {object} [limits] Decoder resource limits.
 * @returns {number} Number of accumulated cases.
 */
const add = (name, text, limits = {}) => cases.push({ name, text, limits });
const fixtureRoot = resolve(root, 'tests/fixtures/portable');
for (const file of readdirSync(fixtureRoot).filter((name) => name.endsWith('.json'))) {
	add(file, readFileSync(resolve(fixtureRoot, file), 'utf8'));
}
const browserFixtures = resolve(root, 'tests/fixtures/browser');
for (const file of readdirSync(browserFixtures).filter((name) => name.endsWith('.json'))) {
	add(file, readFileSync(resolve(browserFixtures, file), 'utf8'));
}
const artwork = gunzipSync(
	readFileSync(resolve(root, 'tests/fixtures/artwork/textmode-tycoon.textmode.json.gz'))
).toString('utf8');
add('textmode-tycoon.textmode.json', artwork);
add(
	'textmode-export-animation.json',
	gunzipSync(readFileSync(resolve(root, 'tests/fixtures/artwork/textmode-export-animation.json.gz'))).toString('utf8')
);
const base = JSON.parse(cases.find((item) => item.name === 'v4-single-layer.json').text);
/**
 * Add a modified copy of the base document to the comparison cases.
 * @param {string} name Case label.
 * @param {Function} change Function that mutates the copied document.
 * @param {object} [limits] Decoder resource limits.
 * @returns {void}
 */
const mutation = (name, change, limits) => {
	const value = structuredClone(base);
	change(value);
	add(name, JSON.stringify(value), limits);
};
/**
 * Select the first cell in the base fixture.
 * @param {object} d Portable document fixture.
 * @returns {object} First cell.
 */
const cell = (d) => d.frames[0].layers[0].cells.rows[0][0];
for (const key of ['target', 'layer', 'grid', 'canvas'])
	mutation(`reserved ${key}`, (d) => {
		d[key] = null;
	});
for (const key of ['id', 'visible', 'opacity', 'blendMode', 'offsetX', 'offsetY', 'rotationZ', 'grid', 'cells']) {
	mutation(`missing layer ${key}`, (d) => {
		delete d.frames[0].layers[0][key];
	});
}
for (const version of ['3.1.0', '4.0.0', '4.1.0', '5.0.0', '3', '', null])
	mutation(`version ${version}`, (d) => {
		d.formatVersion = version;
	});
for (const font of [
	null,
	{},
	{ id: 'bad' },
	{ id: 'sfnt-v1-sha256:' + 'a'.repeat(64) },
	{ id: 'sfnt-v1-sha256:' + 'a'.repeat(64), name: 'UrsaFont' },
	{ id: 'sfnt-v1-sha256:' + 'a'.repeat(64), name: null },
]) {
	mutation('4.0 font ' + JSON.stringify(font), (d) => {
		d.formatVersion = '4.0.0';
		d.frames[0].layers[0].font = font;
	});
}
for (const value of ['', null, 'A\u0301', '\ud800', '\udc00', '\ud800A', '\u0000', '😀', 'A'.repeat(65)]) {
	mutation(`character ${JSON.stringify(value)}`, (d) => {
		cell(d).character = value;
	});
}
for (const color of ['#123456', '#12345678', '#00000000', '#gggggg', '#fff', null, {}, { r: 1, g: 2, b: 3, a: 256 }]) {
	mutation(`color ${JSON.stringify(color)}`, (d) => {
		cell(d).foreground = color;
	});
}
for (const rotation of [-90, 360, -360, 90.35, 1e100])
	mutation(`rotation ${rotation}`, (d) => {
		cell(d).transform.rotation = rotation;
	});
for (const date of [
	'2024-02-29T23:59:59.01+01:30',
	'2025-02-29T00:00:00Z',
	'2026-01-01t00:00:00Z',
	'2026-01-01T00:00:60Z',
	'2026-01-01T00:00:00. Z',
	'0000-02-29T00:00:00-23:59',
]) {
	mutation(`timestamp ${date}`, (d) => {
		d.metadata = { createdAt: date, generator: { name: 'test', version: '1' } };
	});
}
mutation('NUL and supplementary IDs', (d) => {
	d.frames[0].layers[0].id = 'a\u0000b😀';
});
mutation('unpaired surrogate ID', (d) => {
	d.frames[0].layers[0].id = '\ud800';
});
mutation('UTF-16 ID limit', (d) => {
	d.frames[0].layers[0].id = '😀'.repeat(513);
});
mutation('unknown fields omitted', (d) => {
	d.extra = { x: null };
	cell(d).extra = [];
});
mutation('row coordinate mismatch', (d) => {
	cell(d).x = 99;
});
mutation('empty layers', (d) => {
	d.frames[0].layers = [];
});
mutation('object instead of rows', (d) => {
	d.frames[0].layers[0].cells.rows = {};
});
mutation('layer budget', () => {}, { maxCells: 1 });
mutation('unsafe extent', (d) => {
	d.frames[0].layers[0].grid.cellWidth = Number.MAX_SAFE_INTEGER;
});
mutation('unsupported encoding', (d) => {
	d.frames[0].layers[0].cells.encoding = 'future';
});
const v4 = {
	format: 'textmode.document',
	formatVersion: '4.0.0',
	frames: [
		{ durationMs: 1000 / 60, layers: structuredClone(base.frames[0].layers) },
		{ durationMs: 250, layers: [] },
	],
};
add('v4 frame count', JSON.stringify(v4), { maxFrames: 1 });
add('v4 cumulative layer count', JSON.stringify({ ...v4, frames: [v4.frames[0], v4.frames[0]] }), {
	maxTotalLayers: 1,
});
add('v4 cumulative cells', JSON.stringify({ ...v4, frames: [v4.frames[0], v4.frames[0]] }), { maxCells: 1 });
add('v4 variable frames', JSON.stringify(v4));
add(
	'v4 safe duration and tiny overflow',
	JSON.stringify({
		format: v4.format,
		formatVersion: v4.formatVersion,
		frames: [
			{ durationMs: Number.MAX_SAFE_INTEGER, layers: [] },
			{ durationMs: Number.MIN_VALUE, layers: [] },
		],
	})
);
for (const [name, change] of [
	[
		'empty frames',
		(d) => {
			d.frames = [];
		},
	],
	[
		'zero duration',
		(d) => {
			d.frames[1].durationMs = 0;
		},
	],
	[
		'missing duration',
		(d) => {
			delete d.frames[1].durationMs;
		},
	],
	[
		'duplicate id',
		(d) => {
			d.frames[0].layers.push(structuredClone(d.frames[0].layers[0]));
		},
	],
	[
		'root layers',
		(d) => {
			d.frames[0].layers = null;
		},
	],
]) {
	const value = structuredClone(v4);
	change(value);
	add(`v4 ${name}`, JSON.stringify(value));
}
for (const text of ['null', '[]', '{}', '01', '[1,]', '{"a":}', '1.', '1e', '', 'true false', '"\\q"'])
	add(`syntax ${text}`, text);
add('duplicate last key', JSON.stringify(base).replace('"textmode.document"', '"other","format":"textmode.document"'));
const child = spawnSync(process.env.LUA_BIN || 'lua', ['tests/pure/cases.lua'], {
	cwd: root,
	input: JSON.stringify(cases),
	encoding: 'utf8',
	maxBuffer: 32 * 1024 * 1024,
});
if (child.error || child.status !== 0) throw child.error || new Error(child.stderr || `Lua exited ${child.status}`);
const actual = JSON.parse(child.stdout);
for (let index = 0; index < cases.length; index++) {
	const item = cases[index];
	let parsed;
	try {
		parsed = JSON.parse(item.text);
	} catch {}
	if (
		parsed?.format === 'textmode.layer' ||
		(typeof parsed?.formatVersion === 'string' && /^([0-3])\.\d+\.\d+$/.test(parsed.formatVersion))
	) {
		assert.equal(actual[index].ok, false, item.name);
		assert.equal(
			actual[index].error.code,
			parsed.format === 'textmode.layer' ? 'UNSUPPORTED_FORMAT' : 'UNSUPPORTED_VERSION',
			item.name
		);
		continue;
	}
	if (parsed?.formatVersion === '4.1.0' || parsed?.formatVersion === '5.0.0') {
		assert.equal(actual[index].ok, true, item.name);
		continue;
	}
	const expected = parseTextmodeDocumentJSON(item.text, { limits: item.limits });
	assert.equal(actual[index].ok, expected.ok, item.name);
	if (expected.ok) {
		assert.deepEqual(actual[index].document, expected.document, item.name);
		assert.deepEqual(
			actual[index].warnings.map((v) => v.code),
			expected.warnings.map((v) => v.code),
			item.name
		);
	} else {
		assert.equal(actual[index].error.code, expected.error.code, item.name);
		assert.equal(actual[index].error.path, expected.error.path, item.name);
	}
}
const require = createRequire(import.meta.url);
const schema40 = JSON.parse(readFileSync(require.resolve('@textmode/document/schema/4.0'), 'utf8'));
const ajv = new Ajv2020({ validateFormats: true });
addFormats(ajv);
const validate40 = ajv.compile(schema40);
assert(validate40(JSON.parse(artwork)), JSON.stringify(validate40.errors));
for (const file of readdirSync(browserFixtures).filter((name) => name.endsWith('.json'))) {
	assert(
		validate40(JSON.parse(readFileSync(resolve(browserFixtures, file), 'utf8'))),
		JSON.stringify(validate40.errors)
	);
}
console.log(`Verified ${cases.length} cross-language cases and browser fixtures against schema 4.0.`);
