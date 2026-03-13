# Development Guide — PixelOffice

_Generated: 2026-03-12 | Scan: Exhaustive_

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Node.js | LTS (see `.nvmrc`) | Use `nvm use` to match pinned version |
| npm | Bundled with Node.js | Used for both root and webview-ui |
| VS Code | ^1.107.0 | Required for Extension Development Host |
| Claude Code CLI | Latest | Required for testing agent features |
| Git | Any | For version control |

**Optional (for asset pipeline):**
- Pixel art tileset (third-party asset; see `assets/` folder notes in README)

---

## Initial Setup

```bash
# 1. Clone the repository
git clone <repo-url>
cd PixelOffice

# 2. Install extension root dependencies
npm install

# 3. Install webview UI dependencies
cd webview-ui && npm install && cd ..

# 4. Run a full build to verify everything works
npm run build
```

**Why two `npm install`?** The extension host and webview are separate npm workspaces (not linked). `webview-ui/` has its own `node_modules` with React and Vite; the root has esbuild and VS Code types.

---

## Development Workflow

### Option A: F5 Quick Start (Recommended)

1. Open the project in VS Code
2. Press **F5** (or Run → "Run Extension")
3. A new **Extension Development Host** window opens with the extension loaded
4. Open the Pixel office panel (View → Open View... → Pixel office)
5. Make code changes — rebuild to see them (see below)

### Option B: Watch Mode

```bash
# Terminal 1 — Start all watchers in parallel
npm run watch
# Runs: watch:esbuild (backend bundle) + watch:tsc (type check) in parallel
# Note: Vite watch is separate (run manually if needed)
```

After making changes, **reload the Extension Development Host** using the reload button in the main VS Code window's debug toolbar.

### Build Commands Reference

```bash
# Full build (type-check → lint → esbuild backend → vite webview)
npm run build

# Build only (skips type-check and lint — for quick iteration)
node esbuild.js && cd webview-ui && npm run build && cd ..

# Type check only (no emit)
npm run check-types

# Watch: backend bundle (esbuild)
npm run watch:esbuild

# Watch: type check (tsc)
npm run watch:tsc

# Lint extension backend
npm run lint

# Lint webview
npm run lint:webview

# Auto-fix lint issues
npm run lint:fix
npm run lint:webview:fix

# Format all files
npm run format

# Check formatting without writing
npm run format:check
```

---

## Project Structure for Development

```
src/           ← Backend TypeScript (hot-reloads via watch:esbuild)
webview-ui/    ← Frontend React (hot-reloads via vite dev or watch:esbuild rebuild)
scripts/       ← Asset pipeline (run manually with tsx)
```

**Backend changes** (`src/`): Rebuild with esbuild, then reload Extension Dev Host.

**Webview changes** (`webview-ui/src/`): Rebuild with Vite, then reload Extension Dev Host. The webview does NOT hot-reload — a full host reload is required.

---

## Environment Setup

No `.env` file required for basic development.

**Layout file:** Created automatically at `~/.pixel-agents/layout.json` on first run. Delete this file to reset to default layout.

**JSONL files:** Claude Code writes transcripts to `~/.claude/projects/<project-hash>/`. The project hash is derived from the workspace root path (colons, backslashes, forward slashes replaced with dashes).

Example: `C:/Users/user/Projects/PixelOffice` → `C--Users-user-Projects-PixelOffice`

---

## Code Guidelines

### Constants: Never Inline

All magic numbers and strings must go in the centralized constants files:

| Location | Use for |
|---|---|
| `src/constants.ts` | Extension backend: timing, truncation, VS Code IDs |
| `webview-ui/src/constants.ts` | Webview: grid size, animation speeds, zoom, rendering offsets |
| `webview-ui/src/index.css` `:root` | CSS custom properties (`--pixel-*` colors, z-indices) |

Canvas overlay colors (rgba strings) go in the webview constants file since they're used in canvas 2D context, not CSS.

### TypeScript Constraints

```typescript
// ❌ No enums (erasableSyntaxOnly)
enum Direction { UP, DOWN }

// ✅ Use as const objects
const Direction = { UP: 'UP', DOWN: 'DOWN' } as const;
type Direction = typeof Direction[keyof typeof Direction];

// ❌ Missing import type for type-only imports (verbatimModuleSyntax)
import { SomeType } from './types';

// ✅ Correct
import type { SomeType } from './types';
```

### UI Styling Rules

All UI overlays must follow the pixel-art aesthetic:

```tsx
// ❌ No rounded corners
style={{ borderRadius: '4px', boxShadow: '0 2px 8px rgba(0,0,0,0.3)' }}

// ✅ Pixel-art style
style={{
  borderRadius: 0,
  border: '2px solid var(--pixel-border)',
  background: 'var(--pixel-bg)',
  boxShadow: '2px 2px 0px #0a0a14',  // Hard offset, no blur
  fontFamily: 'FS Pixel Sans',
}}
```

CSS variables are defined in `webview-ui/src/index.css` `:root`:
- `--pixel-bg` — Panel background (`#1e1e2e`)
- `--pixel-border` — Border color
- `--pixel-accent` — Accent color
- See `index.css` for full list

### Canvas Rendering Rules

- **No `ctx.scale(devicePixelRatio)`** — zoom is managed as integer device-pixels-per-sprite-pixel
- **Always set `imageSmoothingEnabled = false`** before drawing sprites
- **Integer coordinates** — always use `Math.round()` for canvas draw positions
- **Default zoom:** `Math.round(2 * devicePixelRatio)`

---

## Testing

There are no automated tests in this project. Testing is done manually via the Extension Development Host.

**Manual testing checklist:**
- [ ] Press F5 → Extension Dev Host opens
- [ ] Pixel office panel appears in the panel area
- [ ] `+Agent` button creates a new terminal running `claude`
- [ ] Character appears on canvas with spawn animation
- [ ] While Claude is working: character animates (type/read)
- [ ] After turn ends: green checkmark bubble appears
- [ ] Layout Editor: toggle opens editor, paint floor/wall, place furniture
- [ ] Undo/Redo: Ctrl+Z/Y cycles through changes
- [ ] Save: EditActionBar Save persists to `~/.pixel-agents/layout.json`
- [ ] Settings: export layout → JSON file; import → reloads layout

**Windows-specific testing:**
- The extension is primarily developed and tested on Windows
- Known limitation: `fs.watch` is unreliable on Windows → always paired with polling backup
- Use `scripts/jsonl-viewer.html` to inspect JSONL transcript files

---

## Asset Pipeline

Only needed when importing new pixel-art furniture tilesets:

```bash
# Stage 0: Launch interactive pipeline CLI
npm run import-tileset

# Individual stages (tsx runtime, no compile step required):
npx tsx scripts/1-detect-assets.ts
# Then open scripts/2-asset-editor.html in browser
npx tsx scripts/3-vision-inspect.ts  # Requires ANTHROPIC_API_KEY
# Then open scripts/4-review-metadata.html in browser
npx tsx scripts/5-export-assets.ts

# Generate character sprites (bakes palettes into 6 PNGs):
npx tsx scripts/export-characters.ts

# Generate walls.png (run once, outputs to webview-ui/public/assets/):
node scripts/generate-walls.js
```

**Asset pipeline output:** `webview-ui/public/assets/`
- Individual furniture PNG files
- `furniture-catalog.json` (type metadata, footprints, categories)
- Updated on build: `esbuild.js` copies these to `dist/assets/`

---

## Updating the Default Layout

When you want to change the layout that new users get on first install:

1. Open a VS Code window with the extension running
2. Design your layout using the editor
3. Run: `Ctrl+Shift+P` → **Pixel office: Export Layout as Default**
4. This writes `webview-ui/public/assets/default-layout.json`
5. Rebuild the extension: `npm run build`
6. The new default is now bundled in `dist/assets/`

---

## Packaging for Release

```bash
# Install vsce (VS Code Extension Manager) if not already installed
npm install -g @vscode/vsce

# Package as .vsix
vsce package

# Publish to VS Code Marketplace
vsce publish
```

The `vscode:prepublish` script runs `npm run package` (production build: minified, no sourcemaps).

---

## Debugging Tips

### Extension Host Debugging

- In the Extension Dev Host, open **Help → Toggle Developer Tools** for the extension host console
- The webview has its own DevTools: Right-click in Pixel office panel → **Inspect Element**

### JSONL Debugging

Open `scripts/jsonl-viewer.html` in a browser and point it to a `.jsonl` file to inspect the transcript format.

### Layout File

Reset by deleting `~/.pixel-agents/layout.json`. The extension falls back to the bundled default on next load.

### File Watching Issues (Windows)

If JSONL changes aren't being detected:
1. Check the extension host console for watcher errors
2. The `PROJECT_SCAN_INTERVAL_MS = 1000ms` polling backup should catch missed events
3. Verify the JSONL file exists at `~/.claude/projects/<hash>/`

### Windows-MCP Desktop Automation

For UI automation testing with the Windows-MCP tool:
- Run `uvx --python 3.13 windows-mcp`
- Snap both VS Code windows side-by-side on the SAME screen before clicking
- Webview buttons show `(0,0)` in the accessibility tree — use `Snapshot(use_vision=true)` for coordinates
- Reload extension via the main VS Code window's debug toolbar after rebuilding

---

## Contributing

See `CONTRIBUTING.md` for:
- Pull request process (4 steps)
- Code style requirements
- Bug reporting and feature request guidelines
- Code of Conduct reference
