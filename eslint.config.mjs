import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import prettierConfig from "eslint-config-prettier";

export default tseslint.config(
  // Global ignores
  {
    ignores: [
      "node_modules/**",
      "public/**",
      "vendor/**",
      "tmp/**",
      "log/**",
      "storage/**",
      "*.d.ts",
      "app/frontend/components/ui/**",
    ],
  },

  // Base JS + TypeScript recommended rules
  js.configs.recommended,
  ...tseslint.configs.recommended,

  // React JSX rules (flat config presets)
  {
    files: ["**/*.{jsx,tsx}"],
    ...react.configs.flat.recommended,
    ...react.configs.flat["jsx-runtime"],
    settings: { react: { version: "detect" } },
    rules: {
      ...react.configs.flat.recommended.rules,
      ...react.configs.flat["jsx-runtime"].rules,
      "react/prop-types": "off",
      "react/no-unescaped-entities": "off",
      "react/no-unknown-property": ["error", { ignore: ["head-key"] }],
    },
  },

  // React Hooks (official React team plugin, includes React Compiler rules)
  {
    files: ["**/*.{jsx,tsx}"],
    ...reactHooks.configs.flat.recommended,
  },

  // React Refresh (essential for Vite HMR)
  {
    files: ["**/*.{jsx,tsx}"],
    ...reactRefresh.configs.vite,
    rules: {
      ...reactRefresh.configs.vite.rules,
      "react-refresh/only-export-components": [
        "warn",
        { allowConstantExport: true },
      ],
    },
  },

  // TypeScript-specific rules
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      globals: globals.browser,
    },
    rules: {
      "@typescript-eslint/no-unused-vars": ["warn", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/consistent-type-imports": ["error", { prefer: "type-imports", fixStyle: "inline-type-imports" }],
    },
  },

  // Disable ESLint rules that conflict with Prettier (Prettier runs separately)
  prettierConfig,

  // Console warnings
  {
    files: ["**/*.{js,jsx,ts,tsx}"],
    rules: { "no-console": ["warn", { allow: ["warn", "error"] }] },
  },
);
