# Integration Architecture — PixelOffice

_Generated: 2026-03-12 | Scan: Exhaustive_

---

## Overview

PixelOffice has three distinct "parts" that integrate through two main channels:

```
┌─────────────────────────────────────────────────────────────────────┐
│  OFFLINE: Asset Pipeline (scripts/)                                 │
│  tsx scripts → PNG files + furniture-catalog.json                   │
│                         │                                           │
│                         ▼  (copied on npm run build)                │
│                   webview-ui/public/assets/                         │
└─────────────────────────────────────────────────────────────────────┘
                           │
                           ▼ (copied to dist/assets/ by esbuild.js)
┌─────────────────────────────────────────────────────────────────────┐
│  RUNTIME                                                            │
│                                                                     │
│  ┌──────────────────────────┐       postMessage()                   │
│  │  Extension Host (src/)   │ ◄──────────────────────────────────► │
│  │  Node.js / CommonJS      │       (JSON protocol)                 │
│  └──────────────────────────┘                                       │
│           │                         ┌──────────────────────────┐    │
│           │ fs.watch/read           │  Webview UI (webview-ui/)│    │
│           ▼                         │  React + Canvas 2D       │    │
│  ~/.claude/projects/<hash>/         └──────────────────────────┘    │
│  <session-id>.jsonl                                                 │
│           │                                                         │
│           ▼ (separate process)                                      │
│  Claude Code CLI (claude --session-id <uuid>)                       │
│  Runs in VS Code Terminal                                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Integration Point 1: Extension Host ↔ Webview UI

**Mechanism:** VS Code `postMessage()` API (bidirectional JSON messages)
**Direction:** Both directions
**Protocol:** See `api-contracts.md` for full schema

### Extension → Webview

The extension host sends data to the webview via `panel.webview.postMessage(message)`.

**Initialization sequence (strict load order):**
```
1. characterSpritesLoaded    → 6 pre-colored character PNGs (SpriteData[][])
2. floorTilesLoaded          → 7 floor patterns (16×16 grayscale)
3. wallTilesLoaded           → 16 wall auto-tile pieces (16×32)
4. furnitureAssetsLoaded     → catalog JSON + furniture sprite data
5. layoutLoaded              → OfficeLayout (tiles, furniture, colors)
6. existingAgents            → Restore persisted agents (palette, seat, folder)
7. settingsLoaded            → Sound enabled state
```

**Runtime messages:**
- Agent lifecycle: `agentCreated`, `agentClosed`
- Tool activity: `agentToolStart`, `agentToolDone`, `agentToolsClear`, `agentStatus`
- Permission detection: `agentToolPermission`, `agentToolPermissionClear`
- Subagent lifecycle: `subagentToolStart`, `subagentToolDone`, `subagentToolPermission`, `subagentClear`
- Cross-window layout sync: `layoutLoaded` (re-sent on external file change)

### Webview → Extension

The webview posts messages via `acquireVsCodeApi().postMessage(message)` (singleton).

**User-triggered actions:**
- `openClaude` → create new terminal
- `focusAgent` → focus existing terminal
- `closeAgent` → terminate terminal
- `saveLayout` → persist layout file
- `saveAgentSeats` → persist seat assignments
- `exportLayout` → file save dialog
- `importLayout` → validate + write new layout
- `setSoundEnabled` → persist sound preference

---

## Integration Point 2: Extension Host ↔ Filesystem

**Mechanism:** Node.js `fs` module (async + sync)
**Direction:** Extension reads from Claude output; Extension reads/writes layout

### JSONL Transcript Monitoring

```
Claude Code CLI process
    │
    └─ Writes to: ~/.claude/projects/<project-hash>/<session-id>.jsonl
                  (append-only, newline-delimited JSON)

Extension Host watches:
    ├─ fs.watch(jsonlPath) — event-driven (unreliable on Windows)
    ├─ fs.watchFile(jsonlPath, {interval: 1000}) — stat-based polling backup
    └─ setInterval(1000ms) — manual polling for missed events

readNewLines(agent):
    ├─ Read from agent.fileOffset to current size
    ├─ Buffer incomplete last line
    ├─ Parse each complete line as JSON
    └─ Dispatch to processTranscriptLine()
```

**Project hash derivation:**
```
workspaceRoot.replace(/[:\\/]/g, '-')
// C:/Users/user/Projects/PixelOffice → C--Users-user-Projects-PixelOffice
```

**Terminal adoption (brownfield):**
- Every 1s: scan `~/.claude/projects/<hash>/` for JSONL files not yet tracked
- If unmanaged file found + free terminal exists → adopt (associate JSONL with terminal)
- If `/clear` creates new JSONL → reassign existing agent's file reference

### Layout File I/O

```
Write path (atomic):
    1. JSON.stringify(layout)
    2. Write to ~/.pixel-agents/layout.json.tmp
    3. fs.rename(.tmp → layout.json)  ← atomic on same filesystem

Read path:
    1. fs.readFile(~/.pixel-agents/layout.json)
    2. JSON.parse()
    3. Schema validation (version: 1, tiles array)
    4. Migration if needed (old workspace state format)

Cross-window sync:
    1. watchLayoutFile() starts fs.watch + 2s polling
    2. On change: markOwnWrite() check (skip if this process wrote it)
    3. If external change + webview open: send layoutLoaded
    4. If editor has unsaved changes: skip (last-save-wins)
```

---

## Integration Point 3: Extension Host ↔ VS Code Terminals

**Mechanism:** VS Code Terminal API
**Direction:** Extension creates and controls terminals

```typescript
// Create new Claude terminal
const terminal = vscode.window.createTerminal({
  name: `Agent ${id}`,
  cwd: workspaceRoot,
});
terminal.show();
terminal.sendText(`claude --session-id ${sessionId}`);

// /add-dir for multi-root workspaces
terminal.sendText(`/add-dir ${additionalPath}`);

// Focus existing terminal
terminal.show();

// Terminate terminal
terminal.dispose();
```

**Terminal adoption heuristic:** When the extension starts, it scans for existing VS Code terminals that might be running Claude. If a terminal has no agent and a matching JSONL is found, the terminal is associated with a new AgentState.

---

## Integration Point 4: Asset Pipeline → webview-ui/public/assets/

**Mechanism:** File I/O (scripts write directly to webview-ui/public/assets/)
**Direction:** One-way (offline, before build)
**Trigger:** Manual execution (`npm run import-tileset` or individual `tsx` commands)

```
scripts/5-export-assets.ts
    │
    ├─ Read: assets/MetroCity/ (raw tileset PNGs)
    ├─ Process: pngjs pixel extraction, flood-fill region detection
    ├─ Write: webview-ui/public/assets/<furniture-type>.png (individual sprites)
    └─ Write: webview-ui/public/assets/furniture-catalog.json

scripts/export-characters.ts
    │
    ├─ Read: CHARACTER_PALETTES (hardcoded color definitions)
    ├─ Process: Apply palettes to base character template sprite
    └─ Write: webview-ui/public/assets/characters/char_0.png – char_5.png

scripts/generate-walls.js
    │
    ├─ Process: Programmatic pixel generation (4×4 grid of wall pieces)
    └─ Write: webview-ui/public/assets/walls.png
```

**Build step integration:** `esbuild.js` copies `webview-ui/public/assets/` → `dist/assets/` on every build. The extension host loads sprites from `dist/assets/` at runtime.

---

## Integration Point 5: Extension Host ↔ Claude Code CLI

**Mechanism:** Indirect (file-based, via JSONL transcripts)
**Direction:** Claude writes → Extension reads

Claude Code CLI does NOT communicate directly with the extension via IPC. The extension monitors Claude's output through filesystem watching only.

**Why not IPC?**
- `--output-format stream-json` requires non-TTY stdin — incompatible with VS Code terminals
- Hook-based IPC was attempted but failed: hooks are captured at startup, env vars don't propagate into VS Code terminal processes
- JSONL file watching is reliable, language-agnostic, and doesn't require modifications to Claude Code CLI

---

## Data Flow: Agent Creation to Character Animation

```
1. User clicks "+Agent"
   └─ Webview → Extension: openClaude message

2. Extension: launchNewTerminal()
   ├─ Generate sessionId (crypto.randomUUID())
   ├─ Create VS Code terminal: createTerminal({name, cwd})
   ├─ Send: terminal.sendText('claude --session-id <uuid>')
   ├─ Pre-register JSONL path: ~/.claude/projects/<hash>/<uuid>.jsonl
   └─ Extension → Webview: agentCreated {id, folderName}

3. Webview: addCharacter(id)
   ├─ Assign palette (pickDiversePalette) + hueShift
   ├─ Find nearest available seat
   ├─ Create Character {id, palette, hueShift, seatId, state: WALK}
   └─ Trigger matrix spawn effect (0.3s)

4. Extension: Poll for JSONL (1000ms interval)
   ├─ File appears → clearInterval, start file watching
   └─ fileWatcher.startWatching(agent)

5. Claude writes tool_use to JSONL
   └─ fs.watch / polling detects change

6. Extension: readNewLines(agent)
   ├─ Parse JSONL record: type=assistant, content[0].type=tool_use
   └─ processTranscriptLine: activeToolIds.add(toolId)
       └─ Extension → Webview: agentToolStart {id, toolId, status}

7. Webview: updateCharacterToolState(id, toolStates)
   ├─ Character.state = TYPE
   ├─ Character.animationType = 'type' or 'read' (based on tool name)
   └─ Character walks to seat (if not already there)

8. Claude writes tool_result to JSONL
   └─ Extension: agentToolDone delayed 300ms
       └─ Webview: clear tool from active set

9. Claude writes turn_duration system record
   └─ Extension: clearAllTools + agentStatus(waiting)
       └─ Webview: show green checkmark bubble (auto-fades 2s)
           └─ Character transitions to IDLE + wander AI
```

---

## Shared Data Structures

These structures are defined in the extension host (`src/types.ts`) and replicated (by convention, not by code sharing) in the webview (`webview-ui/src/office/types.ts`). There is no shared runtime code between the two processes.

| Structure | Extension Source | Webview Source |
|---|---|---|
| `OfficeLayout` | `types.ts` | `office/types.ts` |
| `PlacedFurniture` | `types.ts` | `office/types.ts` |
| `FloorColor` | `types.ts` | `office/types.ts` |
| Message types | Inline in `PixelofficeViewProvider.ts` | Inline in `useExtensionMessages.ts` |

**No shared module:** The extension host (CJS) and webview (ESM) cannot share a runtime module. Message schemas are maintained in parallel and must be kept in sync manually.

---

## Deployment Topology

```
VS Code Install
└── .vsix package (pixel-agents-*.vsix)
    ├── package.json          ← Extension manifest + contributes
    ├── dist/extension.js     ← Extension host bundle (CJS)
    ├── dist/webview/         ← Webview bundle (ESM)
    │   ├── index.html
    │   └── assets/index-*.js
    └── dist/assets/          ← Static sprites + catalog + default layout
        ├── characters/char_0-5.png
        ├── floors.png
        ├── walls.png
        ├── furniture-catalog.json
        └── default-layout.json

Runtime files (user home, NOT in .vsix):
└── ~/.pixel-agents/
    └── layout.json           ← User's office layout (persisted across restarts)

Runtime files (Claude Code output, NOT in .vsix):
└── ~/.claude/projects/<hash>/
    └── <session-id>.jsonl    ← Claude transcript (watched by extension)
```

---

## Cross-Window Synchronization

PixelOffice supports multiple VS Code windows sharing the same office layout:

```
Window A (makes edit) → saves layout.json → fs.watch/poll triggers
Window B (observer)  ← reads layout.json ← layoutLoaded message sent

Conflict resolution:
  ├─ markOwnWrite(): Window A sets a flag before writing
  ├─ File watcher in Window A ignores the event it triggered
  ├─ Window B's watcher detects external change → reloads
  └─ If Window B has unsaved editor changes → SKIP reload (last-save-wins)
```
