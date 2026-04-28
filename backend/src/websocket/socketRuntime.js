import { redisClient } from '../config/redis.js';
import { GamePluginRegistry } from '../game/index.js';

const GAME_TTL = 86400;
const DEFAULT_GAME_TYPE = 'fantasy_wars_artifact';
const LOBBY_CHANNEL = 'lobby';

export const keys = {
  state:   (sessionId) => `game:state:${sessionId}`,
  started: (sessionId) => `game:started:${sessionId}`,
};

export const normalizeGameState = (raw = {}) => {
  const alivePlayerIds = Array.isArray(raw.alivePlayerIds) ? raw.alivePlayerIds
                       : Array.isArray(raw.aliveMembers)   ? raw.aliveMembers
                       : [];

  return {
    gameType:       raw.gameType   ?? DEFAULT_GAME_TYPE,
    status:         raw.status === 'playing' ? 'in_progress' : (raw.status ?? 'in_progress'),
    startedAt:      raw.startedAt  ?? Date.now(),
    finishedAt:     raw.finishedAt ?? null,
    alivePlayerIds,
    pluginState:    raw.pluginState ?? {},
  };
};

export const saveGameState = async (sessionId, rawGameState, ttlSeconds = GAME_TTL) => {
  const normalized = normalizeGameState(rawGameState);
  await redisClient.set(keys.state(sessionId), JSON.stringify(normalized), { EX: ttlSeconds });
  return normalized;
};

export const readGameState = async (sessionId) => {
  let raw = await redisClient.get(keys.state(sessionId));
  if (!raw) raw = await redisClient.get(`game:${sessionId}`);
  if (!raw) return null;
  return normalizeGameState(JSON.parse(raw));
};

// Route peers to channels based on the plugin's voice policy.
// mode === 'open'  → everyone → 'lobby'                (voiceState = lobby)
// mode === 'muted' → everyone → 'lobby'                (voiceState = muted)
// mode === 'team'  → each peer → 'team:{teamId}'       (voiceState = lobby, channel isolation handles siloing)
const applyVoicePolicyToRoom = (room, plugin, gameState) => {
  if (!plugin?.getVoicePolicy) {
    room.muteAll();
    return;
  }

  const peers = [...room.peers.values()];
  const policies = peers.map((peer) => ({
    peer,
    policy: plugin.getVoicePolicy(gameState, { userId: peer.userId }) ?? { mode: 'muted' },
  }));

  const anyTeam = policies.some((entry) => entry.policy.mode === 'team');

  policies.forEach(({ peer, policy }) => {
    const targetChannel = policy.mode === 'team' && policy.teamId
      ? `team:${policy.teamId}`
      : LOBBY_CHANNEL;
    if (peer.channelId !== targetChannel) {
      room.setPeerChannel(peer.userId, targetChannel);
    }
  });

  if (anyTeam) {
    room.openLobbyVoice();
    return;
  }

  const allMuted = policies.every((entry) => entry.policy.mode === 'muted');
  if (allMuted) {
    room.muteAll();
  } else {
    room.openLobbyVoice();
  }
};

export const syncMediaRoomState = async (sessionId, room) => {
  if (!room) return null;

  const gameState = await readGameState(sessionId);
  if (!gameState) {
    room.setAlivePeers([...room.peers.keys()]);
    [...room.peers.values()].forEach((peer) => {
      if (peer.channelId !== LOBBY_CHANNEL) {
        room.setPeerChannel(peer.userId, LOBBY_CHANNEL);
      }
    });
    room.openLobbyVoice();
    return null;
  }

  room.setAlivePeers(gameState.alivePlayerIds);

  const plugin = GamePluginRegistry.get(gameState.gameType);
  applyVoicePolicyToRoom(room, plugin, gameState);

  return gameState;
};

export const ensureMediaRoomForSocket = async ({ socket, mediaServer, sessionId }) => {
  if (!mediaServer) return null;

  const room = await mediaServer.getOrCreateRoom(sessionId);
  room.addPeer({ userId: socket.user.id, socket, isAlive: true });
  await syncMediaRoomState(sessionId, room);
  return room;
};
