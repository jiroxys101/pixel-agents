# Architecture — PixelOffice

_Generated: 2026-03-12 | Project: PixelOffice v1.0.2 | Scan: Exhaustive_

## Executive Summary

PixelOffice is a VS Code extension that renders a pixel-art office populated by animated characters, each representing a running Claude Code terminal session. The extension monitors Claude's JSONL transcript files in real-time and translates tool usage patterns into character animations. An interactive layout editor lets users customize their office space. Layouts persist globally across all VS Code windows.

**Architecture style:** Dual-process event-driven system (Extension Host + Webview) with a canvas-based game engine in the browser context.

---

## System Overview

```
VS Code
├── Extension Host Process (Node.js)
│   └── src/ — Backend: terminal management, file watching, JSONL parsing, asset loading
│
└── Webview Process (Chromium sandbox)
    └── webview-ui/ — Frontend: Canvas 2D game engine, React UI, layout editor
        │
        └── postMessage() protocol ──────────────────────────────────────┐
                                                                         │
Claude Code CLI                                                          │
└── ~/.claude/projects/<hash>/<session-id>.jsonl                         │
        ↑ watched by fs.watch + polling                                  │
        └── JSONL events → parsed → Extension → postMessage → Webview ──┘
```

---

## Part 1: Extension Host (`src/`)

### Pattern: State Machine + Event-Driven Pipeline

The extension host acts as a stateful service orchestrating three responsibilities:
1. **Terminal lifecycle** — create, restore, remove Claude terminals
2. **Transcript monitoring** — watch JSONL files, parse events, detect status
3. **Asset management** — load PNG sprites, build catalogs, persist layouts

### Module Map

| Module | Responsibility |
|---|---|
| `extension.ts` | Activation entry; registers commands, WebviewViewProvider |
| `PixelofficeViewProvider.ts` | WebviewViewProvider implementation; owns the webview panel, dispatches all messages, coordinates all other modules |
| `agentManager.ts` | Agent registry (Map of AgentState); launch, remove, restore, persist |
| `assetLoader.ts` | PNG→SpriteData conversion using pngjs; builds sprite catalogs from `dist/assets/` |
| `fileWatcher.ts` | Triple-layer file watching (fs.watch + fs.watchFile + interval); `readNewLines()` with offset tracking and line buffering |
| `transcriptParser.ts` | JSONL record type dispatch; tool_use/tool_result/progress/system handling; subagent message forwarding |
| `layoutPersistence.ts` | Atomic file I/O to `~/.pixel-agents/layout.json`; cross-window sync; workspace state migration; bundled default fallback |
| `timerManager.ts` | Permission timers (7s), waiting timers (5s text-idle), timer cancellation |
| `constants.ts` | All timing, truncation, parsing, and VS Code API constants |
| `types.ts` | `AgentState`, `PersistedAgent`, `SubagentToolInfo` interfaces |

### Agent State Per Terminal

```typescript
interface AgentState {
  id: number;                          // Positive integer (subagents use negative)
  terminalRef: vscode.Terminal;
  projectDir: string;                  // ~/.claude/projects/<hash>/
  jsonlFile: string;                   // <session-id>.jsonl path
  fileOffset: number;                  // Read position for partial-line buffering
  lineBuffer: string;                  // Incomplete line from last read
  activeToolIds: Set<string>;          // Tools currently running
  activeToolStatuses: Map<string, string>; // toolId → display text
  activeSubagentToolNames: Map<string, Map<string, string>>; // parentId→subId→name
  isWaiting: boolean;                  // In waiting state (bubble shown)
}
```

### JSONL Processing Pipeline

```
fs.watch / fs.watchFile / polling interval
         │
         ▼
readNewLines(agent)
  ├─ Read file from agent.fileOffset
  ├─ Split on \n, buffer incomplete last line
  └─ For each complete line → JSON.parse()
              │
              ▼
processTranscriptLine(agent, record)
  ├─ record.type === "assistant"
  │   └─ role.content[].type === "tool_use"
  │       └─ Add to activeToolIds → send agentToolStart
  │
  ├─ record.type === "user"
  │   └─ role.content[].type === "tool_result"
  │       └─ Remove from activeToolIds → delay 300ms → send agentToolDone
  │
  ├─ record.type === "system" + subtype === "turn_duration"
  │   └─ Definitive turn-end → clear ALL tool state → send agentToolsClear + agentStatus(waiting)
  │
  ├─ record.type === "progress" + data.type === "agent_progress"
  │   └─ Subagent tool_use/tool_result → create/update subagent character
  │       └─ Non-exempt tools → startPermissionTimer(parentAgent)
  │
  ├─ record.type === "progress" + data.type === "bash_progress"/"mcp_progress"
  │   └─ Tool actively executing → restart permission timer (clear stuck detection)
  │
  └─ Text-only messages (no tool_use yet in turn)
      └─ Start TEXT_IDLE_TIMER (5000ms)
          └─ If no new data: send agentStatus(waiting)
```

### Idle Detection: Dual Signal

| Signal | Condition | Reliability |
|---|---|---|
| `turn_duration` system record | Tool-using turns | ~98% of turns |
| Text-idle timer (5s silence) | Text-only turns (no tools used) | Fires only when `hadToolsInTurn = false` |

The text-idle timer is suppressed the moment any `tool_use` block arrives in the current turn, preventing false positives.

### Terminal Adoption (Brownfield Detection)

Every 1s, the extension scans the project's JSONL directory for unknown files. If an unmanaged JSONL is found and an active terminal has no agent assigned, the terminal is "adopted" — the file is associated with it. If a `/clear` command produces a new JSONL file for an existing session, the agent's file reference is reassigned.

### Layout Persistence

```
~/.pixel-agents/layout.json     ← Primary (user-level, shared across windows)
    │
    ├─ Read: readLayoutFromFile()
    ├─ Write: writeLayoutToFile() [atomic: .tmp → rename]
    ├─ Watch: watchLayoutFile() [fs.watch + 2s polling]
    └─ markOwnWrite() prevents self-triggered reload

Fallback chain (new workspace):
  1. ~/.pixel-agents/layout.json (existing)
  2. workspace state key 'pixel-agents.layout' (migrate)
  3. dist/assets/default-layout.json (bundled default)
  4. createDefaultLayout() (hardcoded minimal office)
```

---

## Part 2: Webview Frontend (`webview-ui/`)

### Pattern: Imperative Game State + Reactive React Shell

The webview uses React only as a thin shell for UI overlays. The game state (characters, layout, camera) lives in imperative objects outside React's lifecycle. This prevents React reconciliation from interfering with the 60 FPS game loop.

### Component Tree

```
App.tsx (composition root)
├── useExtensionMessages()   ← message handler; updates OfficeState imperatively
├── useEditorActions()       ← edit mode state; triggers React re-renders via useState
├── useEditorKeyboard()      ← keyboard shortcut effect (R, Z, Y, Esc)
│
├── OfficeCanvas             ← owns the <canvas> element
│   ├── gameLoop (rAF)       ← update() + render() at 60 FPS
│   └── Mouse events         ← hit-testing, drag-to-move, click-to-select
│
├── ToolOverlay              ← status label + permission bubbles + close button
├── EditorToolbar            ← palette, floor/wall/color sliders (edit mode only)
├── BottomToolbar            ← "+ Agent" button, Layout toggle, Settings button
├── ZoomControls             ← +/- buttons (top-right)
├── SettingsModal            ← sound toggle, export/import layout, debug toggle
└── DebugView                ← debug overlay (optional)
```

### Imperative Game State

**OfficeState** (game world, lives outside React):
```
OfficeState
├── layout: OfficeLayout       — cols, rows, tiles[], furniture[], tileColors[]
├── characters: Map<id, Character>  — agent id → character data + FSM state
├── seats: Map<seatId, Seat>  — derived from chair furniture
├── tileMap: TileMap           — walkability grid + BFS
├── furnitureInstances: FurnitureInstance[]  — z-sorted render list
├── subagentIdMap: Map<"parentId:toolId", negId>  — subagent assignment
└── selectedAgentId, cameraFollowId, hoveredAgentId
```

**EditorState** (layout editor, lives outside React):
```
EditorState
├── activeTool: EditTool        — SELECT | FLOOR | WALL | ERASE | FURNITURE | ...
├── selectedFurnitureUid: string | null
├── floorColor: FloorColor      — {h, s, b, c, colorize}
├── wallColor: FloorColor
├── undoStack: OfficeLayout[]   — max 50 entries
├── redoStack: OfficeLayout[]
├── isDirty: boolean            — unsaved changes
└── ghostFurniture, wallDragAdding, colorEditUidRef
```

### Game Loop

```
requestAnimationFrame → gameLoop(timestamp)
    ├─ dt = min(timestamp - prev, MAX_DELTA_TIME_SEC)    // cap at 0.1s
    ├─ update(dt)
    │   ├─ For each character:
    │   │   ├─ Update matrix effect (spawn/despawn)
    │   │   ├─ Update FSM (IDLE → WALK → TYPE)
    │   │   ├─ Update wander AI (BFS to random tile)
    │   │   └─ Update bubble animations (fade, timer)
    │   └─ Sync active tools from message state
    │
    └─ render(ctx)
        ├─ Clear canvas
        ├─ Apply camera transform (pan + zoom)
        ├─ Draw floor tiles (pattern + colorization)
        ├─ Collect all entities (furniture + characters + walls) → z-sort by zY
        ├─ Draw each entity in z-order
        │   ├─ Furniture: drawSprite() from spriteCache
        │   ├─ Characters: drawSprite() with direction + frame
        │   └─ Wall tiles: bitmask lookup → draw from wallTiles
        ├─ Draw UI overlays (seat indicators, ghost furniture, grid)
        └─ Draw bubbles (speech, permission, waiting)
```

### Character FSM

```
States: IDLE | WALK | TYPE

IDLE (agent not active)
    └─ Wander AI: BFS to random walkable tile
       ├─ wanderMovesLeft: 3-6 moves per session
       ├─ Pause between moves: 2-20s (random)
       └─ Return to seat when agent becomes active

WALK (en route to seat)
    ├─ Path: BFS(currentTile, seatTile, tileMap, withOwnSeatUnblocked)
    ├─ Speed: 48 px/s, frame cycle: 0.15s
    └─ On arrival → snap to seat → TYPE

TYPE (agent active, at seat)
    ├─ Animation: type1/type2 (0.3s) or read1/read2 (Read/Grep tools)
    ├─ Sitting offset: +6px Y
    └─ seatTimer (120-240s) → transitions to IDLE when turn ends

Matrix Effect (spawn/despawn)
    ├─ Duration: 0.3s
    ├─ 16 vertical columns with staggered timing
    └─ FSM paused during effect; despawning chars skip hit-testing
```

### Sprite System

```
SpriteData = string[][]   // 2D array of "#RRGGBB" or "" (transparent)

Loading order:
  1. characterSpritesLoaded  → 6 pre-colored PNGs (112×96 each, 7 frames × 3 directions)
  2. floorTilesLoaded        → 7 grayscale patterns (16×16 each)
  3. wallTilesLoaded         → 16 auto-tile pieces (16×32 each, 4×4 grid)
  4. furnitureAssetsLoaded   → dynamic catalog + PNG sprites

Caching:
  spriteCache: Map<zoom, WeakMap<SpriteData, OffscreenCanvas>>
    └─ Key: zoom level (integer 1-10)
    └─ Value: pre-rendered OffscreenCanvas at correct pixel size
    └─ Outline sprites: separate cache entry per agent selection state

Colorization:
  ├─ Colorize mode (floor tiles, walls): grayscale → luminance → HSL (Photoshop-style)
  └─ Adjust mode (furniture, character hue shift): rotate H, shift S/B/C
```

### Layout Editor

```
Tools:
  SELECT       — click to select furniture, drag to move
  FLOOR        — paint floor tiles (7 patterns, HSBC color)
  WALL         — click/drag to add walls; click existing = remove
  ERASE        — set tiles to VOID (transparent, non-walkable)
  FURNITURE    — ghost preview (green=valid, red=invalid), R=rotate, T=toggle state
  PICK         — eyedropper: copies type+color from placed furniture
  EYEDROPPER   — copies floor pattern+color

Grid Expansion (FLOOR/WALL/ERASE tools):
  └─ Ghost border 1 tile outside grid → click → expandLayout() (max 64×64)
      └─ Furniture + character positions shift when expanding left/up

Undo/Redo:
  └─ 50-level stack; Ctrl+Z/Y; EditActionBar shows on dirty

Multi-stage Esc:
  exit furniture pick → deselect catalog → close tool tab → deselect furniture → close editor
```

---

## Part 3: Asset Pipeline (`scripts/`)

### Pattern: Sequential CLI Pipeline

7 offline stages for importing third-party pixel-art tilesets:

| Stage | Script | Method | Output |
|---|---|---|---|
| 0 | `0-import-tileset.ts` | Interactive CLI wrapper | Kicks off pipeline |
| 1 | `1-detect-assets.ts` | Flood-fill from seed pixel | Asset region bounding boxes |
| 2 | `2-asset-editor.html` | Browser UI (File System Access API) | Manual position/bounds corrections |
| 3 | `3-vision-inspect.ts` | Claude vision API (claude-opus-4) | Auto-generated metadata (name, category, footprint) |
| 4 | `4-review-metadata.html` | Browser UI | Metadata review and editing |
| 5 | `5-export-assets.ts` | pngjs pixel extraction | Individual PNGs + `furniture-catalog.json` |
| 6 | `export-characters.ts` | Palette baking | 6 character PNGs (`char_0.png`–`char_5.png`) |
| Util | `generate-walls.js` | Programmatic PNG generation | `walls.png` (4×4 grid, 16 auto-tile pieces) |

The pipeline outputs go to `webview-ui/public/assets/` and are copied to `dist/assets/` at build time.

---

## Extension ↔ Webview Message Protocol

### Extension → Webview

| Message | Key Payload | Trigger |
|---|---|---|
| `agentCreated` | `{id, folderName?}` | New terminal launched or adopted |
| `agentClosed` | `{id}` | Terminal closed |
| `agentToolStart` | `{id, toolId, status}` | `tool_use` block in JSONL |
| `agentToolDone` | `{id, toolId}` | `tool_result` (delayed 300ms) |
| `agentToolsClear` | `{id}` | `turn_duration` system record |
| `agentStatus` | `{id, status: 'active'\|'waiting'}` | Turn-end or text-idle timer |
| `agentToolPermission` | `{id}` | 7s timeout on non-exempt tool |
| `agentToolPermissionClear` | `{id}` | New JSONL data arrives |
| `subagentToolStart` | `{id, parentToolId, toolId, status}` | Subagent tool_use via agent_progress |
| `subagentToolDone` | `{id, parentToolId, toolId}` | Subagent tool_result (delayed 300ms) |
| `subagentToolPermission` | `{id, parentToolId}` | 7s timeout on subagent non-exempt tool |
| `subagentClear` | `{id, parentToolId}` | Task tool_result → subagent complete |
| `existingAgents` | `{agents[], agentMeta, folderNames}` | Webview ready / window focus |
| `layoutLoaded` | `{layout: OfficeLayout}` | Webview ready, import, cross-window sync |
| `characterSpritesLoaded` | `{characters: CharacterDirectionSprites[]}` | Asset loading |
| `floorTilesLoaded` | `{sprites: SpriteData[]}` | Asset loading |
| `wallTilesLoaded` | `{sprites: SpriteData[]}` | Asset loading |
| `furnitureAssetsLoaded` | `{catalog, sprites}` | Asset loading |
| `settingsLoaded` | `{soundEnabled}` | First webview message |

### Webview → Extension

| Message | Key Payload | Trigger |
|---|---|---|
| `openClaude` | — | "+ Agent" button click |
| `focusAgent` | `{id}` | Canvas click on character |
| `closeAgent` | `{id}` | Close button on ToolOverlay |
| `saveLayout` | `{layout: OfficeLayout}` | Edit mode save (debounced 500ms) |
| `saveAgentSeats` | `{seats: Record<id, {palette, hueShift, seatId}>}` | Character seat reassignment |
| `exportLayout` | — | Settings modal Export button |
| `importLayout` | `{layout}` | Settings modal Import button |
| `setSoundEnabled` | `{enabled: boolean}` | Settings modal sound toggle |

---

## Data Models

### OfficeLayout

```typescript
interface OfficeLayout {
  version: 1;
  cols: number;           // dynamic, default 20
  rows: number;           // dynamic, default 11
  tiles: TileType[];      // flat array, length = cols × rows
  furniture: PlacedFurniture[];
  tileColors?: FloorColor[]; // per-tile color (floor + wall), length = cols × rows
}

type TileType = 0 /* VOID */ | 1 /* FLOOR */ | 2 /* WALL */;

interface PlacedFurniture {
  uid: string;            // crypto.randomUUID()
  type: string;           // e.g. "DESK_FRONT", "MONITOR_FRONT_OFF"
  col: number;
  row: number;            // may be negative for wall-placeable items
  color?: FloorColor;     // per-item color override
}

interface FloorColor {
  h: number;    // hue 0-360
  s: number;    // saturation 0-100
  b: number;    // brightness -100 to 100
  c: number;    // contrast -100 to 100
  colorize?: boolean; // true = Photoshop Colorize mode; false = Adjust HSL shift
}
```

### FurnitureCatalogEntry

```typescript
interface FurnitureCatalogEntry {
  id: string;              // Unique type key (e.g. "DESK_FRONT")
  name: string;
  label: string;
  category: string;        // "desks" | "chairs" | "storage" | "electronics" | "decor" | "wall" | "misc"
  footprint: [number, number]; // [cols, rows]
  isDesk?: boolean;
  canPlaceOnWalls?: boolean;   // Wall-category items; bottom row must touch wall tile
  canPlaceOnSurfaces?: boolean; // Laptops, monitors, mugs; overlap with desk tiles
  groupId?: string;            // Rotation group or state group key
  orientation?: string;        // "front" | "back" | "left" | "right"
  state?: string;              // "on" | "off"
  backgroundTiles?: number;    // Top N rows allow overlap + character walk-through
}
```

### Character

```typescript
interface Character {
  id: number;             // Positive for real agents, negative for subagents
  agentId: number;        // Same as id for real agents; parent id for subagents
  palette: number;        // 0-5 (which pre-colored PNG)
  hueShift: number;       // Degrees (0 = no shift; ±45-315 for repeated agents)
  seatId: string | null;  // Assigned seat
  x: number; y: number;  // Canvas pixel position
  state: 'IDLE' | 'WALK' | 'TYPE';
  direction: 'DOWN' | 'UP' | 'LEFT' | 'RIGHT';
  frame: number;
  matrixEffect: 'spawn' | 'despawn' | null;
  isSubagent: boolean;
  parentAgentId?: number;
  bubble: { type: 'permission' | 'waiting' | null; ... };
}
```

---

## Critical Timings

| Constant | Value | Purpose |
|---|---|---|
| `TOOL_DONE_DELAY_MS` | 300ms | Prevents React batching from hiding brief active states |
| `PERMISSION_TIMER_DELAY_MS` | 7000ms | Non-exempt tool stuck on permission |
| `TEXT_IDLE_DELAY_MS` | 5000ms | Text-only turn detection (no tools used) |
| `JSONL_POLL_INTERVAL_MS` | 1000ms | Wait for new JSONL file to appear |
| `FILE_WATCHER_POLL_INTERVAL_MS` | 1000ms | fs.watchFile polling backup |
| `PROJECT_SCAN_INTERVAL_MS` | 1000ms | Detect new JSONL in project dir |
| `LAYOUT_FILE_POLL_INTERVAL_MS` | 2000ms | Cross-window layout sync polling |
| `MATRIX_EFFECT_DURATION_SEC` | 0.3s | Spawn/despawn animation length |
| `SEAT_REST_MIN_SEC` | 120s | Min idle time before character wanders |

---

## Key Architectural Decisions

| Decision | Rationale |
|---|---|
| `WebviewViewProvider` (not `WebviewPanel`) | Lives in the panel area alongside terminals; persistent across panel visibility changes |
| Separate esbuild + Vite builds | Extension host needs CJS+Node; webview needs ESM+Browser; different target platforms |
| User-level layout file (`~/.pixel-agents/`) | Shared across all VS Code windows and workspaces; atomic write prevents corruption |
| Triple-layer file watching | `fs.watch` is unreliable on Windows; polling backup ensures no missed JSONL updates |
| Imperative game state outside React | Prevents 60 FPS React re-renders; keeps game loop pure and predictable |
| Negative IDs for subagents | Simple integer space partition; no ID collision with real agents |
| 300ms tool-done delay | React batching would collapse rapid tool_use→tool_result pairs into invisible state transitions |
| Canvas DPR without `ctx.scale()` | Pixel-perfect rendering at all zoom levels; zoom = integer device-pixels-per-sprite-pixel |
| JSONL watching (not hook IPC) | Hooks captured at startup, env vars don't propagate into VS Code terminals |
