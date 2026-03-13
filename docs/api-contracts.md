# API Contracts — PixelOffice

_Generated: 2026-03-12 | Scan: Exhaustive_

This document covers all message-passing contracts between the Extension Host and Webview. Since PixelOffice uses `postMessage()` as its inter-process communication layer, these "API contracts" are message schemas rather than HTTP endpoints.

---

## Extension → Webview Messages

All messages posted via `panel.webview.postMessage({ type, ...payload })`.

---

### `agentCreated`

Sent when a new Claude agent terminal is created or an existing terminal is adopted.

```typescript
{
  type: "agentCreated";
  id: number;          // Positive integer agent ID
  folderName?: string; // Workspace folder name (for multi-root workspaces)
}
```

**Triggers:** `launchNewTerminal()`, `adoptTerminalForFile()`
**Webview effect:** Spawns a new character with matrix effect animation; assigns palette + seat.

---

### `agentClosed`

Sent when a terminal is closed or removed.

```typescript
{
  type: "agentClosed";
  id: number;
}
```

**Triggers:** Terminal close event
**Webview effect:** Despawn character (matrix effect), release seat.

---

### `agentToolStart`

Sent when a `tool_use` block is parsed from a JSONL assistant message.

```typescript
{
  type: "agentToolStart";
  id: number;     // Agent ID
  toolId: string; // tool_use.id from JSONL (e.g. "toolu_01...")
  status: string; // Formatted display string (e.g. "Bash: npm run build")
}
```

**Triggers:** `processTranscriptLine()` on `assistant` + `tool_use` content
**Webview effect:** Character switches to TYPE/READ animation; status bubble shown.

---

### `agentToolDone`

Sent when a `tool_result` is parsed (delayed 300ms to prevent batching flicker).

```typescript
{
  type: "agentToolDone";
  id: number;
  toolId: string;
}
```

**Triggers:** `processTranscriptLine()` on `user` + `tool_result` content (delayed 300ms)
**Webview effect:** Removes tool from active set; character returns to idle if no more tools.

---

### `agentToolsClear`

Definitive turn-end signal. Clears ALL active tools for an agent simultaneously.

```typescript
{
  type: "agentToolsClear";
  id: number;
}
```

**Triggers:** `system` record with `subtype: "turn_duration"` — the reliable turn-end signal
**Webview effect:** Clears all active tools; character transitions to IDLE.

---

### `agentStatus`

Signals the agent's overall activity status (for bubble display and animation).

```typescript
{
  type: "agentStatus";
  id: number;
  status: "active" | "waiting";
}
```

**`active`** — turn just started (new user prompt detected)
**`waiting`** — turn ended (green checkmark bubble, auto-fades 2s)

**Triggers:**
- `waiting`: `turn_duration` signal OR text-idle timer fires after 5s of silence
- `active`: New user prompt content detected in JSONL

---

### `agentToolPermission`

Signals that a tool has been stuck (likely waiting for user permission) for longer than the timeout threshold.

```typescript
{
  type: "agentToolPermission";
  id: number;
}
```

**Triggers:** Permission timer fires after `PERMISSION_TIMER_DELAY_MS = 7000ms` with non-exempt tools still active
**Webview effect:** Shows amber `...` speech bubble on character.

**Exempt tools** (do NOT trigger permission timer): `Task`, `AskUserQuestion`

---

### `agentToolPermissionClear`

Clears the permission state when new JSONL data arrives (tool resumed execution).

```typescript
{
  type: "agentToolPermissionClear";
  id: number;
}
```

**Triggers:** `readNewLines()` detects new file content
**Webview effect:** Removes amber bubble.

---

### `subagentToolStart`

Subagent equivalent of `agentToolStart`. The subagent character is created on first receipt.

```typescript
{
  type: "subagentToolStart";
  id: number;          // Parent agent ID (subagent gets a derived negative ID in webview)
  parentToolId: string; // The Task tool's ID that spawned the subagent
  toolId: string;       // Inner subagent tool_use.id
  status: string;       // Formatted tool status string
}
```

**Triggers:** `progress` record with `data.type === "agent_progress"` + inner `tool_use`
**Webview effect:** Creates subagent character at closest seat to parent; shows tool animation.

---

### `subagentToolDone`

```typescript
{
  type: "subagentToolDone";
  id: number;
  parentToolId: string;
  toolId: string;
}
```

**Triggers:** `progress` record with `data.type === "agent_progress"` + inner `tool_result` (delayed 300ms)

---

### `subagentToolPermission`

```typescript
{
  type: "subagentToolPermission";
  id: number;
  parentToolId: string;
}
```

**Triggers:** Permission timer on parent when subagent runs non-exempt tool
**Webview effect:** Amber bubble on BOTH parent and subagent characters.

---

### `subagentClear`

The Task tool completed; subagent should despawn.

```typescript
{
  type: "subagentClear";
  id: number;
  parentToolId: string;
}
```

**Triggers:** `tool_result` for a Task `tool_use` block
**Webview effect:** Subagent character despawns with matrix effect.

---

### `existingAgents`

Sent on webview ready or window activation to restore existing agent state.

```typescript
{
  type: "existingAgents";
  agents: number[];              // List of active agent IDs
  agentMeta: Record<number, {
    palette: number;             // 0-5
    hueShift: number;            // degrees
    seatId: string | null;
  }>;
  folderNames: Record<number, string>; // agentId → workspace folder name
}
```

**Triggers:** Webview `ready` message, window focus
**Webview effect:** Restores all characters with `skipSpawnEffect: true` (instant appearance).

---

### `layoutLoaded`

Delivers the full office layout to the webview.

```typescript
{
  type: "layoutLoaded";
  layout: {
    version: 1;
    cols: number;
    rows: number;
    tiles: number[];          // TileType: 0=VOID, 1=FLOOR, 2=WALL
    furniture: Array<{
      uid: string;
      type: string;           // e.g. "DESK_FRONT", "CHAIR_BACK"
      col: number;
      row: number;            // may be negative for wall items
      color?: {
        h: number; s: number; b: number; c: number; colorize?: boolean;
      };
    }>;
    tileColors?: Array<{      // per-tile floor/wall colorization
      h: number; s: number; b: number; c: number; colorize?: boolean;
    } | null>;
  };
}
```

**Triggers:** Webview ready, user import, cross-window file change
**Webview effect:** Full layout rebuild; character seat reassignment.

---

### `characterSpritesLoaded`

Delivers pre-colored character sprite data for all 6 palettes.

```typescript
{
  type: "characterSpritesLoaded";
  characters: Array<{          // Length: 6 (one per palette)
    down: SpriteData[][];      // 7 frames × [rows][cols] hex strings
    up: SpriteData[][];
    right: SpriteData[][];
    // left is derived at runtime by horizontally flipping right
  }>;
}
```

**Sprite layout per character PNG** (112×96):
- 7 frames × 16px wide = 112px
- 3 directions × 32px tall = 96px
- Frame order: walk1, walk2, walk3, type1, type2, read1, read2
- Row 0=down, Row 1=up, Row 2=right

---

### `floorTilesLoaded`

```typescript
{
  type: "floorTilesLoaded";
  sprites: string[][][];  // [patternIndex][row][col] = "#RRGGBB" or ""
                          // 7 patterns, each 16×16
}
```

---

### `wallTilesLoaded`

```typescript
{
  type: "wallTilesLoaded";
  sprites: string[][][];  // [bitmaskIndex][row][col] = "#RRGGBB" or ""
                          // 16 pieces, each 16×32 (extends 16px above tile)
}
```

Bitmask encoding: N=1, E=2, S=4, W=8 → values 0-15.

---

### `furnitureAssetsLoaded`

```typescript
{
  type: "furnitureAssetsLoaded";
  catalog: Array<{
    id: string;
    name: string;
    label: string;
    category: string;
    footprint: [number, number];
    isDesk?: boolean;
    canPlaceOnWalls?: boolean;
    canPlaceOnSurfaces?: boolean;
    groupId?: string;
    orientation?: string;
    state?: string;
    backgroundTiles?: number;
  }>;
  sprites: Record<string, string[][]>; // type_id → SpriteData
}
```

---

### `settingsLoaded`

```typescript
{
  type: "settingsLoaded";
  soundEnabled: boolean;
}
```

**Triggers:** First message to webview (initialization)
**Webview effect:** Sets initial sound toggle state.

---

## Webview → Extension Messages

All messages posted via `vscode.postMessage({ type, ...payload })`.

---

### `openClaude`

```typescript
{ type: "openClaude" }
```

**Trigger:** "+ Agent" button in BottomToolbar
**Extension effect:** `launchNewTerminal()` — creates a new VS Code terminal running `claude --session-id <uuid>`.

---

### `focusAgent`

```typescript
{
  type: "focusAgent";
  id: number;  // Agent ID (subagent clicks send parent ID)
}
```

**Trigger:** Canvas click on a character
**Extension effect:** `terminal.show()` — brings the agent's terminal to focus.

---

### `closeAgent`

```typescript
{
  type: "closeAgent";
  id: number;
}
```

**Trigger:** Close button (×) on ToolOverlay
**Extension effect:** `terminal.dispose()` — terminates the Claude terminal.

---

### `saveLayout`

```typescript
{
  type: "saveLayout";
  layout: OfficeLayout;  // Full layout object (see layoutLoaded schema above)
}
```

**Trigger:** Edit mode changes (debounced 500ms)
**Extension effect:** `writeLayoutToFile()` — atomic write to `~/.pixel-agents/layout.json`.

---

### `saveAgentSeats`

```typescript
{
  type: "saveAgentSeats";
  seats: Record<number, {  // agentId → metadata
    palette: number;
    hueShift: number;
    seatId: string | null;
  }>;
}
```

**Trigger:** Character seat reassignment (click character → click seat)
**Extension effect:** Persists to workspace state; restored on next `existingAgents`.

---

### `exportLayout`

```typescript
{ type: "exportLayout" }
```

**Trigger:** Settings modal "Export Layout" button
**Extension effect:** Opens a file save dialog; writes current layout JSON to user-chosen path.

---

### `importLayout`

```typescript
{
  type: "importLayout";
  layout: OfficeLayout;
}
```

**Trigger:** Settings modal "Import Layout" button (after user selects a file)
**Extension effect:** Validates `version === 1` and `tiles` array; writes to `~/.pixel-agents/layout.json`; pushes `layoutLoaded` back to webview.

---

### `setSoundEnabled`

```typescript
{
  type: "setSoundEnabled";
  enabled: boolean;
}
```

**Trigger:** Settings modal sound toggle checkbox
**Extension effect:** Persists to `globalState` key `pixel-agents.soundEnabled`.

---

## Tool Status Formatting

The `status` field in `agentToolStart` / `subagentToolStart` is formatted by `formatToolStatus()` in the extension:

| Tool Name | Format |
|---|---|
| `Bash` | `Bash: <truncated command>` |
| `Write` | `Write: <filename>` |
| `Edit` | `Edit: <filename>` |
| `Read` | `Read: <filename>` |
| `Grep` | `Grep: <pattern>` |
| `Glob` | `Glob: <pattern>` |
| `WebFetch` | `WebFetch: <truncated URL>` |
| `Task` | `Task: <truncated description>` |
| Others | `<ToolName>: <truncated input>` |

Tool animation in webview is determined by `STATUS_TO_TOOL` mapping:
- **TYPE animation** (typing): Write, Edit, Bash, Task, NotebookEdit, TodoWrite, TodoRead
- **READ animation** (reading): Read, Grep, Glob, WebFetch, WebSearch, all others
