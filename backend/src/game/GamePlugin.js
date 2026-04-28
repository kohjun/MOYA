'use strict';

/**
 * Minimum contract every GamePlugin must satisfy.
 *
 * Identity fields (required on the object literal):
 *   gameType    : string   – unique snake_case key, matches DB game_type
 *   displayName : string   – human-readable label
 *   configSchema: Object   – { key: { type, default, min?, max? } }
 *   defaultConfig: Object  – flat map of schema defaults
 *   capabilities : string[] – feature tokens ('territory', 'faction', …)
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
 * Optional methods:
 *   getVoicePolicy(gameState, { userId?: string }) → VoicePolicy
 *     Returns how the voice room should behave for this session state.
 *     Runtime calls this on game state changes to set mute/open modes.
 *
 * VoicePolicy shape:
 * {
 *   mode       : 'open' | 'muted' | 'team',  // 'team' = team-only voice channels
 *   teamId?    : string,                     // required when mode === 'team' for a specific user
 * }
 *
 * GameState shape (stored in Redis under game:state:{sessionId}):
 * {
 *   gameType     : string,
 *   status       : 'in_progress' | 'finished',
 *   startedAt    : number,
 *   finishedAt   : number | null,
 *   alivePlayerIds: string[],
 *   pluginState  : Object,
 * }
 */

export {};
