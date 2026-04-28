'use strict';

import { configSchema, defaultConfig } from './schema.js';
import { buildInitialPluginState } from './state.js';
import {
  getPublicState,
  getPrivateState,
  checkWinCondition,
  handleEvent,
} from './service.js';

const COLOR_CHASER_GAME_TYPE = 'color_chaser';

const ColorChaserPlugin = {
  gameType: COLOR_CHASER_GAME_TYPE,
  displayName: '무지개 꼬리잡기: 컬러 체이서',
  configSchema,
  defaultConfig,
  capabilities: ['chase', 'tag', 'identity-hidden'],

  async startSession({ session, members, config }) {
    const resolvedConfig = { ...defaultConfig, ...(config ?? {}) };
    const pluginState = buildInitialPluginState(members, resolvedConfig, session);

    const gameState = {
      gameType: COLOR_CHASER_GAME_TYPE,
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
        role: player?.colorId ?? 'unknown',
        team: null,
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
    return checkWinCondition(gameState);
  },

  async handleEvent(eventName, payload, ctx) {
    return handleEvent(eventName, payload, ctx);
  },

  // 컬러 체이서 음성 정책:
  //   - 게임 진행 중에는 전원 muted (서로 정체를 모르는 게 핵심).
  //   - 로비/종료 상태에서는 전체 오픈.
  getVoicePolicy(gameState) {
    if (gameState?.status !== 'in_progress') {
      return { mode: 'open' };
    }
    return { mode: 'muted' };
  },

  getSystemPrompt(role, nickname) {
    return [
      'You are the live announcer for Color Chaser (Rainbow Tag).',
      `Player nickname: ${nickname}`,
      `Player color: ${role}`,
      'Keep announcements short, suspenseful, and avoid revealing identities.',
    ].join('\n');
  },

  getKnowledgeRole() {
    return 'all';
  },

  buildStateContext(gameState, player) {
    const ps = gameState?.pluginState ?? {};
    const myState = (ps.playerStates ?? {})[player.userId ?? player.user_id];
    return [
      `Color: ${myState?.colorLabel ?? 'unknown'}`,
      `Target color: ${myState?.targetColorLabel ?? 'unknown'}`,
      `Alive: ${myState?.isAlive ? 'yes' : 'no'}`,
    ].join('\n');
  },

  async getKnowledgeChunks() {
    return [];
  },
};

export default ColorChaserPlugin;
