'use strict';

import { configSchema, defaultConfig } from './schema.js';
import { buildInitialPluginState } from './state.js';
import {
  getPublicState,
  getPrivateState,
  checkWinCondition,
  handleEvent,
  resolveDuelOutcome,
} from './service.js';

const FANTASY_WARS_GAME_TYPE = 'fantasy_wars_artifact';

const FantasyWarsArtifactPlugin = {
  gameType: FANTASY_WARS_GAME_TYPE,
  displayName: '판타지 워즈: 성유물 쟁탈전',
  configSchema,
  defaultConfig,
  capabilities: ['territory', 'faction', 'revive', 'skill', 'artifact'],

  async startSession({ session, members, config }) {
    const resolvedConfig = { ...defaultConfig, ...(config ?? {}) };
    const pluginState = buildInitialPluginState(members, resolvedConfig, session);

    const gameState = {
      gameType: FANTASY_WARS_GAME_TYPE,
      status: 'in_progress',
      startedAt: Date.now(),
      finishedAt: null,
      alivePlayerIds: members.map((member) => member.user_id),
      pluginState,
    };

    const roles = members.map((member) => {
      const player = pluginState.playerStates?.[member.user_id];
      return {
        userId: member.user_id,
        role: player?.job ?? 'warrior',
        team: player?.guildId ?? null,
        privateData: getPrivateState(gameState, member.user_id),
      };
    });

    return { gameState, roles };
  },

  getPublicState(gameState) {
    return getPublicState(gameState);
  },

  getPrivateState(gameState, userId) {
    return getPrivateState(gameState, userId);
  },

  checkWinCondition(gameState) {
    const config = gameState?.pluginState?._config ?? defaultConfig;
    return checkWinCondition(gameState, config);
  },

  async handleEvent(eventName, payload, ctx) {
    return handleEvent(eventName, payload, ctx);
  },

  resolveDuelOutcome(gameState, payload) {
    return resolveDuelOutcome(gameState, payload);
  },

  getCurrentPhase(gameState) {
    const controlPoints = gameState?.pluginState?.controlPoints ?? [];
    const capturedCount = controlPoints.filter((cp) => cp.capturedBy).length;
    if (capturedCount === 0) {
      return 'early';
    }
    if (capturedCount < controlPoints.length) {
      return 'mid';
    }
    return 'late';
  },

  // 판타지 워즈 음성 정책:
  //   - 게임 진행 중에는 같은 길드 멤버끼리만 음성 가능 (팀 채널)
  //   - 로비/종료 상태에서는 전체 오픈
  getVoicePolicy(gameState, { userId } = {}) {
    if (gameState?.status !== 'in_progress') {
      return { mode: 'open' };
    }
    const ps = gameState.pluginState ?? {};
    const player = userId ? (ps.playerStates ?? {})[userId] : null;
    return { mode: 'team', teamId: player?.guildId ?? null };
  },

  getSystemPrompt(role, nickname) {
    return [
      'You are the live announcer for Fantasy Wars: Artifact.',
      `Player nickname: ${nickname}`,
      `Player role: ${role}`,
      'Keep announcements short, dramatic, and easy to understand during live play.',
    ].join('\n');
  },

  // 현재 FW 지식베이스는 role: 'all' 태그만 사용한다.
  // 직업/길드 ID로 RAG를 필터링하면 결과가 비어 응답 품질이 떨어진다.
  getKnowledgeRole() {
    return 'all';
  },

  buildStateContext(gameState, player) {
    const ps = gameState?.pluginState ?? {};
    const myState = (ps.playerStates ?? {})[player.userId ?? player.user_id];
    const capturedByMe = (ps.controlPoints ?? []).filter(
      (cp) => cp.capturedBy === myState?.guildId,
    ).length;

    return [
      `Guild: ${myState?.guildId ?? 'unknown'}`,
      `Role: ${myState?.job ?? 'unknown'}`,
      `Guild master: ${myState?.isGuildMaster ? 'yes' : 'no'}`,
      `Captured points: ${capturedByMe}`,
      `Alive: ${myState?.isAlive ? 'yes' : 'no'}`,
    ].join('\n');
  },

  async getKnowledgeChunks() {
    return [];
  },
};

export default FantasyWarsArtifactPlugin;
