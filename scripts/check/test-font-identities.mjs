import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadFontRegistry, loadFontIdentities, verifyFontIdentity } from '../build/font-verification.mjs';

const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--root'))
	throw new Error('Usage: node scripts/check/test-font-identities.mjs [--root DIRECTORY]');
const root = args.length ? resolve(args[1]) : resolve(import.meta.dirname, '../..');
const golden = loadFontIdentities(root, true);
const registry = loadFontRegistry(root);
const inventory = [];
for (const font of registry) {
	const path = resolve(root, 'assets/fonts', font.file);
	if (font.distribution === 'optional' && !existsSync(path)) continue;
	assert(Object.hasOwn(golden, font.file), `Missing golden identity: ${font.file}`);
	const bytes = readFileSync(path);
	const verified = verifyFontIdentity(font, bytes, golden, font.distribution === 'optional');
	inventory.push({ project: 'asemode', file: font.file, ...verified.font });
}
mkdirSync(resolve(root, '.test-output'), { recursive: true });
writeFileSync(resolve(root, '.test-output/font-identities.json'), JSON.stringify(inventory, null, 2) + '\n');
console.log(`Verified ${inventory.length} font assets from the Asemode registry.`);
