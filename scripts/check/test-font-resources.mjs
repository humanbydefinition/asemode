import assert from 'node:assert/strict';
import {
	mkdtempSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
	readdirSync,
	cpSync,
	rmSync,
	truncateSync,
} from 'node:fs';
import { resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { identifySfntFont } from '@textmode/document/font';
import { generateFontResources } from '../build/generate-font-resources.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = mkdtempSync(resolve(tmpdir(), 'asemode-resource-check-'));
try {
	mkdirSync(resolve(fixture, 'assets/fonts'), { recursive: true });
	const fonts = JSON.parse(readFileSync(resolve(root, 'assets/fonts/registry.json')));
	const registry = resolve(fixture, 'assets/fonts/registry.json');
	const font = fonts.find((font) => font.id === 'unscii-8');
	writeFileSync(registry, JSON.stringify([font]));
	cpSync(resolve(root, 'assets/fonts', font.file), resolve(fixture, 'assets/fonts', font.file));
	generateFontResources(fixture);
	const files = ['src/fonts/bundled.lua', 'src/fonts/resources.lua', 'src/fonts/data/unscii-8.lua'];
	const before = files.map((file) => readFileSync(resolve(fixture, file)));
	generateFontResources(fixture);
	files.forEach((file, index) => assert.deepEqual(readFileSync(resolve(fixture, file)), before[index]));
	for (const change of ['missing', 'modified', 'unexpected']) {
		const target = resolve(fixture, change === 'unexpected' ? 'src/fonts/data/stale.lua' : files[2]);
		if (change === 'missing') rmSync(target);
		else writeFileSync(target, '-- stale\n');
		const contents = readdirSync(resolve(fixture, 'src/fonts/data')).map((name) => [
			name,
			readFileSync(resolve(fixture, 'src/fonts/data', name)).toString(),
		]);
		assert.throws(() => generateFontResources(fixture, true), /stale/);
		assert.deepEqual(
			readdirSync(resolve(fixture, 'src/fonts/data')).map((name) => [
				name,
				readFileSync(resolve(fixture, 'src/fonts/data', name)).toString(),
			]),
			contents
		);
		generateFontResources(fixture);
	}
	for (const entry of [
		{ ...font, id: '' },
		{ ...font, file: '../escape.ttf' },
		{ ...font, file: 'missing.ttf' },
		{ ...font, author: '' },
	]) {
		writeFileSync(registry, JSON.stringify([entry]));
		assert.throws(() => generateFontResources(fixture));
	}
	writeFileSync(registry, JSON.stringify([font, font]));
	assert.throws(() => generateFontResources(fixture), /duplicate/);
	writeFileSync(registry, JSON.stringify([font, { ...font, id: 'another-id' }]));
	assert.throws(() => generateFontResources(fixture), /duplicate/);
	writeFileSync(registry, JSON.stringify([font]));
	truncateSync(resolve(fixture, 'assets/fonts', font.file), 16 * 1024 * 1024 + 1);
	assert.throws(() => generateFontResources(fixture), /byte length/);
	cpSync(resolve(root, 'assets/fonts', font.file), resolve(fixture, 'assets/fonts', font.file));
	const optional = {
		...font,
		id: 'optional-font',
		file: 'optional.ttf',
		distribution: 'optional',
		sourceSha256: createHash('sha256')
			.update(readFileSync(resolve(fixture, 'assets/fonts', font.file)))
			.digest('hex'),
	};
	writeFileSync(registry, JSON.stringify([font, optional]));
	generateFontResources(fixture);
	assert.ok(!readdirSync(resolve(fixture, 'src/fonts/data')).includes('optional-font.lua'));
	mkdirSync(resolve(fixture, 'tests/fixtures'), { recursive: true });
	const golden = JSON.parse(readFileSync(resolve(root, 'tests/fixtures/font-identities.json')));
	writeFileSync(
		resolve(fixture, 'tests/fixtures/font-identities.json'),
		JSON.stringify({ [font.file]: golden[font.file], [optional.file]: golden[font.file] })
	);
	assert.throws(() => generateFontResources(fixture, false, 'release'), /missing optional.ttf/);
	cpSync(resolve(fixture, 'assets/fonts', font.file), resolve(fixture, 'assets/fonts', optional.file));
	generateFontResources(fixture, false, 'release');
	assert.ok(readdirSync(resolve(fixture, 'src/fonts/data')).includes('optional-font.lua'));
	const optionalBytes = readFileSync(resolve(fixture, 'assets/fonts', optional.file));
	const independentId = identifySfntFont(optionalBytes);
	assert(independentId.ok);
	assert.equal(independentId.font.id, golden[font.file]);
	assert.equal(createHash('sha256').update(optionalBytes).digest('hex'), optional.sourceSha256);
	/**
	 * Run the independent identity check against the temporary fixture.
	 * @returns {import('node:child_process').SpawnSyncReturns<string>} Check process result.
	 */
	const identityCheck = () =>
		spawnSync(process.execPath, [resolve(root, 'scripts/check/test-font-identities.mjs'), '--root', fixture], {
			encoding: 'utf8',
		});
	assert.equal(identityCheck().status, 0, 'Independent identity command must accept valid fonts');
	const expectedPath = resolve(fixture, 'tests/fixtures/font-identities.json');
	writeFileSync(expectedPath, JSON.stringify({ [font.file]: golden[font.file], [optional.file]: 'wrong-identity' }));
	assert.notEqual(identityCheck().status, 0, 'Identity command must reject a mismatched golden');
	assert.throws(() => generateFontResources(fixture, false, 'release'), /identity mismatch optional.ttf/);
	writeFileSync(expectedPath, JSON.stringify({ [font.file]: golden[font.file], [optional.file]: golden[font.file] }));
	writeFileSync(registry, JSON.stringify([font, { ...optional, sourceSha256: 'a'.repeat(64) }]));
	assert.notEqual(identityCheck().status, 0, 'Identity command must reject a mismatched source hash');
	assert.throws(() => generateFontResources(fixture, false, 'release'), /identity mismatch optional.ttf/);
	writeFileSync(registry, JSON.stringify([font, optional]));
	writeFileSync(resolve(fixture, 'assets/fonts', optional.file), 'not a font');
	assert.throws(() => generateFontResources(fixture, false, 'release'), /identity mismatch optional.ttf/);
	console.log('PASS resource generation, determinism, validation, and read-only stale checks');
} finally {
	rmSync(fixture, { recursive: true, force: true });
}
