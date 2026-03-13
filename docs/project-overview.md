# Project Overview — PixelOffice

_Generated: 2026-03-12 | Version: 1.0.2_

---

## Summary

**PixelOffice** is a VS Code extension that brings your Claude Code AI agent sessions to life as animated pixel-art characters in a virtual office environment. Each running Claude terminal becomes a character in the office — busy typing when working, wandering around when idle, and showing speech bubbles when waiting for your input.

The extension monitors Claude Code's JSONL transcript files in real-time to detect tool usage and translate it into character animations. It includes a full interactive layout editor for customizing the office space, with support for floor tiles, walls, furniture, and persistent cross-window layouts.

---

## Key Features

| Feature | Description |
|---|---|
| **Live agent tracking** | Real-time character animations reflect what Claude is doing (typing, reading, idle) |
| **Office layout editor** | Paint floors/walls, place furniture, undo/redo, export/import layouts |
| **Sub-agent visualization** | Task tool spawns separate characters with permission bubble detection |
| **Speech bubbles** | Permission bubbles (amber `...`) and waiting bubbles (green ✓) |
| **Sound notifications** | E5→E6 ascending chime when an agent is waiting for input |
| **Persistent layouts** | Office layout saved to `~/.pixel-agents/layout.json`; shared across all VS Code windows |
| **Character diversity** | 6 pre-colored palettes + hue shift for 7+ agents |
| **Matrix spawn effect** | Digital rain animation for character appearance/disappearance |
| **Cross-window sync** | Layouts update in real-time when another VS Code window saves |

---

## Architecture at a Glance

**Type:** Multi-part VS Code Extension (3 parts)

| Part | Technology | Role |
|---|---|---|
| Extension Host | TypeScript, Node.js, esbuild | Terminal management, JSONL watching, asset loading, layout persistence |
| Webview UI | React 19, TypeScript, Vite, Canvas 2D | Pixel-art game engine, layout editor, character animations |
| Asset Pipeline | TypeScript, tsx, Claude Vision API | Offline tileset import and sprite generation |

**Communication:** `postMessage()` JSON protocol between extension host and webview. No HTTP servers, no databases, no external services at runtime.

---

## Tech Stack Summary

```
Extension Host:  TypeScript → esbuild → dist/extension.js (CommonJS)
Webview:         React 19 + TypeScript → Vite → dist/webview/ (ES Modules)
Canvas:          HTML5 Canvas 2D (pixel-perfect, no smoothing, integer zoom)
Storage:         JSON files (~/.pixel-agents/layout.json, VS Code workspace state)
Asset watch:     fs.watch + fs.watchFile + manual polling (triple-layer)
```

---

## Repository Structure

```
PixelOffice/
├── src/           Extension backend (10 TypeScript files)
├── webview-ui/    React webview (42 TypeScript/TSX files + assets)
├── scripts/       Asset pipeline (12 offline scripts)
├── assets/        Raw tileset files (third-party, not in repo)
└── docs/          Generated AI documentation (this folder)
```

---

## Entry Points

| Entry | Path | Purpose |
|---|---|---|
| Extension activation | `src/extension.ts` → `activate()` | VS Code loads this on extension start |
| Webview mount | `webview-ui/src/main.tsx` | React app entry, runs in sandboxed browser |
| Build script | `esbuild.js` | Bundles extension + copies assets |
| Full build | `npm run build` | type-check → lint → esbuild → vite |

---

## Getting Started

```bash
# Install dependencies (both parts)
npm install && cd webview-ui && npm install && cd ..

# Build
npm run build

# Launch Extension Development Host
# Press F5 in VS Code (or Run → "Run Extension")
```

See `development-guide.md` for detailed setup, debug tips, and contribution workflow.

---

## Known Limitations

- Agent-terminal sync may break in edge cases (terminal renamed, /clear handling, rapid spawning)
- Status detection is heuristic-based (JSONL watching + timer signals, not direct IPC)
- Windows is the primary test platform; macOS/Linux may have minor differences
- Pixel-art tilesets require a paid third-party asset (MetroCity) — users can import their own

---

## Long-Term Vision

The project aims to become an agent-agnostic, platform-agnostic interface — not specific to Claude Code or VS Code — where any AI agent activity can be visualized as characters in a configurable pixel-art environment.
