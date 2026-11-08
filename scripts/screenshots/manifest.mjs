import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const catalogPath = join(dirname(fileURLToPath(import.meta.url)), 'catalog.json');

/**
 * Declarative screenshot catalog loaded from `catalog.json`.
 * @type {{
 *   themes: string[],
 *   categories: Array<{ id: string, title: string, description: string }>,
 *   screenshots: Array<{
 *     id: string,
 *     category: string,
 *     suite: string,
 *     kind: string,
 *     variant?: string,
 *     includeTab?: boolean,
 *     command?: string,
 *     params?: Record<string, string>
 *   }>
 * }}
 */
export const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));

/** Supported Aseprite themes for documentation screenshots. */
export const themes = catalog.themes;

/** Logical documentation categories for grouping screenshots in `docs/SCREENSHOTS.md`. */
export const categories = catalog.categories;

/** Structured screenshot definitions from `catalog.json`. */
export const screenshotEntries = catalog.screenshots;

/** Ordered list of unique Lua capture suites. */
export const suites = [...new Set(screenshotEntries.map((entry) => entry.suite))];

/**
 * Resolve a screenshot's display title from live runtime titles or derive a fallback label.
 * @param {{ id: string, kind: string, variant?: string }} entry Catalog screenshot entry.
 * @param {Record<string, string>} [runtimeTitles] Live titles introspected from `src/ui/` at capture time.
 * @returns {string} Display title.
 */
export function resolveEntryTitle(entry, runtimeTitles = {}) {
	if (runtimeTitles && typeof runtimeTitles[entry.id] === 'string' && runtimeTitles[entry.id] !== '') {
		return runtimeTitles[entry.id];
	}
	const words = entry.id
		.replace(/^(loading|alert)-/, '')
		.split('-')
		.map((word, index) => (index === 0 ? word.charAt(0).toUpperCase() + word.slice(1) : word))
		.join(' ');
	if (entry.kind === 'loading') {
		return `Loading: ${words}`;
	}
	if (entry.kind === 'alert') {
		return `Alert: ${entry.variant || words}`;
	}
	return entry.variant ? `${words}: ${entry.variant}` : words;
}

/** Dialogs, panels, loading states, warning variants, and alerts as `[id, title]` pairs. */
export const screenshots = screenshotEntries.map((entry) => [entry.id, resolveEntryTitle(entry)]);

/**
 * Split a comma-separated CLI flag value into trimmed non-empty tokens.
 * @param {string} value Raw argument value.
 * @returns {string[]} Parsed tokens.
 */
function splitCsv(value) {
	return String(value)
		.split(',')
		.map((token) => token.trim())
		.filter(Boolean);
}

/**
 * Parse CLI arguments for `generate.mjs` (`--suite`, `--only`, `--theme`).
 * @param {string[]} [argv] Raw CLI arguments after the script name.
 * @returns {{ suites: string[], only: string[], themes: string[] }} Parsed filter options.
 */
export function parseCliArgs(argv = []) {
	const parsed = { suites: [], only: [], themes: [] };
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === '--') continue;
		const [flag, inlineValue] = arg.startsWith('--') ? arg.split('=', 2) : [arg, undefined];
		/**
		 * Read the value of a flag from either `--flag=value` or the next positional argument.
		 * @returns {string} Flag value.
		 */
		const readValue = () => {
			if (inlineValue !== undefined && inlineValue !== '') return inlineValue;
			const next = argv[i + 1];
			if (!next || next.startsWith('--')) {
				throw new Error(`Missing value for ${flag}`);
			}
			i++;
			return next;
		};
		if (flag === '--suite' || flag === '--suites' || flag === '--category') {
			parsed.suites.push(...splitCsv(readValue()));
		} else if (flag === '--only' || flag === '--id' || flag === '--filter') {
			parsed.only.push(...splitCsv(readValue()));
		} else if (flag === '--theme' || flag === '--themes') {
			parsed.themes.push(...splitCsv(readValue()));
		} else {
			throw new Error(
				`Unknown argument: ${arg}. Supported flags: --suite=<name>, --only=<id>, --theme=<light|dark>`
			);
		}
	}
	return parsed;
}

/**
 * Validate and resolve CLI filter options against the screenshot catalog.
 * @param {{ suites?: string[], only?: string[], themes?: string[] }} [options] Filter options.
 * @returns {{
 *   isFiltered: boolean,
 *   themes: string[],
 *   suites: string[],
 *   onlyIds: string[],
 *   screenshots: Array<[string, string]>
 * }} Resolved execution plan.
 */
export function resolveFilter(options = {}) {
	const requestedThemes = options.themes?.length ? options.themes : themes;
	for (const theme of requestedThemes) {
		if (!themes.includes(theme)) {
			throw new Error(`Unknown theme "${theme}". Valid themes: ${themes.join(', ')}`);
		}
	}

	const validSuites = new Set([...suites, ...categories.map((cat) => cat.id)]);
	const requestedSuites = options.suites ?? [];
	for (const suite of requestedSuites) {
		if (!validSuites.has(suite)) {
			throw new Error(`Unknown suite "${suite}". Valid suites: ${suites.join(', ')}`);
		}
	}

	const byId = new Map(screenshotEntries.map((entry) => [entry.id, entry]));
	const requestedOnly = options.only ?? [];
	for (const id of requestedOnly) {
		if (!byId.has(id)) {
			throw new Error(`Unknown screenshot id "${id}".`);
		}
	}

	const hasSuiteFilter = requestedSuites.length > 0;
	const hasOnlyFilter = requestedOnly.length > 0;
	const isFiltered =
		hasSuiteFilter ||
		hasOnlyFilter ||
		requestedThemes.length !== themes.length ||
		requestedThemes.some((theme, index) => theme !== themes[index]);

	const suiteSet = new Set(requestedSuites);
	const onlySet = new Set(requestedOnly);
	const selectedEntries = screenshotEntries.filter((entry) => {
		const matchesSuite = !hasSuiteFilter || suiteSet.has(entry.suite) || suiteSet.has(entry.category);
		const matchesOnly = !hasOnlyFilter || onlySet.has(entry.id);
		return matchesSuite && matchesOnly;
	});

	if (selectedEntries.length === 0) {
		throw new Error('No screenshots matched the provided --suite and --only filters.');
	}

	const activeSuites = suites.filter((suite) => selectedEntries.some((entry) => entry.suite === suite));
	const onlyIds = isFiltered ? selectedEntries.map((entry) => entry.id) : [];

	return {
		isFiltered,
		themes: requestedThemes,
		suites: activeSuites,
		onlyIds,
		screenshots: selectedEntries.map((entry) => [entry.id, resolveEntryTitle(entry)]),
	};
}
