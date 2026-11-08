import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { identifySfntFont } from '@textmode/document/font';

/**
 * Read the font registry from a project root.
 * @param {string} root Project root.
 * @returns {Array<object>} Registered font entries.
 * @throws {Error} If the registry is empty or invalid.
 */
export function loadFontRegistry(root) {
	const registry = JSON.parse(readFileSync(resolve(root, 'assets/fonts/registry.json'), 'utf8'));
	if (!Array.isArray(registry) || registry.length === 0) throw new Error('Font registry must be a nonempty array');
	return registry;
}

/**
 * Read the committed identity fixture, if available or required.
 * @param {string} root Project root.
 * @param {boolean} [required=false] Require the fixture to exist.
 * @returns {Record<string, string>|null} Font identities, or null if absent and optional.
 */
export function loadFontIdentities(root, required = false) {
	const path = resolve(root, 'tests/fixtures/font-identities.json');
	return required || existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null;
}

/**
 * Validate font bytes against the identity fixture and optional source hash.
 * @param {{file: string, sourceSha256?: string}} font Font registry entry.
 * @param {Uint8Array} bytes Font file bytes.
 * @param {Record<string, string>|null} golden Expected identities, or null to skip comparison.
 * @param {boolean} [verifySourceHash=false] Compare the source SHA-256 hash.
 * @returns {{font: object, sha256: string}} Identified font and its SHA-256 hash.
 * @throws {Error} If the font or its identity is invalid.
 */
export function verifyFontIdentity(font, bytes, golden, verifySourceHash = false) {
	const result = identifySfntFont(bytes);
	if (!result.ok) throw new Error(`Invalid font: ${font.file}: ${result.error.message}`);
	if (golden && golden[font.file] !== result.font.id) throw new Error(`Font identity mismatch: ${font.file}`);
	const sha256 = createHash('sha256').update(bytes).digest('hex');
	if (verifySourceHash && sha256 !== font.sourceSha256) throw new Error(`SHA-256 mismatch: ${font.file}`);
	return { font: result.font, sha256 };
}
