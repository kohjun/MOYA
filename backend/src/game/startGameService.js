import { redisClient } from '../config/redis.js';
import * as sessionService from '../services/sessionService.js';
import * as AIDirector from '../ai/AIDirector.js';
import { getMediaServer } from '../media/MediaServer.js';
import { GamePluginRegistry } from './index.js';
import { keys, syncMediaRoomState } from '../websocket/socketRuntime.js';
import { validateFantasyWarsStart } from './plugins/fantasy_wars_artifact/startValidation.js';

const GAME_TTL = 86400;
const DEFAULT_GAME_TYPE = 'fantasy_wars_artifact';

const GAME_EVENTS = {
  started:      'game:started',
  roleAssigned: 'game:role_assigned',
  aiMessage:    'game:ai_message',
};

async function emitGameStartAnnouncement({ io, sessionId, gameState, aliveMembers }) {
  try {
    const ps = gameState.pluginState ?? {};
    const roomLike = {
      roomId: sessionId,
      pluginState: ps,
      alivePlayerIds: aliveMembers.map((member) => member.user_id),
    };
    const msg = await AIDirector.fwOnGameStart(roomLike);

    if (msg) {
      io.to(`session:${sessionId}`).emit(GAME_EVENTS.aiMessage, {
        type: 'announcement',
        message: msg,
      });
      io.to(`session:${sessionId}`).emit('ai:recovered', { sessionId });
    } else {
      io.to(`session:${sessionId}`).emit('ai:failed', {
        sessionId,
        message: 'AI 마스터가 응답하지 않았습니다.',
      });
    }
  } catch (error) {
    console.error('[AI] game start announcement failed:', error.message);
    io.to(`session:${sessionId}`).emit('ai:failed', {
      sessionId,
      message: 'AI 마스터 서버 연결 실패.',
    });
  }
}

function assertFantasyWarsLayoutReady(session, config) {
  const playableArea = Array.isArray(session?.playable_area) ? session.playable_area : [];
  const controlPoints = Array.isArray(config?.controlPoints) ? config.controlPoints : [];
  const spawnZones = Array.isArray(config?.spawnZones) ? config.spawnZones : [];
  const expectedControlPoints = Number(config?.controlPointCount ?? 5);
  const expectedSpawnZones = Number(config?.teamCount ?? 3);

  if (playableArea.length < 3) {
    throw new Error('FANTASY_WARS_PLAYABLE_AREA_REQUIRED');
  }
  if (controlPoints.length !== expectedControlPoints) {
    throw new Error('FANTASY_WARS_CONTROL_POINTS_REQUIRED');
  }
  if (spawnZones.length !== expectedSpawnZones) {
    throw new Error('FANTASY_WARS_SPAWN_ZONES_REQUIRED');
  }
}

export const startGameForSession = async ({ io, sessionId, requesterUserId }) => {
  const session = await sessionService.getSession(sessionId);
  if (!session) throw new Error('SESSION_NOT_FOUND');
  if (session.host_user_id !== requesterUserId) throw new Error('NOT_HOST');

  const alreadyStarted = await redisClient.get(keys.started(sessionId));
  if (alreadyStarted) throw new Error('GAME_ALREADY_STARTED');

  const members = await sessionService.getSessionMembers(sessionId);
  const aliveMembers = members.filter(m => m?.user_id);

  if (aliveMembers.length < 2) {
    const err = new Error('NOT_ENOUGH_PLAYERS');
    err.details = { required: 2, current: aliveMembers.length };
    throw err;
  }

  const gameType = session.game_type ?? DEFAULT_GAME_TYPE;
  const plugin   = GamePluginRegistry.get(gameType);

  const config = {
    ...(plugin.defaultConfig ?? {}),
    ...(session.game_config ?? {}),
  };

  if (gameType === 'fantasy_wars_artifact') {
    assertFantasyWarsLayoutReady(session, config);
    validateFantasyWarsStart(aliveMembers, config);
  }

  const { gameState, roles } = await plugin.startSession({
    session,
    members: aliveMembers,
    config,
    io,
  });

  await Promise.all([
    redisClient.set(keys.state(sessionId),   JSON.stringify(gameState), { EX: GAME_TTL }),
    redisClient.set(keys.started(sessionId), '1',                       { EX: GAME_TTL }),
  ]);

  const startedPayload = {
    sessionId,
    gameType,
    playerCount:   aliveMembers.length,
    startedAt:     new Date(gameState.startedAt).toISOString(),
    activeModules: Array.isArray(session.active_modules) ? session.active_modules : [],
    ...(plugin.getPublicState?.(gameState) ?? {}),
  };

  const mediaRoom = getMediaServer()?.getRoom(sessionId);
  if (mediaRoom) {
    mediaRoom.setAlivePeers(aliveMembers.map(m => m.user_id));
    await syncMediaRoomState(sessionId, mediaRoom);
  }

  io.to(`session:${sessionId}`).emit(GAME_EVENTS.started, startedPayload);

  // Color Chaser: 게임 시작 즉시 거점 활성화 schedule + 시간 제한 timer 등록.
  if (gameType === 'color_chaser') {
    try {
      const handlers = await import('../websocket/handlers/colorChaserHandlers.js');
      handlers.ensureCpActivationTimer(io, sessionId, gameState);
      handlers.ensureTimeLimitTimer(io, sessionId, gameState);
    } catch (err) {
      console.error('[CC] start hook failed:', err);
    }
  }

  for (const roleAssignment of roles) {
    io.to(`user:${roleAssignment.userId}`).emit(GAME_EVENTS.roleAssigned, {
      role: roleAssignment.role,
      team: roleAssignment.team,
      ...(roleAssignment.privateData ?? {}),
    });
  }

  void emitGameStartAnnouncement({
    io,
    sessionId,
    gameState,
    aliveMembers,
  });

  return { session, aliveMembers, gameState, startedPayload };
};
