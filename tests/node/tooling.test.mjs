import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { crc32, deflateRawSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readArchive, checkRelease } from '../../scripts/check/extension-archive.mjs';
import { pruneArchives } from '../../scripts/build/package.mjs';

test('extension uses Asemode as its identity and display name', () => {
	const manifest = JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8'));
	assert.equal(manifest.name, 'asemode');
	assert.equal(manifest.displayName, 'Asemode');
});

test('archive cleanup retains the current release and unrelated files', () => {
	const dir = mkdtempSync(join(tmpdir(), 'asemode-dist-'));
	try {
		const current = 'asemode-1.0.0.aseprite-extension';
		const old = 'asemode-0.1.2.aseprite-extension';
		const directory = 'asemode-directory.aseprite-extension';
		mkdirSync(join(dir, directory));
		for (const name of [current, `${current}.sha256`, old, `${old}.sha256`, 'notes.txt'])
			writeFileSync(join(dir, name), 'data');
		pruneArchives(dir, current);
		assert.deepEqual(readdirSync(dir).sort(), [current, `${current}.sha256`, directory, 'notes.txt'].sort());
		assert.throws(() => pruneArchives(join(dir, 'missing'), current));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('importing the package module does not build an archive', () => {
	const dir = mkdtempSync(join(tmpdir(), 'asemode-import-'));
	try {
		const moduleUrl = new URL('../../scripts/build/package.mjs', import.meta.url).href;
		execFileSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(moduleUrl)})`], {
			cwd: dir,
		});
		assert.deepEqual(readdirSync(dir), []);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

/**
 * Create a ZIP archive with the specified entries for archive validation tests.
 * @param {Array<{name: string, text: string, method?: number}>} files Archive entries.
 * @returns {Buffer} ZIP archive bytes.
 */
function zipOf(files) {
	const local = [],
		central = [];
	let offset = 0;
	for (const { name, text, method = 8 } of files) {
		const n = Buffer.from(name),
			b = Buffer.from(text),
			data = method === 8 ? deflateRawSync(b) : b,
			crc = crc32(b);
		const h = Buffer.alloc(30);
		h.writeUInt32LE(0x04034b50);
		h.writeUInt16LE(0x800, 6);
		h.writeUInt16LE(method, 8);
		h.writeUInt32LE(crc, 14);
		h.writeUInt32LE(data.length, 18);
		h.writeUInt32LE(b.length, 22);
		h.writeUInt16LE(n.length, 26);
		const c = Buffer.alloc(46);
		c.writeUInt32LE(0x02014b50);
		c.writeUInt16LE(0x800, 8);
		c.writeUInt16LE(method, 10);
		c.writeUInt32LE(crc, 16);
		c.writeUInt32LE(data.length, 20);
		c.writeUInt32LE(b.length, 24);
		c.writeUInt16LE(n.length, 28);
		c.writeUInt32LE(offset, 42);
		local.push(h, n, data);
		central.push(c, n);
		offset += h.length + n.length + data.length;
	}
	const directory = Buffer.concat(central),
		end = Buffer.alloc(22);
	end.writeUInt32LE(0x06054b50);
	end.writeUInt16LE(files.length, 8);
	end.writeUInt16LE(files.length, 10);
	end.writeUInt32LE(directory.length, 12);
	end.writeUInt32LE(offset, 16);
	return Buffer.concat([...local, directory, end]);
}

test('archive reader rejects corrupt, duplicate and unsafe entries', async () => {
	const zip = zipOf([
		{ name: 'a.txt', text: 'alpha', method: 0 },
		{ name: 'ü/b.txt', text: 'beta' },
	]);
	const entries = await readArchive(zip);
	assert.equal(entries.get('ü/b.txt').bytes.toString(), 'beta');
	for (const name of ['../bad', '/bad', 'C:/bad', 'a\\b'])
		await assert.rejects(readArchive(zipOf([{ name, text: 'x' }])));
	await assert.rejects(
		readArchive(
			zipOf([
				{ name: 'a', text: 'x' },
				{ name: 'a', text: 'y' },
			])
		),
		/duplicate/
	);
	await assert.rejects(readArchive(zip.subarray(0, zip.length - 22)));
});
test('release policy validates checksum, manifest and exclusions', async () => {
	const files = [
		{ name: 'package.json', text: JSON.stringify({ contributes: { scripts: [{ path: 'main.lua' }] } }) },
		{ name: 'main.lua', text: '' },
	];
	for (const name of [
		'README.md',
		'LICENSE',
		'THIRD_PARTY_NOTICES.md',
		'docs/guide/README.md',
		'assets/fonts/licenses/CHUNKY.txt',
		'assets/fonts/licenses/FROGBLOCK.txt',
		'assets/fonts/licenses/KITCHEN-SINK.txt',
	])
		files.push({ name, text: '' });
	const zip = zipOf(files),
		entries = await readArchive(zip),
		name = 'x.zip';
	const checksum = `${createHash('sha256').update(zip).digest('hex')}  ${name}\n`;
	assert(checkRelease(entries, zip, name, checksum, []));
	assert.throws(() => checkRelease(entries, zip, name, 'wrong', []), /checksum/);
	assert.throws(() => checkRelease(entries, zip, name, checksum, [{ id: 'missing' }]), /font/);
	assert.throws(
		() => checkRelease(entries, zip, name, checksum, [{ id: 'optional', distribution: 'optional' }], 'release'),
		/missing font resource/
	);
	const noLicense = new Map(entries);
	noLicense.delete('LICENSE');
	assert.throws(() => checkRelease(noLicense, zip, name, checksum, []), /missing required file/);
	const noFontLicense = new Map(entries);
	noFontLicense.delete('assets/fonts/licenses/CHUNKY.txt');
	assert.throws(() => checkRelease(noFontLicense, zip, name, checksum, []), /missing required file/);
	const noEntrypoint = new Map(entries);
	noEntrypoint.delete('main.lua');
	assert.throws(() => checkRelease(noEntrypoint, zip, name, checksum, []), /manifest/);
	for (const name of ['a.ttf', 'tests/a', 'tools/a', 'foo.aseprite-keys']) {
		const bad = new Map(entries);
		bad.set(name, { name, bytes: Buffer.alloc(0) });
		assert.throws(() => checkRelease(bad, zip, 'x.zip', checksum, []));
	}
});
