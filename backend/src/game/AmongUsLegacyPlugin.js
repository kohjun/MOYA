'use strict';

import { redisClient } from '../config/redis.js';
import * as sessionService from '../services/sessionService.js';
import * as MissionSystem from './MissionSystem.js';
import * as AIDirector from '../ai/AIDirector.js';
import VoteSystem from './VoteSystem.js';
import KillCooldownManager from './KillCooldownManager.js';
import { EVENTS } from '../websocket/socketProtocol.js';

const GAME_TTL = 86400;

// ─────────────────────────────────────────────────────────────────────────────
// AmongUsLegacyPlugin
//
// gameType 'among_us' — legacy entry point.
// All game-specific logic lives here; startGameService and gameHandlers
// are now policy-free entry points.
// ─────────────────────────────────────────────────────────────────────────────

const AmongUsLegacyPlugin = {
  gameType:    'among_us',
  displayName: '어몽어스',

  configSchema: {
    impostorCount:  { type: 'number', default: 1, min: 1, max: 3 },
    killCooldown:   { type: 'number', default: 30, min: 10, max: 60 },
    discussionTime: { type: 'number', default: 90, min: 30, max: 180 },
    voteTime:       { type: 'number', default: 30, min: 15, max: 60 },
    missionPerCrew: { type: 'number', default: 3, min: 1, max: 5 },
    killDistance:   { type: 'number', default: 3, min: 1, max: 10 },
  },

  defaultConfig: {
    impostorCount:  1,
    killCooldown:   30,
    discussionTime: 90,
    voteTime:       30,
    missionPerCrew: 3,
    killDistance:   3,
  },

  capabilities: ['kill', 'vote', 'mission', 'proximity', 'item'],

  // ── lifecycle ─────────────────────────────────────────────────────────────

  async startSession({ session, members, config }) {
    const impostorCount = Math.max(
      1,
      Math.min(
        Number.isInteger(config.impostorCount ?? session.impostor_count)
          ? (config.impostorCount ?? session.impostor_count)
          : 1,
        Math.max(1, members.length - 1),
      ),
    );

    const shuffled  = [...members].sort(() => Math.random() - 0.5);
    const impostors = new Set(shuffled.slice(0, impostorCount).map(m => m.user_id));

    const gameState = {
      gameType:       'among_us',
      status:         'in_progress',
      startedAt:      Date.now(),
      finishedAt:     null,
      alivePlayerIds: members.map(m => m.user_id),
      pluginState: {
        impostors:    [...impostors],
        killLog:      [],
        meetingCount: 0,
        killCooldown: config.kill_cooldown ?? session.kill_cooldown ?? 30,
      },
    };

    const roles = members.map(m => ({
      userId:      m.user_id,
      role:        impostors.has(m.user_id) ? 'impostor' : 'crew',
      team:        impostors.has(m.user_id) ? 'impostor' : 'crew',
      privateData: { impostors: impostors.has(m.user_id) ? [...impostors] : [] },
    }));

    return { gameState, roles };
  },

  getPublicState(gameState) {
    return {
      status:         gameState.status,
      startedAt:      gameState.startedAt,
      finishedAt:     gameState.finishedAt,
      aliveCount:     gameState.alivePlayerIds.length,
      alivePlayerIds: gameState.alivePlayerIds,
    };
  },

  getPrivateState(gameState, userId) {
    const ps = gameState.pluginState ?? {};
    const impostors  = Array.isArray(ps.impostors) ? ps.impostors : [];
    const isImpostor = impostors.includes(userId);
    return {
      role:      isImpostor ? 'impostor' : 'crew',
      team:      isImpostor ? 'impostor' : 'crew',
      impostors: isImpostor ? impostors : [],
    };
  },

  async handleEvent(eventName, payload, ctx) {
    switch (eventName) {
      case 'kill':             return this._handleKill(payload, ctx);
      case 'emergency':        return this._handleEmergency(payload, ctx);
      case 'report':           return this._handleReport(payload, ctx);
      case 'vote':             return this._handleVote(payload, ctx);
      case 'mission_complete': return this._handleMissionComplete(payload, ctx);
      case 'trigger_sabotage': return this._handleTriggerSabotage(payload, ctx);
      case 'fix_sabotage':     return this._handleFixSabotage(payload, ctx);
      default:                 return false;
    }
  },

  checkWinCondition(gameState) {
    const ps = gameState.pluginState ?? {};
    const impostors     = Array.isArray(ps.impostors) ? ps.impostors : [];
    const aliveImpostors = impostors.filter(id => gameState.alivePlayerIds.includes(id));
    const aliveCrew      = gameState.alivePlayerIds.filter(id => !impostors.includes(id));

    if (aliveImpostors.length === 0)
      return { winner: 'crew', reason: 'impostors_ejected' };
    if (aliveImpostors.length >= aliveCrew.length)
      return { winner: 'impostor', reason: 'outnumbered' };
    return null;
  },

  // ── AI helpers ────────────────────────────────────────────────────────────

  getSystemPrompt(role, nickname) {
    const base = `너는 어몽어스 오프라인 게임의 AI 진행자야. 플레이어 닉네임: ${nickname}\n답변은 반드시 완전한 문장으로 끝내고, 5문장을 넘지 마.`;
    return role === 'impostor'
      ? base + '\n이 플레이어는 임포스터야. 전략적으로 조언하되 다른 플레이어에게 정체가 들키지 않도록 해.'
      : base + '\n이 플레이어는 크루원이야. 미션 완수와 임포스터 색출을 도와줘. 임포스터가 누구인지는 절대 알려주지 마.';
  },

  buildStateContext(gameState, player) {
    const aliveCount = gameState.alivePlayerIds?.length ?? 0;
    const ps = gameState.pluginState ?? {};
    return [
      `생존자 수: ${aliveCount}명`,
      `킬 로그: ${ps.killLog?.length ?? 0}건`,
      `내 역할: ${player.roleId ?? player.role}`,
      `내 팀: ${player.team}`,
    ].join('\n');
  },

  getKnowledgeChunks() {
    return import('./knowledgeBase/index.js');
  },

  // ── private event handlers ────────────────────────────────────────────────

  async _handleKill({ targetUserId }, { io, socket, userId, sessionId, gameState, saveState }) {
    if (gameState.status === 'finished') return true;

    const ps = gameState.pluginState ?? {};
    const impostors = Array.isArray(ps.impostors) ? ps.impostors : [];

    if (!impostors.includes(userId)) return true;
    if (!gameState.alivePlayerIds.includes(targetUserId)) return true;
    if (!KillCooldownManager.canKill(sessionId, userId)) {
      socket.emit(EVENTS.ERROR, { code: 'KILL_COOLDOWN' });
      return true;
    }

    // 동시 타격 방어 락
    const lockKey = `target_lock:${sessionId}:${targetUserId}`;
    const locked = await redisClient.set(lockKey, '1', { NX: true, EX: 2 });
    if (!locked) return true;

    gameState.alivePlayerIds = gameState.alivePlayerIds.filter(id => id !== targetUserId);
    ps.killLog = [...(ps.killLog ?? []), { killerId: userId, victimId: targetUserId, at: Date.now() }];
    gameState.pluginState = ps;

    await saveState(gameState);
    KillCooldownManager.setKillCooldown(sessionId, userId, ps.killCooldown ?? 30);

    io.to(`session:${sessionId}`).emit(EVENTS.GAME_KILL_CONFIRMED, { victimId: targetUserId });
    socket.emit(EVENTS.GAME_KILL_CONFIRMED, { ok: true });

    // AI 킬 알림
    try {
      const members = await sessionService.getSessionMembers(sessionId);
      const memberById = new Map(members.map(m => [m.user_id, m]));
      const killer = memberById.get(userId) ?? { nickname: userId };
      const target = memberById.get(targetUserId) ?? { nickname: targetUserId, zone: '' };
      const msg = await AIDirector.onKill(
        { roomId: sessionId, killLog: ps.killLog, alivePlayerIds: gameState.alivePlayerIds, impostors },
        { userId, nickname: killer.nickname ?? userId },
        { userId: targetUserId, nickname: target.nickname ?? targetUserId, zone: target.zone ?? '' },
      );
      if (msg) io.to(`session:${sessionId}`).emit(EVENTS.GAME_AI_MESSAGE, { type: 'kill', message: msg });
    } catch (e) { console.error('[AI] kill failed:', e.message); }

    // 승리 조건 체크
    const win = this.checkWinCondition(gameState);
    if (win) {
      gameState.status = 'finished';
      gameState.finishedAt = Date.now();
      await saveState(gameState);
      io.to(`session:${sessionId}`).emit(EVENTS.GAME_OVER, win);
    }

    return true;
  },

  async _handleEmergency(_payload, { sessionId, userId, gameState }) {
    const ps = gameState.pluginState ?? {};
    const impostors = Array.isArray(ps.impostors) ? ps.impostors : [];

    if (!gameState.alivePlayerIds.includes(userId)) {
      return { handled: true, error: 'ONLY_ALIVE_PLAYERS' };
    }

    const [session, members] = await Promise.all([
      sessionService.getSession(sessionId),
      sessionService.getSessionMembers(sessionId),
    ]);
    if (!session) return { handled: true, error: 'SESSION_NOT_FOUND' };

    session.aliveMembers = members.filter(m => gameState.alivePlayerIds.includes(m.user_id));
    session.impostors    = impostors;

    VoteSystem.startMeeting(session, { callerId: userId, bodyId: null, reason: 'emergency' });
    return true;
  },

  async _handleReport({ bodyId }, { sessionId, userId, gameState }) {
    if (!gameState.alivePlayerIds.includes(userId)) return true;
    if (gameState.alivePlayerIds.includes(bodyId)) return true;

    const [session, members] = await Promise.all([
      sessionService.getSession(sessionId),
      sessionService.getSessionMembers(sessionId),
    ]);
    if (!session) return true;

    const ps = gameState.pluginState ?? {};
    session.aliveMembers = members.filter(m => gameState.alivePlayerIds.includes(m.user_id));
    session.impostors    = Array.isArray(ps.impostors) ? ps.impostors : [];

    VoteSystem.startMeeting(session, { callerId: userId, bodyId, reason: 'report' });
    return true;
  },

  _handleVote({ targetId }, { sessionId, userId, socket }) {
    try {
      const result = VoteSystem.submitVote(sessionId, userId, targetId);
      socket.emit('game:vote_ack', { ok: true, ...result });
    } catch (err) {
      socket.emit('game:vote_ack', { ok: false, error: err.message });
    }
    return true;
  },

  async _handleMissionComplete({ missionId }, { io, socket, sessionId, userId, gameState, saveState }) {
    if (gameState.status === 'finished') return true;
    if (!missionId) return true;
    const result = await MissionSystem.completeMission(sessionId, userId, missionId);
    if (!result) return true;

    const progressData = await MissionSystem.getProgressBar(sessionId);
    socket.emit(EVENTS.GAME_MISSION_PROGRESS, { missionId, ...progressData });
    io.to(`session:${sessionId}`).emit(EVENTS.GAME_MISSION_PROGRESS, progressData);

    const pct = progressData.total > 0 ? progressData.completed / progressData.total : 0;
    io.to(`session:${sessionId}`).emit(EVENTS.TASK_PROGRESS, {
      progress: pct,
      completed: progressData.completed,
      total: progressData.total,
      percent: progressData.percent,
    });

    if (result.allDone) {
      gameState.status = 'finished';
      gameState.finishedAt = Date.now();
      await saveState(gameState);
      io.to(`session:${sessionId}`).emit(EVENTS.GAME_OVER, { winner: 'crew', reason: 'all_missions_done' });
    }
    return true;
  },

  async _handleTriggerSabotage({ missionId }, { io, socket, userId, sessionId, gameState }) {
    if (!missionId) return true;
    const ps = gameState.pluginState ?? {};
    if (!Array.isArray(ps.impostors) || !ps.impostors.includes(userId)) return true;
    if (!gameState.alivePlayerIds.includes(userId)) return true;

    await redisClient.set(`sabotage:${sessionId}:${missionId}`, '1', { EX: 300 });
    io.to(`session:${sessionId}`).emit(EVENTS.GAME_SABOTAGE_ACTIVE, { missionId, triggeredBy: userId });
    return true;
  },

  async _handleFixSabotage({ missionId }, { io, userId, sessionId, gameState }) {
    if (!missionId) return true;
    if (!gameState.alivePlayerIds.includes(userId)) return true;

    await redisClient.del(`sabotage:${sessionId}:${missionId}`);
    io.to(`session:${sessionId}`).emit(EVENTS.GAME_SABOTAGE_FIXED, { missionId, fixedBy: userId });
    return true;
  },
};

export default AmongUsLegacyPlugin;
