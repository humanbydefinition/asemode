import { spawnSync } from 'node:child_process';

const executable = process.env.LUA_LANGUAGE_SERVER || 'lua-language-server';
const result = spawnSync(
	executable,
	['--check=.', '--checklevel=Error', '--configpath=.luarc.ci.json', '--logpath=.test-output/luals'],
	{ stdio: 'inherit' }
);
if (result.error) {
	console.error(`Could not start Lua Language Server: ${result.error.message}`);
	process.exitCode = 1;
} else {
	process.exitCode = result.status ?? 1;
}
