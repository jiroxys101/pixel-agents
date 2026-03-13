# PixelOffice — Project Documentation Index

_Generated: 2026-03-12 | Version: 1.0.2 | Scan: Exhaustive_

👆 **This is the primary entry point for AI-assisted development on PixelOffice.**

---

## Project Overview

- **Type:** Multi-part VS Code Extension (extension host + React webview + asset pipeline)
- **Primary Language:** TypeScript
- **Architecture:** Dual-process event-driven (Extension Host ↔ Webview via postMessage)
- **Version:** 1.0.2 | Publisher: pablodelucca | License: MIT

### Quick Reference

#### Extension Host (src/)
- **Type:** `extension` (VS Code Extension)
- **Tech Stack:** TypeScript, esbuild, pngjs, VS Code API, fs.watch
- **Entry Point:** `src/extension.ts` → `activate()`
- **Output:** `dist/extension.js` (CommonJS)
- **Architecture:** State Machine + Event-Driven Pipeline (JSONL file watching → character updates)

#### Webview UI (webview-ui/)
- **Type:** `web` (React + Canvas)
- **Tech Stack:** React 19, TypeScript, Vite, HTML5 Canvas 2D, Web Audio API
- **Entry Point:** `webview-ui/src/main.tsx`
- **Output:** `dist/webview/` (ES Modules)
- **Architecture:** Imperative Game State (OfficeState) + Reactive React Shell

#### Asset Pipeline (scripts/)
- **Type:** `cli` (tsx offline scripts)
- **Tech Stack:** TypeScript, tsx, @anthropic-ai/sdk, pngjs
- **Entry Points:** `scripts/0-import-tileset.ts`, `scripts/5-export-assets.ts`, `scripts/export-characters.ts`
- **Output:** `webview-ui/public/assets/` (PNGs + furniture-catalog.json)

---

## Generated Documentation

### Architecture & Design
- [Project Overview](./project-overview.md) — Summary, key features, architecture at a glance
- [Architecture](./architecture.md) — Full system design, module map, data flows, key decisions
- [Integration Architecture](./integration-architecture.md) — Multi-part integration, postMessage protocol, cross-window sync, deployment topology
- [Technology Stack](./technology-stack.md) — Tech table, part-level summaries, build commands, TypeScript constraints

### Code Reference
- [API Contracts](./api-contracts.md) — Complete Extension ↔ Webview message protocol (schemas, triggers, effects)
- [Data Models](./data-models.md) — All persisted and runtime data schemas (OfficeLayout, Character, AgentState, JSONL format)
- [Component Inventory](./component-inventory.md) — React components, hooks, game engine modules, sprite system
- [Source Tree Analysis](./source-tree-analysis.md) — Annotated full directory tree with purpose of every file

### Developer Guides
- [Development Guide](./development-guide.md) — Setup, build commands, code guidelines, testing, asset pipeline, packaging

---

## Existing Documentation

- [README.md](../README.md) — User-facing: features, installation, usage, tech stack, limitations, vision
- [CONTRIBUTING.md](../CONTRIBUTING.md) — PR process, code guidelines, bug reporting
- [CHANGELOG.md](../CHANGELOG.md) — Version history (v1.0.1, v1.0.2)
- [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) — Contributor Covenant 3.0
- [CLAUDE.md](../CLAUDE.md) — Compressed AI reference (architecture, patterns, lessons — optimized for AI context)

---

## Getting Started

```bash
# Install all dependencies
npm install && cd webview-ui && npm install && cd ..

# Full build
npm run build

# Launch Extension Development Host (in VS Code)
# Press F5 or Run → "Run Extension"
```

For detailed instructions see [Development Guide](./development-guide.md).

---

## Key File Locations at Runtime

| Resource | Path |
|---|---|
| User layout | `~/.pixel-agents/layout.json` |
| Claude transcripts | `~/.claude/projects/<hash>/<session-id>.jsonl` |
| Extension bundle | `dist/extension.js` |
| Webview bundle | `dist/webview/` |
| Bundled assets | `dist/assets/` |

---

## When Working on New Features

| Task | Start here |
|---|---|
| Understanding agent lifecycle | [Architecture.md — JSONL Processing Pipeline](./architecture.md#jsonl-processing-pipeline) |
| Adding a new message type | [API Contracts](./api-contracts.md) |
| Adding a UI component | [Component Inventory](./component-inventory.md) |
| Understanding layout schema | [Data Models — Layout File](./data-models.md#1-layout-file) |
| Adding furniture types | [Data Models — Furniture Catalog](./data-models.md#4-furniture-catalog) |
| Canvas rendering | [Component Inventory — renderer.ts](./component-inventory.md#rendererts) |
| File watching / JSONL parsing | [Architecture.md — Extension Host](./architecture.md#part-1-extension-host-src) |
| Cross-window sync | [Integration Architecture — Layout File I/O](./integration-architecture.md#integration-point-2-extension-host-filesystem) |
| Build configuration | [Technology Stack — Build Commands](./technology-stack.md#build-commands) |
