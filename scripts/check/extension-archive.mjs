import { createHash } from 'node:crypto';
import yauzl from 'yauzl';

/**
 * Reject an archive with a consistent error prefix.
 * @param {string} message Reason the archive is invalid.
 * @throws {Error} Always.
 * @returns {never} This function always throws.
 */
const fail = (message) => {
	throw new Error(`Invalid extension archive: ${message}`);
};
/**
 * Read and validate ZIP entries, including safe names and uncompressed sizes.
 * @param {Buffer} zip Archive bytes.
 * @returns {Promise<Map<string, {name: string, bytes: Buffer}>>} Validated entries by path.
 * @throws {Error} If the archive is malformed or contains unsafe or duplicate paths.
 */
export async function readArchive(zip) {
	const entries = new Map();
	const file = await yauzl.fromBufferPromise(zip, { lazyEntries: true, autoClose: false, strictFileNames: true });
	try {
		for await (const entry of file.eachEntry()) {
			const name = entry.fileName;
			if (name.endsWith('/')) continue;
			if (entries.has(name)) fail(`duplicate entry ${name}`);
			const stream = await file.openReadStreamPromise(entry);
			const chunks = [];
			for await (const chunk of stream) chunks.push(chunk);
			const bytes = Buffer.concat(chunks);
			entries.set(name, { name, bytes });
		}
		return entries;
	} finally {
		file.close();
	}
}

/**
 * Check release contents, manifest, font resources, and the archive checksum.
 * @param {Map<string, {name: string, bytes: Buffer}>} entries Validated archive entries.
 * @param {Buffer} zip Original archive bytes.
 * @param {string} archiveName Expected archive filename.
 * @param {string} checksum Contents of its SHA-256 checksum file.
 * @param {Array<{id: string, distribution?: string}>} registry Bundled font registry.
 * @param {'default'|'release'} [edition='default'] Font distribution edition.
 * @returns {object} Parsed extension manifest.
 * @throws {Error} If the archive violates release policy or its checksum differs.
 */
export function checkRelease(entries, zip, archiveName, checksum, registry, edition = 'default') {
	for (const name of [
		'package.json',
		'README.md',
		'LICENSE',
		'THIRD_PARTY_NOTICES.md',
		'docs/guide/README.md',
		'assets/fonts/licenses/CHUNKY.txt',
		'assets/fonts/licenses/FROGBLOCK.txt',
		'assets/fonts/licenses/KITCHEN-SINK.txt',
	])
		if (!entries.has(name)) fail(`missing required file ${name}`);
	for (const name of entries.keys()) {
		if (name === 'examples/textmode-tycoon/textmode-tycoon.aseprite') fail(`excluded font masks ${name}`);
		if (name.toLowerCase().endsWith('.ttf') || name.includes('PublicPixel')) fail(`raw or removed font ${name}`);
		if (
			name.startsWith('tools/') ||
			name.startsWith('tests/') ||
			name.startsWith('scripts/') ||
			name === '.luarc.json' ||
			name === '.stylua.toml'
		)
			fail(`development tooling ${name}`);
		if (name.endsWith('.aseprite-keys')) fail(`bundled shortcut ${name}`);
	}
	const manifest = JSON.parse(entries.get('package.json')?.bytes.toString() || 'null');
	if (
		!manifest ||
		manifest.contributes?.keys ||
		manifest.scripts ||
		manifest.devDependencies ||
		manifest.private ||
		!Array.isArray(manifest.contributes?.scripts) ||
		manifest.contributes.scripts.length === 0 ||
		manifest.contributes.scripts.some(({ path }) => !path || !entries.has(path.replace(/^\.\//, '')))
	)
		fail('unsanitized manifest');
	for (const font of registry) {
		const present = entries.has(`src/fonts/data/${font.id}.lua`);
		if ((edition === 'release' || font.distribution !== 'optional') && !present)
			fail(`missing font resource ${font.id}`);
		if (edition === 'default' && font.distribution === 'optional' && present)
			fail(`unexpected font resource ${font.id}`);
	}
	const allowed = new Set(
		registry
			.filter((font) => edition === 'release' || font.distribution !== 'optional')
			.map((font) => `src/fonts/data/${font.id}.lua`)
	);
	if (edition === 'release') {
		allowed.add('src/fonts/data/FROGBLOCK-license.txt');
		allowed.add('src/fonts/data/KITCHEN-SINK-license.txt');
		if (!entries.has('src/fonts/data/FROGBLOCK-license.txt')) fail('missing FROGBLOCK license');
		if (!entries.has('src/fonts/data/KITCHEN-SINK-license.txt')) fail('missing Kitchen Sink license');
	}
	for (const name of entries.keys())
		if (name.startsWith('src/fonts/data/') && !allowed.has(name)) fail(`unexpected font resource ${name}`);
	const expected = `${createHash('sha256').update(zip).digest('hex')}  ${archiveName}\n`;
	if (checksum !== expected) fail('checksum mismatch');
	return manifest;
}
