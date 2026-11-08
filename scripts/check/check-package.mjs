import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { hasOptionalFonts } from '../build/generate-font-resources.mjs';
import { checkRelease, readArchive } from './extension-archive.mjs';

if (process.argv.slice(2).some((arg) => arg !== '--release')) throw new Error('Usage: check-package.mjs [--release]');
const manifest = JSON.parse(readFileSync('package.json'));
const name = `asemode-${manifest.version}.aseprite-extension`;
const edition = process.argv.includes('--release') || hasOptionalFonts(resolve('.')) ? 'release' : 'default';
const path = resolve('dist', name);
const archive = readFileSync(path);
const entries = await readArchive(archive);
checkRelease(
	entries,
	archive,
	name,
	readFileSync(`${path}.sha256`, 'utf8'),
	JSON.parse(readFileSync('assets/fonts/registry.json')),
	edition
);
console.log(`Verified ${entries.size} archive entries and SHA-256 checksum.`);
