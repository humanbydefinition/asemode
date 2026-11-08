import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { publish, publishSubset } from './publish.mjs';
import { parseCliArgs, resolveFilter } from './manifest.mjs';

const currentDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(currentDir, '../..');
const script = join(currentDir, 'capture.lua');
const executable = process.env.ASEPRITE_PATH || '/Applications/Aseprite.app/Contents/MacOS/aseprite';
const binary = executable.endsWith('/bin') ? join(executable, 'aseprite') : executable;

/**
 * Recursively collect all `.lua` files inside a directory for Aseprite `[script_access]` pre-authorization.
 * @param {string} directory Directory path to scan.
 * @returns {Promise<string[]>} Absolute paths to `.lua` files.
 */
async function collectLuaFiles(directory) {
	const entries = await readdir(directory, { withFileTypes: true });
	const files = [];
	for (const entry of entries) {
		const fullPath = join(directory, entry.name);
		if (entry.isDirectory()) {
			files.push(...(await collectLuaFiles(fullPath)));
		} else if (entry.isFile() && entry.name.endsWith('.lua')) {
			files.push(fullPath);
		}
	}
	return files;
}

/**
 * Capture a theme in an isolated Aseprite profile.
 * @param {string} theme Theme to capture.
 * @param {string} temp Temporary capture directory.
 * @param {{ suites: string[], onlyIds: string[] }} plan Execution plan for suites and screenshot IDs.
 * @returns {Promise<void>} Resolves when the capture finishes.
 */
async function run(theme, temp, plan) {
	const profile = join(temp, `profile-${theme}`);
	const output = join(temp, theme);
	await mkdir(profile);
	await mkdir(output);
	const authorizedFiles = [...(await collectLuaFiles(currentDir)), join(root, 'src/core/util.lua')];
	const permissions = authorizedFiles
		.map((path) => `${createHash('sha1').update(path).digest('hex')} = 6`)
		.join('\n');
	await writeFile(
		join(profile, 'aseprite.ini'),
		`[theme]\nselected = ${theme === 'dark' ? 'default-dark' : 'default'}\n\n[script_access]\n${permissions}\n`
	);
	const args = [
		'--script-param',
		`root=${root}`,
		'--script-param',
		`output=${output}`,
		'--script-param',
		`theme=${theme}`,
		'--script-param',
		`suites=${plan.suites.join(',')}`,
	];
	if (plan.onlyIds.length > 0) {
		args.push('--script-param', `only=${plan.onlyIds.join(',')}`);
	}
	args.push('--script', script);
	const child = spawn(binary, args, {
		cwd: root,
		env: { ...process.env, ASEPRITE_USER_FOLDER: profile },
		stdio: 'inherit',
	});
	let exited;
	child.on('exit', (code) => {
		exited = code ?? -1;
	});
	child.on('error', () => {
		exited = -1;
	});
	const deadline = Date.now() + 180000;
	try {
		while (Date.now() < deadline) {
			await new Promise((done) => setTimeout(done, 300));
			try {
				throw new Error(await readFile(join(output, 'error'), 'utf8'));
			} catch (error) {
				if (error.code !== 'ENOENT') throw error;
			}
			try {
				await access(join(output, 'done'));
				return;
			} catch (error) {
				if (error.code !== 'ENOENT') throw error;
			}
			if (exited !== undefined) throw new Error(`Aseprite exited before capture finished (${exited})`);
		}
		let lastStep = 'none';
		try {
			lastStep = await readFile(join(output, 'progress'), 'utf8');
		} catch {
			// Ignore missing progress file.
		}
		throw new Error(
			`Timed out capturing ${theme} theme (last step: ${lastStep}). Check Aseprite for a dialog or permission request.`
		);
	} finally {
		if (exited === undefined) child.kill('SIGTERM');
	}
}

/**
 * Capture and publish all configured themes (or a CLI-filtered subset).
 * @returns {Promise<void>} Resolves when publishing finishes.
 */
async function main() {
	if (process.platform !== 'darwin') throw new Error('Screenshot generation requires a macOS graphical session.');
	const plan = resolveFilter(parseCliArgs(process.argv.slice(2)));
	await access(binary, constants.X_OK);
	const temp = await mkdtemp(join(tmpdir(), 'asemode-captures-'));
	try {
		for (const theme of plan.themes) {
			const scope = plan.isFiltered
				? ` (${plan.screenshots.length} screenshot(s) across suite(s): ${plan.suites.join(', ')})`
				: '';
			console.log(`Capturing ${theme} theme${scope}...`);
			await run(theme, temp, plan);
		}
		if (plan.isFiltered) {
			await publishSubset(temp, plan);
			console.log(
				`Updated ${plan.screenshots.length} screenshot(s) for [${plan.themes.join(', ')}] in docs/images/screenshots.`
			);
		} else {
			await publish(temp);
			console.log('Screenshots published to docs/images/screenshots.');
		}
	} finally {
		await rm(temp, { recursive: true, force: true });
	}
}
main().catch((error) => {
	console.error(error.message);
	process.exitCode = 1;
});
