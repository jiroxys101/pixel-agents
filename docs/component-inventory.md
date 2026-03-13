# Component Inventory — PixelOffice

_Generated: 2026-03-12 | Scan: Exhaustive_

---

## React Components (webview-ui/src/)

### Top-Level: `App.tsx`

**Role:** Composition root. Wires all hooks and components together. No business logic.

**Hooks consumed:**
| Hook | Purpose |
|---|---|
| `useExtensionMessages()` | Handles all VS Code postMessage events; updates OfficeState imperatively |
| `useEditorActions()` | Edit mode state (isDirty, editMode, undo/redo callbacks) |
| `useEditorKeyboard()` | Keyboard shortcuts (R=rotate, Ctrl+Z/Y=undo/redo, Esc=exit edit) |

**Renders:** `OfficeCanvas`, `ToolOverlay`, `EditorToolbar`, `BottomToolbar`, `ZoomControls`, `SettingsModal`, `DebugView`, `EditActionBar` (inline)

---

## UI Shell Components (`webview-ui/src/components/`)

### `BottomToolbar.tsx`

**Role:** Primary user action bar, anchored to bottom of viewport.

**Controls:**
- **+ Agent** button → posts `openClaude` message
- **Layout** button → toggles edit mode
- **Settings** button → opens `SettingsModal`

**Styling:** Pixel-art aesthetic (`borderRadius: 0`, `--pixel-bg`, `2px solid` border, `2px 2px 0px` hard shadow)

---

### `ZoomControls.tsx`

**Role:** Zoom in/out overlay, anchored top-right.

**Controls:**
- **+** → increment zoom (max 10)
- **−** → decrement zoom (min 1)
- **Label** → shows current zoom level

**State:** Reads/writes `zoom` via callback from `App.tsx`.

---

### `SettingsModal.tsx`

**Role:** Centered modal for extension settings.

**Controls:**
- **Sound Notifications** checkbox → posts `setSoundEnabled` message
- **Export Layout** button → posts `exportLayout` message
- **Import Layout** button → file dialog (webview File System Access API) → posts `importLayout`
- **Debug** checkbox → toggles `DebugView`
- **Close** button (×)

**Modal behavior:** Click outside or press Esc closes.

---

### `DebugView.tsx`

**Role:** Developer overlay displaying raw game state.

**Shows:**
- Active agent IDs and their tool states
- Camera position, zoom level, DPR
- Frame rate and loop timing
- Character positions and FSM states

**Visibility:** Toggled via Settings modal; hidden by default.

---

## Office Canvas Component (`webview-ui/src/office/components/`)

### `OfficeCanvas.tsx`

**Role:** Owns the HTML `<canvas>` element. Manages resize, DPR scaling, game loop, and input events.

**Responsibilities:**
- Create and size canvas (physical px = logical px × zoom, no DPR scaling)
- Start `gameLoop` (requestAnimationFrame) on mount
- Handle mouse events:
  - **Click** → hit-test characters (select, focus) or furniture (select in edit)
  - **Middle-mouse drag** → pan camera
  - **Right-click** → erase in edit mode
  - **Drag** → move selected furniture in SELECT tool
  - **Hover** → update hovered character for ToolOverlay
- Handle webview resize via ResizeObserver
- Forward editor interactions to `editorState` + `editorActions`

**DPR handling:** Canvas element `width/height` set to `Math.round(cols * TILE_SIZE * zoom)`, no `ctx.scale()`. Zoom multiplier is the device-pixel-level zoom.

---

### `ToolOverlay.tsx`

**Role:** Floating label rendered above the hovered or selected character.

**Shows:**
- Agent name / folder (from `folderNames`)
- Active tool status string (e.g. "Bash: npm run build")
- Permission bubble (amber `...`) when stuck on permission
- Waiting bubble (green ✓) after turn completes
- **Close** button (×) → posts `closeAgent` message

**Positioning:** Computed from character canvas position → CSS `position: absolute` overlay.

---

## Editor Components (`webview-ui/src/office/editor/`)

### `EditorToolbar.tsx`

**Role:** Full editor UI panel shown when layout edit mode is active.

**Sections:**
| Section | Contents |
|---|---|
| Tool selector | SELECT, FLOOR, WALL, ERASE, FURNITURE tabs |
| Floor palette | 7 floor pattern thumbnails with HSBC sliders |
| Wall palette | Wall color HSBC sliders |
| Furniture palette | Scrollable grid of catalog items (1 per rotation group) |
| Item controls | R (rotate), T (toggle state), Delete button, HSBC color sliders |

**Furniture catalog display:**
- Groups items by `category` tab (Desks, Chairs, Storage, Electronics, Decor, Wall, Misc)
- Shows 1 representative item per `groupId` (prefers `orientation: "front"`)
- Eyedropper and Pick tools update the selected catalog item

**Color sliders:** Hue, Saturation, Brightness, Contrast + Colorize checkbox. Shared between floor, wall, and selected furniture (in Adjust mode for furniture).

---

## Custom Hooks (`webview-ui/src/hooks/`)

### `useExtensionMessages.ts`

**Role:** Central message handler. Receives all messages from the extension host.

**State managed:**
```typescript
{
  agents: number[];                       // Active agent IDs
  agentMeta: Record<number, AgentMeta>;   // palette, hueShift, seatId
  folderNames: Record<number, string>;    // agentId → folder label
  toolStates: Record<number, ToolState>;  // agentId → {toolId, status}[]
}
```

**Message routing:**
- `agentCreated` → add to agents list; call `officeState.addCharacter()`
- `agentClosed` → remove from list; call `officeState.removeCharacter()`
- `agentToolStart/Done/Clear` → update `toolStates`; update character animation
- `agentStatus` → set waiting bubble
- `agentToolPermission` → show permission bubble on character
- `subagent*` → manage subagent characters in `officeState`
- `existingAgents` → bulk restore with `skipSpawnEffect: true`
- `layoutLoaded` → call `officeState.rebuildFromLayout()`
- `*Loaded` (assets) → populate sprite data, build furniture catalog

**Pattern:** Imperative updates to `OfficeState` singleton + selective `setState` calls to trigger React re-renders where needed.

---

### `useEditorActions.ts`

**Role:** Edit mode state machine and action callbacks.

**State:**
```typescript
{
  editMode: boolean;
  isDirty: boolean;
  activeTool: EditTool;
  selectedCatalogItem: FurnitureCatalogEntry | null;
  floorColor: FloorColor;
  wallColor: FloorColor;
  undoCount: number;  // Trigger re-render when undo stack changes
  redoCount: number;
}
```

**Callbacks exposed:**
- `toggleEditMode()` — enter/exit layout editor
- `handleSave()` — posts `saveLayout` message
- `handleUndo()` / `handleRedo()` — delegates to `editorState`
- `handleReset()` — reverts to last saved layout
- `setActiveTool()`, `setFloorColor()`, `setWallColor()`

---

### `useEditorKeyboard.ts`

**Role:** Keyboard shortcut effect. Runs as a `useEffect` when edit mode is active.

**Shortcuts:**
| Key | Action |
|---|---|
| `R` | Rotate selected furniture |
| `T` | Toggle state of selected furniture |
| `Ctrl+Z` | Undo |
| `Ctrl+Y` / `Ctrl+Shift+Z` | Redo |
| `Esc` | Multi-stage exit (see architecture.md) |
| `Delete` / `Backspace` | Delete selected furniture |

---

## Game Engine Modules (`webview-ui/src/office/engine/`)

### `gameLoop.ts`

**Role:** `requestAnimationFrame` loop orchestrator.

**Interface:**
```typescript
startGameLoop(
  updateFn: (dt: number) => void,
  renderFn: (ctx: CanvasRenderingContext2D) => void,
  canvas: HTMLCanvasElement
): () => void  // Returns stop function
```

Delta time is capped at `MAX_DELTA_TIME_SEC = 0.1s` to prevent physics explosion on tab unfocus.

---

### `officeState.ts`

**Role:** Central game world state manager.

**Key methods:**
| Method | Purpose |
|---|---|
| `rebuildFromLayout(layout)` | Parse tiles, furniture, tileColors; rebuild TileMap and FurnitureInstances |
| `addCharacter(id, meta)` | Create new character; assign seat (palette + hueShift via `pickDiversePalette`) |
| `removeCharacter(id)` | Despawn character; release seat |
| `updateCharacterToolState(id, toolStates)` | Switch FSM state based on active tools |
| `getCharacterAt(x, y, zoom)` | Hit-test: find character at canvas click position |
| `getFurnitureAt(col, row)` | Find furniture at grid position |
| `rebuildFurnitureInstances()` | Re-sort furniture + apply auto-state (ON sprites near active desks) |
| `update(dt)` | Tick all character FSMs, bubble timers |

**Singleton pattern:** `officeState` is a module-level instance, not React state.

---

### `characters.ts`

**Role:** Character FSM logic and wander AI.

**Key functions:**
| Function | Purpose |
|---|---|
| `updateCharacter(char, dt, officeState)` | Advance FSM, animation, pathfinding |
| `pickDiversePalette(characters)` | Choose least-used palette; random hueShift for repeats |
| `hueShiftSprites(sprites, hueShift)` | Apply `adjustSprite()` to all direction frames |
| `getSpritesForCharacter(char)` | Return correct sprite set (palette + hueShift from cache) |

---

### `renderer.ts`

**Role:** Canvas draw pipeline. Called every frame by `gameLoop`.

**Draw order:**
1. Clear canvas (`clearRect`)
2. Apply camera transform (translate for pan, no scale — zoom handled in coordinates)
3. **Floor pass** — draw colorized floor tiles for all FLOOR tiles
4. **Wall base pass** — draw flat wall base color for WALL tiles
5. **Entity collection** — gather furniture instances + wall sprites + character render data
6. **Z-sort** — sort all entities by `zY` ascending
7. **Entity draw pass** — `drawSprite()` for each entity in z-order
8. **Bubble pass** — draw speech/permission/waiting bubbles above characters
9. **Editor overlays** — seat highlights, ghost furniture, grid, expansion hints, selection outlines

**`drawSprite(ctx, sprite, x, y, zoom, isFlipped?)`:**
- Looks up `OffscreenCanvas` from `spriteCache` for current zoom
- `drawImage()` at pixel-aligned position

---

### `matrixEffect.ts`

**Role:** Matrix-style spawn/despawn digital rain animation.

**Algorithm:**
```
16 vertical columns, each column has:
  - Random delay offset (0-0.2s)
  - Rain sweep from top to bottom over 0.3s

Spawn: columns reveal character pixels behind the sweep
Despawn: columns consume character pixels with green rain trails
Per-pixel: compare column sweep progress to pixel Y position
```

Called from `renderer.ts` instead of `drawSprite()` when `char.matrixEffect !== null`.

---

## Layout Modules (`webview-ui/src/office/layout/`)

### `furnitureCatalog.ts`

**Role:** Catalog management and dynamic lookups.

**Key functions:**
| Function | Purpose |
|---|---|
| `buildDynamicCatalog(entries)` | Build `rotationGroups` and `stateGroups` Maps |
| `getCatalogEntry(type)` | Lookup by type string |
| `getRotatedType(type)` | Next orientation in rotation group |
| `getToggledType(type)` | Toggle ON/OFF state variant |
| `getPaletteItems()` | One item per group (front orientation preferred) |

---

### `layoutSerializer.ts`

**Role:** Converts between `OfficeLayout` (persisted) and runtime structures.

**Key functions:**
| Function | Purpose |
|---|---|
| `layoutToFurnitureInstances(layout, sprites, catalog)` | Build z-sorted FurnitureInstance[] with colorization |
| `layoutToSeats(layout, catalog)` | Extract Seat[] from chair furniture |
| `getBlockedTiles(layout, catalog, exceptUid?)` | Set of `"col,row"` strings that are impassable |
| `getPlacementBlockedTiles(layout, catalog, exceptUid?)` | Stricter blocked set for placement validation |
| `canPlaceFurniture(layout, catalog, entry, col, row)` | Validate placement (checks walls, surfaces, overlap) |
| `expandLayout(layout, direction)` | Grow grid by 1 tile; shift furniture/colors if needed |

---

### `tileMap.ts`

**Role:** Walkability grid and BFS pathfinding.

**Key functions:**
| Function | Purpose |
|---|---|
| `buildTileMap(layout, blockedTiles)` | Create 2D boolean walkability grid |
| `findPath(startCol, startRow, endCol, endRow, tileMap)` | BFS; returns path as `{col, row}[]` or `null` |
| `withOwnSeatUnblocked(blockedTiles, seatTile)` | Returns new blocked set with character's own seat tile removed |

---

## Sprite Modules (`webview-ui/src/office/sprites/`)

### `spriteData.ts`

**Role:** Pixel data storage. Contains:
- 6 pre-colored character sprite sets (loaded from extension via `characterSpritesLoaded`)
- Fallback hardcoded character templates (used if PNGs not loaded)
- Furniture sprite data (loaded from extension via `furnitureAssetsLoaded`)
- Tile sprites: floor patterns, wall pieces
- Bubble sprites: permission dots, waiting checkmark

### `spriteCache.ts`

**Role:** Sprite rendering cache keyed by zoom level.

```typescript
// Cache structure:
Map<zoom: number, WeakMap<SpriteData, OffscreenCanvas>>

// Outline cache (for selected characters):
Map<zoom: number, WeakMap<SpriteData, OffscreenCanvas>>
```

Each `SpriteData` (2D hex array) is rendered to an `OffscreenCanvas` once per zoom level. Cache is automatically GC'd when SpriteData objects are released.

---

## Colorization Module (`webview-ui/src/office/colorize.ts`)

**Role:** Dual-mode pixel colorization for floor tiles, walls, furniture, and character hue shifts.

**Exported functions:**
| Function | Mode | Use |
|---|---|---|
| `colorizeSprite(sprite, color)` | Colorize (Photoshop-style) | Floor tiles, walls — grayscale input → fixed HSL |
| `adjustSprite(sprite, color)` | Adjust (HSL shift) | Furniture color, character hue shift |
| `colorizeFloorSprite(sprite, color)` | Always Colorize | Floor tiles |

**Cache:** Generic `Map<string, SpriteData>` keyed by `"{type}-{h}-{s}-{b}-{c}-{colorize}"`.

---

## Auto-State System

When `officeState.rebuildFurnitureInstances()` runs, electronics near active agents are automatically swapped to their ON sprite:

```
For each active character (TYPE state):
  1. Determine facing direction
  2. Check 3 tiles deep in facing direction, 1 tile to each side
  3. For any desk tile found in that zone:
     4. Check all furniture items adjacent to that desk tile
     5. If item has a state group (on/off variants):
        → Swap to ON sprite in render (does NOT modify saved layout)
```

This is purely visual — the layout file always stores the OFF variant.
