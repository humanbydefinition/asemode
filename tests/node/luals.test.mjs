import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const config = readFileSync(new URL('../../.luarc.ci.json', import.meta.url));
const probes = {
	'undefined-global': 'print(missing_global)\n',
	'duplicate-set-field': '---@class Foo\nlocal Foo = {}\nfunction Foo:x() end\nfunction Foo:x() end\n',
	'duplicate-doc-field': '---@class Foo\n---@field x number\n---@field x string\nlocal Foo = {}\n',
	'unknown-diag-code': '---@diagnostic disable: bogus-code\nlocal x = 1\n',
	'undefined-doc-name': '---@type MissingType\nlocal x\n',
	'undefined-doc-param': '---@param wrong string\nlocal function f(value) return value end\n',
	'incomplete-signature-doc': '---@param first string\nlocal function f(first, second) return first end\n',
	'unknown-symbol': 'local =\n',
};

test('LuaLS CI configuration gates errors and selected diagnostics', () => {
	const dir = mkdtempSync(join(tmpdir(), 'asemode-luals-'));
	try {
		mkdirSync(join(dir, 'src', 'core'), { recursive: true });
		writeFileSync(join(dir, '.luarc.ci.json'), config);
		/**
		 * Run Lua Language Server against the temporary project.
		 * @returns {import('node:child_process').SpawnSyncReturns<string>} Diagnostic process result.
		 */
		const run = () =>
			spawnSync(
				process.env.LUA_LANGUAGE_SERVER || 'lua-language-server',
				['--check=.', '--checklevel=Error', '--configpath=.luarc.ci.json', '--logpath=logs'],
				{ cwd: dir, encoding: 'utf8' }
			);
		for (const [code, source] of Object.entries(probes)) {
			writeFileSync(join(dir, 'src', 'probe.lua'), source);
			const result = run();
			assert.ifError(result.error);
			assert.equal(result.status, 1, code);
			assert.match(result.stdout + result.stderr, new RegExp(`\\(${code}\\)`));
		}
		writeFileSync(
			join(dir, 'src', 'probe.lua'),
			'---@param value string Input value.\n---@return string result Input value.\nlocal function f(value) return value end\n'
		);
		const documented = run();
		assert.ifError(documented.error);
		assert.equal(documented.status, 0, documented.stdout + documented.stderr);
		rmSync(join(dir, 'src', 'probe.lua'));
		mkdirSync(join(dir, 'tests', 'pure'), { recursive: true });
		writeFileSync(join(dir, 'tests', 'pure', 'probe.lua'), probes['undefined-global']);
		const pure = run();
		assert.ifError(pure.error);
		assert.equal(pure.status, 1, pure.stdout + pure.stderr);
		assert.match(pure.stdout + pure.stderr, /undefined-global/);
		rmSync(join(dir, 'tests', 'pure', 'probe.lua'));
		mkdirSync(join(dir, 'src', 'fonts', 'data'), { recursive: true });
		mkdirSync(join(dir, 'scripts'), { recursive: true });
		for (const path of ['src/core/version.lua', 'src/fonts/data/generated.lua', 'scripts/ignored.lua']) {
			writeFileSync(join(dir, path), probes['undefined-global']);
		}
		const ignored = run();
		assert.ifError(ignored.error);
		assert.equal(ignored.status, 0, ignored.stdout + ignored.stderr);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
