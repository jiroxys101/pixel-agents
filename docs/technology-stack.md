# Technology Stack — PixelOffice

_Generated: 2026-03-12 | Project: PixelOffice v1.0.2 | Scan: Exhaustive_

## Overview

PixelOffice is a multi-part VS Code extension composed of two compiled TypeScript parts (extension host + React webview) and an offline asset processing pipeline. The extension host runs in Node.js under the VS Code Extension Host; the webview runs in a sandboxed browser context.

---

## Technology Table

| Category | Technology | Version | Justification |
|---|---|---|---|
| **VS Code API** | WebviewViewProvider | ^1.107.0 | Panel-area webview, terminal management, workspace state, commands |
| **Extension Runtime** | Node.js / CommonJS | ES2022 | Extension Host platform; esbuild targets CJS format, external: vscode |
| **Extension Build** | esbuild | ^0.27.2 | Single-file bundle with custom problem-matcher plugin, watch mode, asset copy |
| **Language** | TypeScript | ^5.9.3 | Strict mode, `verbatimModuleSyntax`, `noUnusedLocals/Params`, no `enum` (erasable syntax only) |
| **PNG Parsing** | pngjs | ^7.0.0 | RGBA buffer from PNG files for sprite conversion (alpha threshold = 128) |
| **Anthropic SDK** | @anthropic-ai/sdk | ^0.74.0 | Used by asset pipeline scripts (`3-vision-inspect.ts`) for Claude vision API calls |
| **Webview Framework** | React | ^19.2.0 | Composition root (App.tsx), functional components, hooks for state |
| **Webview Build** | Vite | ^7.2.4 | ES module output, base: `'./'` for webview path isolation, asset copying |
| **Vite Plugin** | @vitejs/plugin-react | ^5.1.1 | JSX/TSX transform, React Fast Refresh |
| **Canvas Rendering** | HTML5 Canvas 2D | Browser | Pixel-perfect rendering; `imageSmoothingEnabled: false`; no `ctx.scale()` |
| **Audio** | Web Audio API / AudioContext | Browser | Sine-wave oscillators for notification chime (E5→E6, 659.25Hz→1318.51Hz) |
| **Animation** | requestAnimationFrame | Browser | 60 FPS game loop; delta-time capping at `MAX_DELTA_TIME_SEC = 0.1s` |
| **File Watching** | fs.watch + fs.watchFile + polling | Node.js | Triple-layer watchdog: `fs.watch` (primary), `fs.watchFile` (1s polling), manual interval (1s) |
| **Linting** | ESLint | ^9.39.2 | `typescript-eslint` + `simple-import-sort`; separate configs for `src/` and `webview-ui/` |
| **Formatting** | Prettier | ^3.8.1 | 2-space indent, 100-col, single-quote; applied to TS, TSX, CSS, JS, JSON, MD |
| **Git Hooks** | Husky | ^9.1.7 | Pre-commit hook runs lint-staged |
| **Staged Linting** | lint-staged | ^16.3.2 | Lint+format only changed files before commit |
| **Script Runner** | tsx | ^4.21.0 | Runtime TypeScript execution for asset pipeline scripts (no compile step) |
| **Pixel Font** | FS Pixel Sans Unicode | Custom TTF | Pixel-art aesthetic; loaded via `@font-face` in `index.css`; applied globally |
| **Package Manager** | npm | LTS | Root and webview-ui are separate npm workspaces (not linked, separate node_modules) |

---

## Part-Level Tech Summary

### Part 1 — Extension Host (`src/`)

| Item | Value |
|---|---|
| Language | TypeScript |
| Module System | CommonJS (esbuild output) |
| Target | ES2022 |
| Entry Point | `src/extension.ts` → `activate()` / `deactivate()` |
| Output | `dist/extension.js` |
| Key APIs | `vscode.window.createWebviewPanel`, `vscode.window.createTerminal`, `vscode.workspace.fs`, `fs.watch`, `fs.watchFile` |
| Key Deps | `pngjs`, `@anthropic-ai/sdk`, `@types/vscode` |

### Part 2 — Webview Frontend (`webview-ui/`)

| Item | Value |
|---|---|
| Language | TypeScript + React (TSX) |
| Module System | ES Modules |
| Target | ES2022 / Browser |
| Entry Point | `src/main.tsx` |
| Output | `../dist/webview/` |
| Key APIs | `Canvas 2D`, `requestAnimationFrame`, `AudioContext`, `acquireVsCodeApi()` |
| Key Deps | `react@19`, `react-dom@19`, Vite, TypeScript |

### Part 3 — Asset Pipeline (`scripts/`)

| Item | Value |
|---|---|
| Language | TypeScript / JavaScript |
| Runner | `tsx` (runtime execution, no compile step) |
| Key Scripts | `1-detect-assets.ts` (flood-fill), `3-vision-inspect.ts` (Claude vision), `5-export-assets.ts` (PNG export + catalog), `export-characters.ts` (character baking) |
| Output | `webview-ui/public/assets/` (PNGs + `furniture-catalog.json`) |
| Key Deps | `@anthropic-ai/sdk`, `pngjs`, `tsx` |

---

## Key Library Details

### pngjs (Extension Host)
- Used in `assetLoader.ts` to parse PNG → RGBA buffer
- Alpha threshold: pixel with `alpha >= 128` → opaque, else transparent
- SpriteData is a `string[][]` (2D array of hex colors `"#RRGGBB"` or `""`)
- All 6 character PNGs, floors.png, walls.png processed this way

### Web Audio API (Webview)
- `notificationSound.ts` creates oscillator nodes for notification chimes
- AudioContext starts suspended in webview; unlocked on first canvas `mousedown`
- Two-note ascending chime: E5 (659.25 Hz) → E6 (1318.51 Hz), 0.18s each, volume 0.14
- Toggle state persisted in extension `globalState` key `pixel-agents.soundEnabled`

### Canvas 2D Rendering (Webview)
- No `ctx.scale(devicePixelRatio)` — zoom is managed as integer device-pixels-per-sprite-pixel
- Default zoom: `Math.round(2 * devicePixelRatio)`
- All sprites drawn with `drawImage()` at pixel-aligned coordinates
- Z-sort: all entities (furniture + characters + walls) sorted by `zY` before each frame
- Off-screen canvas caching: sprites pre-rendered to `OffscreenCanvas`, cached in `WeakMap` keyed by zoom level

---

## Build Commands

```sh
# Full build (type-check → lint → esbuild → vite)
npm run build

# Development watch (parallel: esbuild watch + tsc noEmit watch + vite)
npm run watch

# Type check only
npm run check-types

# Lint
npm run lint             # extension backend
npm run lint:webview     # webview frontend

# Format
npm run format           # all files

# Asset pipeline
npm run import-tileset   # tsx scripts/0-import-tileset.ts
```

---

## TypeScript Constraints (Project-Wide)

| Constraint | Config | Impact |
|---|---|---|
| No `enum` | `erasableSyntaxOnly` | Use `as const` objects instead |
| `import type` required | `verbatimModuleSyntax` | Type-only imports must use `import type` |
| No unused locals | `noUnusedLocals: true` | Dead code caught at compile time |
| No unused params | `noUnusedParameters: true` | Prefix with `_` if intentionally unused |
| Strict mode | `strict: true` | Null checks, strict function types, no implicit any |
