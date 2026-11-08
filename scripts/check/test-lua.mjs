import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const lua = process.env.LUA_BIN || 'lua';
/**
 * Run a Lua test process and return its standard output.
 * @param {string[]} args Lua script and arguments.
 * @returns {string} Process output.
 * @throws {Error} If the process fails.
 */
function run(args) {
	const child = spawnSync(lua, args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
	if (child.error || child.status !== 0) throw child.error || new Error(child.stderr || `Lua exited ${child.status}`);
	return child.stdout;
}
const version = spawnSync(lua, ['-v'], { encoding: 'utf8' });
assert.match((version.stdout || '') + (version.stderr || ''), /Lua 5\.4\.6\b/, 'Lua 5.4.6 is required');
const output = run(['tests/pure/run.lua']);
process.stdout.write(output);
assert.match(output, /ASEMODE_PURE_OK \d+/);
