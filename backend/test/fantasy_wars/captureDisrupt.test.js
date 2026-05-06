import test from 'node:test';
import assert from 'node:assert/strict';

import { handleCaptureDisrupt } from '../../src/game/plugins/fantasy_wars_artifact/captureHandlers.js';
import { defaultConfig } from '../../src/game/plugins/fantasy_wars_artifact/schema.js';
import { makeControlPoint, makeGameState, makePlayer } from '../../testing/fantasy_wars/helpers.js';
import { makeFakeIo } from './_helpers/fakeIo.js';
import { makeFakeGameStateStore } from './_helpers/fakeGameStateStore.js';

// 일관된 테스트 fixture: cp-1 에 적 길드(beta) 점령 진행 중. player(alpha) 는
// 살아있고 cp-1 안에 있다고 가정. 위치 의존 분기는 redis 가 필요하므로 이
// 파일에서는 redis 호출 전에 종료되는 동기 가드 분기만 검증한다.
function makeFixture(playerOverrides = {}, cpOverrides = {}) {
  const cp = makeControlPoint({
    id: 'cp-1',
    capturingGuild: 'guild_beta',
    captureStartedAt: 1000,
    captureParticipantUserIds: ['enemy-1'],
    ...cpOverrides,
  });
  const player = makePlayer({
    userId: 'me',
    guildId: 'guild_alpha',
    ...playerOverrides,
  });
  const gameState = makeGameState({
    pluginState: {
      _config: defaultConfig,
      controlPoints: [cp],
      playerStates: { me: player, 'enemy-1': makePlayer({ userId: 'enemy-1', guildId: 'guild_beta' }) },
    },
  });
  return { gameState, cp, player };
}

function makeCtx(gameState) {
  const io = makeFakeIo();
  const store = makeFakeGameStateStore(gameState);
  return {
    ctx: {
      userId: 'me',
      sessionId: 'session-1',
      gameState: store.snapshot(),
      readState: store.readState,
      saveState: store.saveState,
      io,
    },
    io,
    store,
  };
}

test('handleCaptureDisrupt rejects when controlPointId missing', async () => {
  const { gameState } = makeFixture();
  const { ctx } = makeCtx(gameState);
  const result = await handleCaptureDisrupt({}, ctx);
  assert.deepEqual(result, { error: 'CP_NOT_FOUND' });
});

test('handleCaptureDisrupt rejects an unknown control point', async () => {
  const { gameState } = makeFixture();
  const { ctx } = makeCtx(gameState);
  const result = await handleCaptureDisrupt({ controlPointId: 'cp-unknown' }, ctx);
  assert.deepEqual(result, { error: 'CP_NOT_FOUND' });
});

test('handleCaptureDisrupt rejects dead player', async () => {
  const { gameState } = makeFixture({ isAlive: false });
  const { ctx, io } = makeCtx(gameState);
  const result = await handleCaptureDisrupt({ controlPointId: 'cp-1' }, ctx);
  assert.deepEqual(result, { error: 'PLAYER_DEAD' });
  assert.equal(io.eventsFor('fw:capture_cancelled').length, 0);
});

test('handleCaptureDisrupt rejects player currently locked in a duel (server-side guard)', async () => {
  // UI 가 disrupt 버튼을 숨긴다 해도, 클라가 fw:capture_disrupt 를 직접 emit
  // 했을 때 서버가 결투 잠금을 우회당하면 안 된다 (Codex high finding).
  const { gameState } = makeFixture({ inDuel: true });
  const { ctx, io } = makeCtx(gameState);
  const result = await handleCaptureDisrupt({ controlPointId: 'cp-1' }, ctx);
  assert.deepEqual(result, { error: 'PLAYER_IN_DUEL' });
  assert.equal(io.eventsFor('fw:capture_cancelled').length, 0);
});

test('handleCaptureDisrupt rejects when no capture is active', async () => {
  const { gameState } = makeFixture({}, { capturingGuild: null });
  const { ctx } = makeCtx(gameState);
  const result = await handleCaptureDisrupt({ controlPointId: 'cp-1' }, ctx);
  assert.deepEqual(result, { error: 'CAPTURE_NOT_ACTIVE' });
});

test('handleCaptureDisrupt rejects friendly capture (not enemy)', async () => {
  const { gameState } = makeFixture({}, { capturingGuild: 'guild_alpha' });
  const { ctx } = makeCtx(gameState);
  const result = await handleCaptureDisrupt({ controlPointId: 'cp-1' }, ctx);
  assert.deepEqual(result, { error: 'NOT_ENEMY_CAPTURE' });
});
