# Game Plugin Architecture

> Target architecture for MOYA's game plugin system.  
> Current state: `AmongUsPlugin` (live) + `FantasyWarsPlugin` (stub).

---

## Overview

```
Backend                          Frontend
────────────────────────────────────────────────────────
GamePluginRegistry               GameCatalogRepository
  └─ register(plugin)              └─ listGames() → GameDescriptor[]
  └─ list() → PluginDescriptor[]   └─ getGame(gameType)
  └─ get(gameType) → Plugin
                                 GameModePlugin (UI layer)
Plugin Contract                    └─ buildBottomActions(ctx)
  gameType: string                 └─ buildStackLayers(ctx)
  displayName: string
  configSchema: Record
  defaultConfig: Record
  capabilities: string[]
  ─── runtime methods ───
  assignRoles(members, config)
  checkWinCondition(gameState)
  getCurrentPhase(gameState)
  getSystemPrompt(role, nickname)
  buildStateContext(gameState, player)
  getKnowledgeChunks()
```

---

## Plugin Contract (Backend)

Each plugin **must** export an object that satisfies:

```js
{
  // ── Identity ──────────────────────────────────────────────
  gameType:    string,          // unique snake_case key, e.g. 'among_us'
  displayName: string,          // human-readable, e.g. '어몽어스'

  // ── Configuration schema ──────────────────────────────────
  configSchema: {
    [key: string]: {
      type: 'number' | 'string' | 'boolean',
      default: any,
      min?: number,   // for numbers
      max?: number,
    }
  },
  defaultConfig: Record<string, any>,  // flat map of schema defaults

  // ── Feature flags ─────────────────────────────────────────
  capabilities: string[],
  // Known capability tokens:
  //   'kill'        – players can eliminate each other
  //   'vote'        – emergency meeting / vote mechanic
  //   'mission'     – task/mission system active
  //   'proximity'   – distance-based triggers
  //   'item'        – item pickup/use system
  //   'territory'   – area control mechanic (fantasy_wars)
  //   'faction'     – multi-team faction system (fantasy_wars)

  // ── Runtime methods ───────────────────────────────────────
  assignRoles(members: Member[], config: Record): RoleAssignment[],
  checkWinCondition(gameState: GameState): WinResult | null,
  getCurrentPhase(gameState: GameState): string,
  getSystemPrompt(role: string, nickname: string): string,
  buildStateContext(gameState: GameState, player: Player): string,
  getKnowledgeChunks(): Promise<KnowledgeChunk[]>,
}
```

---

## Registry API

```js
GamePluginRegistry.register(plugin)        // boot-time registration
GamePluginRegistry.get(gameType)           // throws if not found
GamePluginRegistry.list()                  // for catalog API
// list() returns: Array<{ gameType, displayName, configSchema,
//                          defaultConfig, capabilities }>
```

---

## REST Catalog Endpoint

```
GET /games
→ 200 { games: PluginDescriptor[] }

GET /games/:gameType
→ 200 { game: PluginDescriptor }
→ 404 if unknown gameType
```

---

## Frontend Boundary

### Models (`game_catalog_models.dart`)

```dart
class GameDescriptor {
  final String gameType;
  final String displayName;
  final Map<String, dynamic> configSchema;
  final Map<String, dynamic> defaultConfig;
  final List<String> capabilities;
}

class GameCatalog {
  final List<GameDescriptor> games;
}
```

### Repository (`game_catalog_repository.dart`)

```dart
abstract class GameCatalogRepository {
  Future<GameCatalog> listGames();
  Future<GameDescriptor> getGame(String gameType);
}
```

### UI Plugin (`GameModePlugin`)

`GameModePlugin` remains a **pure UI concern** — it maps `SessionType → UI modules`.  
It does NOT carry game rules (those live in the backend plugin).

---

## Plugin Lifecycle

```
Boot
  server.js
    └─ import './game/index.js'          ← registers all plugins
         └─ GamePluginRegistry.register(AmongUsPlugin)
         └─ GamePluginRegistry.register(FantasyWarsPlugin)  ← stub

Request: POST /sessions/:id/start
  startGameService
    └─ plugin = GamePluginRegistry.get(session.game_type ?? 'among_us')
    └─ roles  = plugin.assignRoles(members, config)
    └─ ... emit roles, missions, etc.
```

---

## Plugin Status

| Plugin | gameType | Status | Capabilities |
|---|---|---|---|
| AmongUsPlugin | `among_us` | ✅ Live (legacy) | kill, vote, mission, proximity, item |
| FantasyWarsPlugin | `fantasy_wars` | 🚧 Stub | territory, faction, mission |

---

## Adding a New Plugin

1. Create `backend/src/game/MyGamePlugin.js` implementing the contract above.
2. Register in `backend/src/game/index.js`.
3. Add `GameDescriptor` entry in frontend (auto-fetched from `/games` catalog).
4. Add `case SessionType.myGame: return MyGameModePlugin()` in `createPlugin()`.
