/**
 * ESLint 9 flat config
 * - 通过 FlatCompat 复用 eslint-config-expo（传统 eslintrc 格式）
 * - 启用 eslint-plugin-react-hooks：rules-of-hooks(error) + exhaustive-deps(warn)
 */
import { FlatCompat } from '@eslint/eslintrc';
import reactHooks from 'eslint-plugin-react-hooks';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const compat = new FlatCompat({ baseDirectory: __dirname });

export default [
  {
    ignores: [
      'node_modules/**',
      'android/**',
      '.expo/**',
      'assets/**',
    ],
  },
  ...compat.extends('expo'),
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    plugins: {
      'react-hooks': reactHooks,
    },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      // React Compiler 级规则对本项目大量误报/需大规模重构，暂不启用：
      // - refs：RN 官方惯用法 useRef(new Animated.Value()).current 会被误报
      // - set-state-in-effect：数据拉取/loading 重置等既有模式需要架构级重构
      'react-hooks/refs': 'off',
      'react-hooks/set-state-in-effect': 'off',
    },
  },
];
