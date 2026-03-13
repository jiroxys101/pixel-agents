---
project_name: 'PixelOffice'
user_name: 'Rijul'
date: '2026-03-12'
sections_completed:
  ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules', 'anti_patterns']
status: 'complete'
rule_count: 47
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

### Extension (Node.js / VS Code Extension Host)
- TypeScript 5.9.x — `module: Node16`, `target: ES2022`, `strict: true`
- VS Code API ^1.107.0 — `WebviewViewProvider` (panel area, not WebviewPanel)
- pngjs 7.0.0 — PNG → RGBA buffer parsing; alpha threshold 128 for opaque detection
- @anthropic-ai/sdk 0.74.0 — Claude API (dev dependency, used in asset scripts only)
- esbuild 0.27.x — bundles `src/` → `dist/extension.js`

### Webview (React SPA)
- TypeScript ~5.9.3 — `module: ESNext`, `verbatimModuleSyntax: true`, `erasableSyntaxOnly: true`, `noUnusedLocals/Parameters: true`
- React 19.2.0 + react-dom 19.2.0
- Vite 7.2.x — builds `webview-ui/src/` → `dist/webview-ui/`

### Tooling
- ESLint 9.x (flat config, `eslint.config.mjs`) + typescript-eslint 8.x + simple-import-sort
- Prettier 3.8.x — singleQuote, tabWidth: 2, trailingComma: all, printWidth: 100, endOfLine: lf
- husky 9.x + lint-staged — pre-commit auto-fix + format

## Critical Implementation Rules

### Language-Specific Rules

#### TypeScript — Both Contexts
- **No enums** — `erasableSyntaxOnly: true` forbids them. Use `as const` objects instead:
  `const FOO = { A: 'a', B: 'b' } as const; type Foo = typeof FOO[keyof typeof FOO];`
- **`import type` required** for type-only imports — `verbatimModuleSyntax: true` enforces this.
  Wrong: `import { SomeType } from './types'`
  Right: `import type { SomeType } from './types'`
- **No unused locals or parameters** — `noUnusedLocals/Parameters: true`. Prefix intentionally
  unused params with `_` (e.g., `_event`).

#### TypeScript — Extension (`src/`)
- `module: Node16` — use `.js` extension in relative imports when needed by Node16 module resolution.
- `strict: true` — no implicit any, strict null checks throughout.
- `crypto.randomUUID()` is available in the extension host — no need for external UUID libraries.

#### TypeScript — Webview (`webview-ui/src/`)
- `verbatimModuleSyntax: true` — every file must be treated as ESM; no CommonJS patterns.
- `erasableSyntaxOnly: true` — no decorators, no `const enum`, no `namespace`.
- `noUncheckedSideEffectImports: true` — side-effect-only imports must be deliberate.
- Webview runs in a browser-like context — no Node.js APIs (`fs`, `path`, etc.) available.

### Framework-Specific Rules

#### VS Code Extension
- Use `WebviewViewProvider` (not `WebviewPanel`) — the view lives in the panel area alongside terminals.
- Extension ↔ Webview communication is exclusively via `postMessage` — no shared memory.
  Extension sends: `panel.webview.postMessage(msg)`. Webview sends: `vscode.postMessage(msg)`.
- `workspaceState` for per-workspace persistence (agent list). `globalState` for cross-workspace
  settings (e.g., `pixel-agents.soundEnabled`).
- Layout is persisted to `~/.pixel-agents/layout.json` (user-level file), NOT to workspaceState.
- Terminal `cwd` option must be set at creation time — cannot change after creation.
- `fs.watch` is unreliable on Windows — always pair with a polling backup (2s interval).
- Partial line buffering is required for append-only file reads — carry unterminated lines between reads.

#### React (Webview)
- Game/office state lives in imperative classes (`OfficeState`, `editorState`) — NOT in React state.
  After imperative mutations, call the appropriate `onXxxChange()` callback to trigger React re-render.
- Canvas interactions (hit-testing, drag, pan) are handled imperatively in `OfficeCanvas.tsx` —
  do not lift canvas state into React hooks unless it affects React-rendered UI.
- `useExtensionMessages.ts` is the single source of truth for agent/tool state from the extension.
- `useEditorActions.ts` manages editor state + callbacks; `useEditorKeyboard.ts` is a side-effect hook.
- Hooks are composed in `App.tsx` — do not add new top-level state outside of the existing hooks
  without discussing architecture first.
- Web Audio API: `AudioContext` starts suspended in webviews — call `unlockAudio()` on first user
  gesture (canvas mousedown) before playing any sounds.

### Testing Rules

- **No test framework is currently configured** — do not add test files or test infrastructure
  without explicit instruction. The project has no `jest.config`, `vitest.config`, or test scripts.
- Build verification is the primary quality gate: `npm run build` runs `check-types` → `lint` →
  `esbuild` → `vite build`. All four must pass before considering work complete.
- Type-checking is separate from building: `npm run check-types` (tsc --noEmit) for fast feedback.
- Linting runs on `src/` (extension) via `npm run lint`; webview via `npm run lint:webview`.
- Pre-commit hooks (lint-staged) auto-fix ESLint issues and run Prettier on staged files —
  do not assume a file is correctly formatted until after a commit or explicit `npm run format`.

### Code Quality & Style Rules

#### Constants Discipline (Critical)
- **All magic numbers and strings MUST go in the appropriate constants file** — never inline them:
  - Extension backend: `src/constants.ts`
  - Webview: `webview-ui/src/constants.ts`
  - CSS custom properties: `webview-ui/src/index.css` `:root` block (`--pixel-*` vars)
  - Canvas overlay colors (rgba strings) go in the webview constants file, not CSS.

#### File & Module Naming
- Extension modules: `camelCase.ts` (e.g., `agentManager.ts`, `fileWatcher.ts`)
- Extension classes/providers: `PascalCase.ts` (e.g., `PixelofficeViewProvider.ts`)
- Webview components: `PascalCase.tsx` (e.g., `BottomToolbar.tsx`, `OfficeCanvas.tsx`)
- Webview modules: `camelCase.ts` (e.g., `colorize.ts`, `tileMap.ts`, `toolUtils.ts`)

#### Import Ordering
- `simple-import-sort` is enforced — imports are auto-sorted on commit. Do not manually reorder.
- Always use `import type` for type-only imports (see Language Rules).

#### UI Styling (Pixel Aesthetic)
- **No `borderRadius`** — all overlays use sharp corners (`borderRadius: 0`).
- Shadows: hard offset only — `2px 2px 0px #0a0a14` (no blur radius).
- Use CSS variables from `index.css` `:root` for all UI colors (`--pixel-bg`, `--pixel-border`,
  `--pixel-accent`, etc.) — do not hardcode hex colors in React inline styles.
- Pixel font: FS Pixel Sans — applied globally via `@font-face` in `index.css`.

#### Prettier Config (enforced)
- singleQuote: true, tabWidth: 2, useTabs: false, trailingComma: all, printWidth: 100, endOfLine: lf

### Development Workflow Rules

#### Build Pipeline
- Full build: `npm run build` (type-check → lint → esbuild → vite). Run from project root.
- Webview only: `cd webview-ui && npm run build` (or `npm run build:webview` from root).
- Watch mode: `npm run watch` (parallel esbuild watch + tsc watch). Use during active development.
- Production package: `npm run package` (same as build but esbuild in production mode).
- Asset pipeline (tileset import): `npm run import-tileset` — 7-stage script, interactive CLI.

#### Extension Development
- Press **F5** in VS Code to launch the Extension Development Host.
- After rebuilding, reload the extension via the button on the main VS Code window (not the dev host).
- `esbuild.js` is the custom bundler config — inline problem matcher, no extra extension needed.
- Webview assets are copied from `webview-ui/public/assets/` → `dist/assets/` during build.
- To update the default layout: run "Pixel office: Export Layout as Default" from the command palette,
  then rebuild (writes to `webview-ui/public/assets/default-layout.json`).

#### Two Separate npm Workspaces
- Root `package.json` = extension. `webview-ui/package.json` = webview. They are independent.
- `npm install` at root does NOT install webview deps — must also run `cd webview-ui && npm install`.
- Do not add webview dependencies to the root `package.json` or vice versa.

#### Scripts Directory
- `scripts/` contains asset extraction pipeline (TypeScript, run via `tsx`). Not part of the
  extension build — excluded from `tsconfig.json`. Run ad-hoc when updating sprite assets.

### Critical Don't-Miss Rules

#### Architecture Boundaries
- **Never add inline constants** — any new number/string with semantic meaning goes in
  `src/constants.ts` or `webview-ui/src/constants.ts`. This is the single most frequently
  violated rule in this codebase.
- **Never use `enum`** — the compiler (`erasableSyntaxOnly`) will reject it. Use `as const`.
- **Never use Node.js APIs in webview code** — `fs`, `path`, `os`, `crypto` are extension-only.
- **Never modify `OfficeState` from React render** — it is imperative; mutations happen in
  event handlers and the game loop only.

#### JSONL / File Watching Gotchas
- `/clear` in a Claude session creates a **new JSONL file** — the old file simply stops receiving
  data. Agents must be re-bound to the new file path.
- `fs.watch` on Windows fires spuriously and misses events — the 2s polling backup is not optional.
- Always buffer partial lines when reading append-only JSONL files — a read may land mid-line.
- Delay `agentToolDone` messages by 300ms — prevents React batching from hiding brief active states.

#### Agent & Subagent ID System
- Main agents: positive integer IDs (1, 2, 3…).
- Sub-agents: **negative** integer IDs (-1, -2, -3…).
- Sub-agents are **never persisted** — they are ephemeral and recreated from JSONL on restore.
- Sub-agent clicks focus the **parent** terminal, not the sub-agent itself.

#### Sprite & Asset System
- PNG → SpriteData uses alpha threshold **128** (not 0 or 255) for opaque detection.
- Character sprites are pre-colored PNGs (6 palettes) — no runtime palette swapping. Hue shifts
  use `adjustSprite()` (HSL rotation), not palette replacement.
- Sprite cache is keyed by `"palette:hueShift"` — include both when constructing cache keys.
- `layoutToSeats()` derives seats from furniture at runtime — never store seat data separately.
- `backgroundTiles` on a catalog entry means the top N footprint rows are walkable/placeable-through.

#### Rendering
- Zoom = integer device-pixels-per-sprite-pixel. **Never use `ctx.scale(dpr)`** — pixel-perfect
  rendering is achieved by making zoom account for DPR directly.
- Default zoom: `Math.round(2 * devicePixelRatio)`.
- All entities are z-sorted by Y before rendering — do not render in insertion order.
- Wall sprites extend **16px above** their tile (3D face effect) — account for this in hit-testing
  and overlap calculations.

#### Layout Persistence
- Layout writes use atomic rename (`.tmp` + rename) via `writeLayoutToFile()` — never write directly.
- `markOwnWrite()` prevents the file watcher from re-reading our own write — always call it.
- Cross-window sync: external layout changes push `layoutLoaded` to webview; skipped if editor
  has unsaved changes (last-save-wins policy).

---

## Usage Guidelines

**For AI Agents:**
- Read this file before implementing any code in this project
- Follow ALL rules exactly as documented
- When in doubt, prefer the more restrictive option
- Update this file if new patterns emerge

**For Humans:**
- Keep this file lean and focused on agent needs
- Update when technology stack changes
- Review periodically for outdated rules
- Remove rules that become obvious over time

Last Updated: 2026-03-12
