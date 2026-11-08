import jsdoc from 'eslint-plugin-jsdoc';

export default [
	{
		files: ['scripts/**/*.mjs', 'tests/node/**/*.mjs', 'release.config.cjs'],
		plugins: { jsdoc },
		rules: {
			'jsdoc/require-jsdoc': [
				'error',
				{
					require: { FunctionDeclaration: true },
					contexts: [
						'VariableDeclaration > VariableDeclarator > ArrowFunctionExpression',
						'VariableDeclaration > VariableDeclarator > FunctionExpression',
					],
				},
			],
			'jsdoc/check-param-names': 'error',
			'jsdoc/check-types': 'error',
			'jsdoc/require-description': 'error',
			'jsdoc/require-param': 'error',
			'jsdoc/require-param-description': 'error',
			'jsdoc/require-param-type': 'error',
			'jsdoc/require-returns': ['error', { forceRequireReturn: true, forceReturnsWithAsync: true }],
			'jsdoc/require-returns-description': 'error',
			'jsdoc/require-returns-type': 'error',
		},
	},
];
