const { createDefaultEsmPreset } = require('ts-jest');

const tsJestTransformCfg = createDefaultEsmPreset().transform;

/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.spec.ts'],
  extensionsToTreatAsEsm: ['.ts'],
  transform: tsJestTransformCfg,
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
};
