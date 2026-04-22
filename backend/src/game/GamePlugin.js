'use strict';

/**
 * Minimum contract every GamePlugin must satisfy.
 *
 * Identity fields (required on the object literal):
 *   gameType    : string   – unique snake_case key, matches DB game_type
 *   displayName : string   – human-readable label
 *   configSchema: Object   – { key: { type, default, min?, max? } }
 *   defaultConfig: Object  – flat map of schema defaults
 *   capabilities : string[] – feature tokens ('kill', 'vote', …)
 *
 * Methods (all plugins must implement):
 *   startSession({ session, members, config, io })
 *     → Promise<{ gameState: GameState, roles: RoleAssignment[] }>
 *
 *   getPublicState(gameState)
 *     → Object   — sent to all players on game:request_state
 *
 *   getPrivateState(gameState, userId)
 *     → Object   — merged into state update for a specific player
 *
 *   handleEvent(eventName, payload, ctx)
 *     → Promise<boolean>  — true = handled, false = not this plugin's event
 *
 *   checkWinCondition(gameState)
 *     → { winner: string, reason: string } | null
 *
 * GameState shape (stored in Redis under game:state:{sessionId}):
 * {
 *   gameType     : string,
 *   status       : 'in_progress' | 'finished',
 *   startedAt    : number,        // Date.now()
 *   finishedAt   : number | null,
 *   alivePlayerIds: string[],
 *   pluginState  : Object,        // plugin-owned, opaque to the runtime
 * }
 *
 * RoleAssignment shape:
 * {
 *   userId     : string,
 *   role       : string,
 *   team       : string,
 *   privateData: Object,  // emitted only to this player via game:role_assigned
 * }
 *
 * EventContext shape (ctx passed to handleEvent):
 * {
 *   io         : SocketIO.Server,
 *   socket     : SocketIO.Socket,
 *   userId     : string,
 *   sessionId  : string,
 *   gameState  : GameState,
 *   saveState  : (gs: GameState) => Promise<void>,
 * }
 */

// No runtime enforcement — this file is the living contract document.
export {};
