import { redisClient } from '../config/redis.js';
import VoteSystem from '../game/VoteSystem.js';

const GAME_TTL = 86400;

// Redis key helpers — single source of truth for key naming
export const keys = {
  state:   (sessionId) => `game:state:${sessionId}`,
  started: (sessionId) => `game:started:${sessionId}`,
};

// ─────────────────────────────────────────────────────────────────────────────
// normalizeGameState — generic; AmongUs fields live in pluginState
// Handles both legacy format (root-level impostors/killLog) and new format.
// ─────────────────────────────────────────────────────────────────────────────

export const normalizeGameState = (raw = {}) => {
  const alivePlayerIds = Array.isArray(raw.alivePlayerIds)  ? raw.alivePlayerIds
                       : Array.isArray(raw.aliveMembers)    ? raw.aliveMembers
                       : [];

  // Migrate legacy root-level AmongUs fields into pluginState
  const pluginState = raw.pluginState ?? {
    impostors:    Array.isArray(raw.impostors)  ? raw.impostors  : [],
    killLog:      Array.isArray(raw.killLog)    ? raw.killLog    : [],
    meetingCount: Number.isInteger(raw.meetingCount) ? raw.meetingCount : 0,
  };

  return {
    gameType:       raw.gameType    ?? 'among_us',
    status:         raw.status === 'playing' ? 'in_progress' : (raw.status ?? 'in_progress'),
    startedAt:      raw.startedAt   ?? Date.now(),
    finishedAt:     raw.finishedAt  ?? null,
    alivePlayerIds,
    pluginState,
  };
};

// ─────────────────────────────────────────────────────────────────────────────
// saveGameState — always writes to new key namespace
// ─────────────────────────────────────────────────────────────────────────────

export const saveGameState = async (sessionId, rawGameState, ttlSeconds = GAME_TTL) => {
  const normalized = normalizeGameState(rawGameState);
  await redisClient.set(keys.state(sessionId), JSON.stringify(normalized), { EX: ttlSeconds });
  return normalized;
};

// ─────────────────────────────────────────────────────────────────────────────
// readGameState — reads from new key, falls back to legacy key for migration
// ─────────────────────────────────────────────────────────────────────────────

export const readGameState = async (sessionId) => {
  let raw = await redisClient.get(keys.state(sessionId));
  // Legacy fallback: old key format was `game:{sessionId}`
  if (!raw) raw = await redisClient.get(`game:${sessionId}`);
  if (!raw) return null;
  return normalizeGameState(JSON.parse(raw));
};

// ─────────────────────────────────────────────────────────────────────────────
// syncMediaRoomState
// ─────────────────────────────────────────────────────────────────────────────

export const syncMediaRoomState = async (sessionId, room) => {
  if (!room) return null;

  const gameState = await readGameState(sessionId);
  if (!gameState) {
    room.setAlivePeers([...room.peers.keys()]);
    room.openLobbyVoice();
    return null;
  }

  room.setAlivePeers(gameState.alivePlayerIds);

  if (VoteSystem.hasActiveMeeting(sessionId)) {
    room.startEmergencyMeeting();
  } else if (gameState.status === 'in_progress') {
    room.muteAll();
  } else {
    room.openLobbyVoice();
  }

  return gameState;
};

// ─────────────────────────────────────────────────────────────────────────────
// ensureMediaRoomForSocket
// ─────────────────────────────────────────────────────────────────────────────

export const ensureMediaRoomForSocket = async ({ socket, mediaServer, sessionId }) => {
  if (!mediaServer) return null;

  const room = await mediaServer.getOrCreateRoom(sessionId);
  room.addPeer({ userId: socket.user.id, socket, isAlive: true });
  await syncMediaRoomState(sessionId, room);
  return room;
};
