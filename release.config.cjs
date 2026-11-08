module.exports = {
	branches: ['main'],
	tagFormat: 'v${version}',
	plugins: [
		[
			'@semantic-release/commit-analyzer',
			{
				releaseRules: [
					{ type: 'feat', release: 'minor' },
					{ type: 'fix', release: 'patch' },
					{ type: 'perf', release: 'patch' },
					{ type: 'refactor', release: 'patch' },
					{ type: 'docs', release: false },
					{ type: 'style', release: false },
					{ type: 'test', release: false },
					{ type: 'chore', release: false },
					{ breaking: true, release: 'major' },
				],
			},
		],
		'@semantic-release/release-notes-generator',
		['@semantic-release/npm', { npmPublish: false }],
		['@semantic-release/exec', { prepareCmd: 'npm run build && npm run test:package' }],
		[
			'@semantic-release/git',
			{
				assets: ['package.json', 'package-lock.json', 'src/core/version.lua'],
				message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
			},
		],
		[
			'@semantic-release/github',
			{
				draftRelease: true,
				successComment: false,
				failComment: false,
				releasedLabels: false,
			},
		],
	],
};
