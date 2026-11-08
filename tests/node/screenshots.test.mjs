import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
	categories,
	parseCliArgs,
	resolveFilter,
	screenshotEntries,
	screenshots,
	suites,
	themes,
} from '../../scripts/screenshots/manifest.mjs';
import { gallery, publish, publishSubset } from '../../scripts/screenshots/publish.mjs';

/**
 * Create a distinct minimal PNG header buffer for a given screenshot index.
 * @param {number} index Screenshot index (1-based).
 * @returns {Buffer} Minimal valid PNG buffer.
 */
function makePng(index) {
	const png = Buffer.alloc(33);
	Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png);
	png.write('IHDR', 12);
	png.writeUInt32BE(index + 1, 16);
	png.writeUInt32BE(3, 20);
	return png;
}

test('catalog.json defines valid categories, suites, and unique screenshot IDs without hardcoded titles', () => {
	assert.deepEqual(themes, ['light', 'dark']);
	assert.equal(categories.length, 6);
	assert.equal(suites.length, 6);
	assert.equal(screenshots.length, 59);

	const categoryIds = new Set(categories.map((cat) => cat.id));
	const seenIds = new Set();
	for (const entry of screenshotEntries) {
		assert.ok(!seenIds.has(entry.id), `Duplicate screenshot id: ${entry.id}`);
		seenIds.add(entry.id);
		assert.equal(entry.title, undefined, `Hardcoded title should not exist in catalog.json for ${entry.id}`);
		assert.ok(categoryIds.has(entry.category), `Unknown category ${entry.category} for ${entry.id}`);
		assert.ok(['dialog', 'loading', 'alert'].includes(entry.kind), `Invalid kind ${entry.kind} for ${entry.id}`);
	}

	const rendered = gallery({ export: 'Export Textmode Document' });
	assert.match(rendered, /## Contents/);
	assert.match(rendered, /### Export Textmode Document/);
	for (const category of categories) {
		assert.ok(rendered.includes(`## ${category.title}`), `Missing category heading ${category.title}`);
	}
});

test('parseCliArgs and resolveFilter resolve suite, only, and theme filters', () => {
	const parsed = parseCliArgs(['--suite=fonts,portable', '--only', 'font-upload,import-json', '--theme=dark']);
	assert.deepEqual(parsed, {
		suites: ['fonts', 'portable'],
		only: ['font-upload', 'import-json'],
		themes: ['dark'],
	});

	const plan = resolveFilter(parsed);
	assert.equal(plan.isFiltered, true);
	assert.deepEqual(plan.themes, ['dark']);
	assert.deepEqual(plan.suites, ['fonts', 'portable']);
	assert.deepEqual(plan.onlyIds, ['font-upload', 'import-json']);

	const alertsPlan = resolveFilter(parseCliArgs(['--suite=alerts']));
	assert.equal(alertsPlan.isFiltered, true);
	assert.equal(alertsPlan.onlyIds.length, 16);
	assert.deepEqual(alertsPlan.suites, ['document-grid', 'fonts', 'alerts']);

	assert.throws(() => resolveFilter({ suites: ['unknown-suite'] }), /Unknown suite/);
	assert.throws(() => resolveFilter({ only: ['unknown-id'] }), /Unknown screenshot id/);
	assert.throws(() => resolveFilter({ themes: ['sepia'] }), /Unknown theme/);
});

test('publishes complete themed sets with introspected runtime titles, supports subset updates, and preserves published images on error', async () => {
	const temp = await mkdtemp(join(tmpdir(), 'asemode-screenshots-'));
	try {
		const captures = join(temp, 'captures');
		const docs = join(temp, 'docs');
		const runtimeTitles = { asemode: 'Asemode', export: 'Export Textmode Document' };
		for (const theme of themes) {
			await mkdir(join(captures, theme), { recursive: true });
			await writeFile(join(captures, theme, 'titles.json'), JSON.stringify(runtimeTitles));
			for (let i = 0; i < screenshots.length; i++) {
				const [id] = screenshots[i];
				await writeFile(join(captures, theme, `${id}.png`), makePng(i + 1));
			}
		}
		await publish(captures, docs);
		assert.equal(await readFile(join(docs, 'SCREENSHOTS.md'), 'utf8'), gallery(runtimeTitles));
		const output = join(docs, 'images/screenshots/light/asemode.png');
		assert.deepEqual(await readFile(output), makePng(1));

		// Subset update test
		const subsetSource = join(temp, 'subset');
		await mkdir(join(subsetSource, 'dark'), { recursive: true });
		await writeFile(join(subsetSource, 'dark/font-upload.png'), makePng(999));
		const subsetPlan = resolveFilter(parseCliArgs(['--only=font-upload', '--theme=dark']));
		await publishSubset(subsetSource, subsetPlan, docs);
		assert.deepEqual(await readFile(join(docs, 'images/screenshots/dark/font-upload.png')), makePng(999));

		// Duplicate and missing image rejection tests
		await writeFile(join(captures, 'dark/font-upload.png'), makePng(1));
		await assert.rejects(publish(captures, docs), /Duplicate PNG screenshot/);
		await rm(join(captures, 'dark/asemode.png'));
		await assert.rejects(publish(captures, docs), /Cannot read screenshot/);
		assert.deepEqual(await readFile(output), makePng(1));
	} finally {
		await rm(temp, { recursive: true, force: true });
	}
});
