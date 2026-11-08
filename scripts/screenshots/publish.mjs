import { readFile, mkdir, mkdtemp, cp, rename, rm, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { categories, resolveEntryTitle, screenshotEntries, screenshots, themes } from './manifest.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

/**
 * Convert a Markdown heading title into a GitHub-compatible anchor slug.
 * @param {string} title Heading text.
 * @returns {string} Anchor slug.
 */
function slugifyHeading(title) {
	return title
		.toLowerCase()
		.replace(/[^\w\s-]/g, '')
		.replace(/\s+/g, '-');
}

/**
 * Read runtime-introspected dialog/tab/loading/alert titles emitted by `lib/harness.lua`.
 * @param {string} source Capture directory.
 * @param {string[]} [targetThemes] Themes to inspect.
 * @returns {Promise<Record<string, string>>} Resolved title map keyed by screenshot ID.
 */
async function readCapturedTitles(source, targetThemes = themes) {
	const merged = {};
	for (const theme of targetThemes) {
		try {
			const raw = await readFile(join(source, theme, 'titles.json'), 'utf8');
			const parsed = JSON.parse(raw);
			for (const [id, title] of Object.entries(parsed)) {
				if (merged[id] && merged[id] !== title) {
					throw new Error(
						`Inconsistent runtime title for ${id} across themes: "${merged[id]}" vs "${title}"`
					);
				}
				merged[id] = title;
			}
		} catch (error) {
			if (error.code !== 'ENOENT') throw error;
		}
	}
	return merged;
}

/**
 * Validate a capture set before touching the published images.
 * @param {string} source Directory containing themed PNG captures.
 * @param {{ themes?: string[], screenshots?: Array<[string, string]> }} [selection] Optional subset to validate.
 * @returns {Promise<void>} Resolves when all captures pass validation.
 * @throws {Error} If a capture is missing, has an invalid PNG header, or duplicates another capture in the same theme.
 */
export async function validateCaptures(source, selection = {}) {
	const targetThemes = selection.themes ?? themes;
	const targetScreenshots = selection.screenshots ?? screenshots;
	for (const theme of targetThemes) {
		const seen = new Map();
		for (const [id] of targetScreenshots) {
			const path = join(source, theme, `${id}.png`);
			let bytes;
			try {
				bytes = await readFile(path);
			} catch (error) {
				throw new Error(`Cannot read screenshot ${path}: ${error.message}`);
			}
			if (
				bytes.length < 33 ||
				!bytes.subarray(0, 8).equals(signature) ||
				bytes.toString('ascii', 12, 16) !== 'IHDR' ||
				!bytes.readUInt32BE(16) ||
				!bytes.readUInt32BE(20)
			) {
				throw new Error(`Invalid PNG screenshot: ${path}`);
			}
			const digest = createHash('sha256').update(bytes).digest('hex');
			const duplicate = seen.get(digest);
			if (duplicate) {
				throw new Error(`Duplicate PNG screenshot in ${theme} theme: ${id}.png matches ${duplicate}.png`);
			}
			seen.set(digest, id);
		}
	}
}

/**
 * Render the categorized Markdown screenshot gallery with a Table of Contents.
 * @param {Record<string, string>} [runtimeTitles] Live titles introspected from `src/ui/` at capture time.
 * @returns {string} Gallery Markdown.
 */
export function gallery(runtimeTitles = {}) {
	const lines = [
		'# Asemode screenshots',
		'',
		'Screenshots of Asemode panels, dialogs, transient loading states, warning variants, and modal alerts in the default Aseprite light and dark themes.',
		'',
		'## Contents',
		'',
	];
	for (const category of categories) {
		lines.push(`- [${category.title}](#${slugifyHeading(category.title)})`);
	}
	lines.push('');

	for (const category of categories) {
		const items = screenshotEntries.filter((entry) => entry.category === category.id);
		if (items.length === 0) continue;
		lines.push(`## ${category.title}`, '', category.description, '');
		for (const entry of items) {
			const title = resolveEntryTitle(entry, runtimeTitles);
			lines.push(
				`### ${title}`,
				'',
				'| Light | Dark |',
				'| --- | --- |',
				`| ![${title}, light theme](images/screenshots/light/${entry.id}.png) | ![${title}, dark theme](images/screenshots/dark/${entry.id}.png) |`,
				''
			);
		}
	}
	return lines.join('\n');
}

/**
 * Publish a validated screenshot set and restore the old set if replacement fails.
 * @param {string} source Directory containing themed PNG captures.
 * @param {string} [docs] Documentation directory. Defaults to the project docs directory.
 * @returns {Promise<void>} Resolves when the images and gallery are published.
 */
export async function publish(source, docs = join(root, 'docs')) {
	await validateCaptures(source);
	const runtimeTitles = await readCapturedTitles(source, themes);
	const images = join(docs, 'images');
	await mkdir(images, { recursive: true });
	const staging = await mkdtemp(join(images, '.screenshots-'));
	const target = join(images, 'screenshots');
	const backup = join(staging, 'previous');
	const next = join(staging, 'next');
	let old = false;
	try {
		await mkdir(next);
		for (const theme of themes) {
			await mkdir(join(next, theme));
			for (const [id] of screenshots) await cp(join(source, theme, `${id}.png`), join(next, theme, `${id}.png`));
		}
		await writeFile(join(staging, 'gallery.md'), gallery(runtimeTitles));
		try {
			await rename(target, backup);
			old = true;
		} catch (error) {
			if (error.code !== 'ENOENT') throw error;
		}
		try {
			await rename(next, target);
			await rename(join(staging, 'gallery.md'), join(docs, 'SCREENSHOTS.md'));
		} catch (error) {
			await rm(target, { recursive: true, force: true });
			if (old) await rename(backup, target);
			throw error;
		}
	} finally {
		await rm(staging, { recursive: true, force: true });
	}
}

/**
 * Validate and copy a filtered subset of screenshots into the documentation folder.
 * @param {string} source Directory containing themed PNG captures.
 * @param {{ themes: string[], screenshots: Array<[string, string]> }} selection Filtered selection to publish.
 * @param {string} [docs] Documentation directory. Defaults to the project docs directory.
 * @returns {Promise<void>} Resolves when the selected images are updated.
 */
export async function publishSubset(source, selection, docs = join(root, 'docs')) {
	await validateCaptures(source, selection);
	await readCapturedTitles(source, selection.themes);
	const target = join(docs, 'images/screenshots');
	for (const theme of selection.themes) {
		await mkdir(join(target, theme), { recursive: true });
		for (const [id] of selection.screenshots) {
			await cp(join(source, theme, `${id}.png`), join(target, theme, `${id}.png`));
		}
	}
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	if (!process.argv[2]) {
		console.error('Usage: node scripts/screenshots/publish.mjs <capture-directory>');
		process.exitCode = 1;
	} else {
		publish(resolve(process.argv[2])).catch((error) => {
			console.error(error.message);
			process.exitCode = 1;
		});
	}
}
