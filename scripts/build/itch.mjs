import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../..', import.meta.url));
const mode = process.argv[2];
if (!['dry-run', 'preview', 'publish:first', 'publish', 'status'].includes(mode) || process.argv.length !== 3) {
	throw new Error('Usage: node scripts/build/itch.mjs <dry-run|preview|publish:first|publish|status>');
}

const target = process.env.ITCH_TARGET || (mode === 'dry-run' ? 'local-dry-run/placeholder:aseprite-extension' : '');
if (!/^[^\s/:]+\/[^\s/:]+:[^\s/:]+$/.test(target)) {
	throw new Error('Set ITCH_TARGET to your itch.io target, for example username/project:aseprite-extension.');
}

const { version } = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
if (typeof version !== 'string' || !/^[\da-z][\da-z.+-]*$/i.test(version)) {
	throw new Error('Invalid package version');
}
const archive = resolve(root, `dist/asemode-${version}.aseprite-extension`);
if (mode !== 'status' && !existsSync(archive)) throw new Error(`Build the release archive first: ${archive}`);

let args;
if (mode === 'status') args = ['status', target];
else if (mode === 'preview') args = ['push-preview', '--changes-only', archive, target];
else {
	args = ['push', '--userversion', version];
	if (mode === 'dry-run') args.push('--dry-run');
	if (mode === 'publish:first') args.push('--hidden');
	if (mode === 'publish') args.push('--if-changed');
	args.push(archive, target);
}
const result = spawnSync('butler', args, { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.signal) throw new Error(`Butler terminated by ${result.signal}`);
process.exitCode = result.status ?? 1;
