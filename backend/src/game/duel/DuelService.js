'use strict';

import crypto from 'crypto';
import {
  pickMinigame,
  generateMinigameParams,
  buildPublicMinigameParams,
  judgeMinigame,
  processMinigameAction,
} from './minigames/index.js';

const CHALLENGE_TIMEOUT_MS = 15_000;
const GAME_TIMEOUT_MS = 30_000;
// 클라이언트 VS intro(5s) + briefing(10s) = 약 15s 의 pre-play 가 끝나야 실제 미니게임이
// 시작된다. accept 직후 GAME_TIMEOUT_MS 만 걸면 정당한 제출이 timeout 으로 처리될 수 있어,
// pre-play 가 정상 진행되는지만 감시하는 fallback 타이머를 따로 운영하고, 클라이언트가
// `fw:duel:play_started` 를 emit 하면 그때 GAME_TIMEOUT_MS 본 타이머를 시작한다.
// 25s 면 클라 pre-play 기본값(15s) 에 네트워크/렌더 지연 10s 여유를 더한 값.
const PRE_PLAY_FALLBACK_MS = 25_000;

const activeDuels = new Map();
const playerDuelMap = new Map();

class DuelService {
  challenge({ challengerId, targetId, sessionId, transport, onResolve, onInvalidate }) {
    if (!challengerId || !targetId || !sessionId) {
      return { ok: false, error: 'MISSING_FIELDS' };
    }
    if (challengerId === targetId) {
      return { ok: false, error: 'CANNOT_CHALLENGE_SELF' };
    }
    if (playerDuelMap.has(challengerId)) {
      return { ok: false, error: 'CHALLENGER_IN_DUEL' };
    }
    if (playerDuelMap.has(targetId)) {
      return { ok: false, error: 'TARGET_IN_DUEL' };
    }

    const duelId = crypto.randomUUID();
    const seed = crypto.randomBytes(16).toString('hex');
    const record = this._createDuelRecord({
      duelId,
      sessionId,
      challengerId,
      targetId,
      seed,
      transport,
      onResolve,
      onInvalidate,
    });

    activeDuels.set(duelId, record);
    playerDuelMap.set(challengerId, duelId);
    playerDuelMap.set(targetId, duelId);

    record._challengeTimer = setTimeout(
      () => this._invalidate(duelId, 'challenge_timeout'),
      CHALLENGE_TIMEOUT_MS,
    );

    transport.sendToUser(targetId, 'fw:duel:challenged', {
      duelId,
      challengerId,
      sessionId,
      expiresInMs: CHALLENGE_TIMEOUT_MS,
    });
    transport.sendToUser(challengerId, 'fw:duel:challenged', {
      duelId,
      targetId,
      sessionId,
      self: true,
    });

    return { ok: true, duelId };
  }

  accept({ duelId, userId }) {
    const record = this._getPendingDuel(duelId);
    if (!record) {
      return { ok: false, error: 'DUEL_NOT_PENDING' };
    }
    if (record.targetId !== userId) {
      return { ok: false, error: 'NOT_TARGET' };
    }

    clearTimeout(record._challengeTimer);

    const minigameType = pickMinigame(record.seed);
    const params = generateMinigameParams(
      minigameType,
      record.seed,
      [record.challengerId, record.targetId],
    );
    record.status = 'in_game';
    record.startedAt = Date.now();
    record.minigameType = minigameType;
    record.params = params;

    // accept 시점엔 본 타이머(GAME_TIMEOUT_MS) 를 걸지 않는다. 클라가 pre-play 이후
    // `fw:duel:play_started` 를 emit 하면 markPlayStarted 가 본 타이머를 건다.
    // 그 신호가 끝내 안 오면 PRE_PLAY_FALLBACK_MS 후 timeout 으로 invalidate.
    record._prePlayFallbackTimer = setTimeout(
      () => void this._resolveTimeout(duelId),
      PRE_PLAY_FALLBACK_MS,
    );

    const startPayload = {
      duelId,
      minigameType,
      gameTimeoutMs: GAME_TIMEOUT_MS,
      startedAt: record.startedAt,
    };

    record._transport.sendToUser(record.challengerId, 'fw:duel:started', {
      ...startPayload,
      params: buildPublicMinigameParams(minigameType, params, record.challengerId),
    });
    record._transport.sendToUser(record.targetId, 'fw:duel:started', {
      ...startPayload,
      params: buildPublicMinigameParams(minigameType, params, record.targetId),
    });
    record._transport.sendToSession(record.sessionId, 'fw:duel:accepted', {
      duelId,
      challengerId: record.challengerId,
      targetId: record.targetId,
      minigameType,
    });

    return {
      ok: true,
      duelId,
      startedAt: record.startedAt,
      gameTimeoutMs: GAME_TIMEOUT_MS,
      challengerId: record.challengerId,
      targetId: record.targetId,
    };
  }

  reject({ duelId, userId }) {
    const record = this._getPendingDuel(duelId);
    if (!record) {
      return { ok: false, error: 'DUEL_NOT_PENDING' };
    }
    if (record.targetId !== userId) {
      return { ok: false, error: 'NOT_TARGET' };
    }

    clearTimeout(record._challengeTimer);
    this._emitToBoth(record, 'fw:duel:rejected', { duelId });
    this._close(record, 'rejected');
    return { ok: true };
  }

  cancel({ duelId, userId }) {
    const record = this._getPendingDuel(duelId);
    if (!record) {
      return { ok: false, error: 'DUEL_NOT_PENDING' };
    }
    if (record.challengerId !== userId) {
      return { ok: false, error: 'NOT_CHALLENGER' };
    }

    clearTimeout(record._challengeTimer);
    // cancel은 다른 lifecycle emit과 달리 target → challenger 순서를 유지.
    record._transport.sendToUser(record.targetId, 'fw:duel:cancelled', { duelId });
    record._transport.sendToUser(record.challengerId, 'fw:duel:cancelled', { duelId });
    this._close(record, 'cancelled');
    return { ok: true };
  }

  // Client → server signal that pre-play (VS intro + briefing) finished and the
  // actual minigame is now visible. Both clients emit independently; the first
  // one to arrive arms the authoritative GAME_TIMEOUT_MS timer. Subsequent calls
  // are idempotent. If neither client signals, the pre-play fallback timer set
  // in accept() invalidates the duel.
  markPlayStarted({ duelId, userId }) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'in_game') {
      return { ok: false, error: 'DUEL_NOT_ACTIVE' };
    }
    if (userId !== record.challengerId && userId !== record.targetId) {
      return { ok: false, error: 'NOT_PARTICIPANT' };
    }
    if (record._playStarted) {
      // 두 번째 클라가 늦게 emit 하더라도 idempotent 처리. 이미 본 타이머가 가동 중이므로
      // 같은 startedAt / gameTimeoutMs 를 그대로 응답해 클라 동기화에 도움.
      return {
        ok: true,
        startedAt: record.startedAt,
        gameTimeoutMs: GAME_TIMEOUT_MS,
        alreadyStarted: true,
      };
    }

    record._playStarted = true;
    clearTimeout(record._prePlayFallbackTimer);
    record._prePlayFallbackTimer = null;

    record.startedAt = Date.now();
    record._gameTimer = setTimeout(
      () => void this._resolveTimeout(duelId),
      GAME_TIMEOUT_MS,
    );

    const armedPayload = {
      duelId,
      startedAt: record.startedAt,
      gameTimeoutMs: GAME_TIMEOUT_MS,
    };
    record._transport.sendToUser(record.challengerId, 'fw:duel:play_armed', armedPayload);
    record._transport.sendToUser(record.targetId, 'fw:duel:play_armed', armedPayload);

    return {
      ok: true,
      startedAt: record.startedAt,
      gameTimeoutMs: GAME_TIMEOUT_MS,
      alreadyStarted: false,
    };
  }

  async submit({ duelId, userId, result }) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'in_game') {
      return { ok: false, error: 'DUEL_NOT_ACTIVE' };
    }
    if (userId !== record.challengerId && userId !== record.targetId) {
      return { ok: false, error: 'NOT_PARTICIPANT' };
    }
    if (record.submissions[userId]) {
      return { ok: false, error: 'ALREADY_SUBMITTED' };
    }

    record.submissions[userId] = { result, submittedAt: Date.now() };
    if (Object.keys(record.submissions).length >= 2) {
      await this._resolve(duelId);
    }
    return { ok: true };
  }

  // 턴 기반(action-stream) 미니게임용 — 매 턴 actor 의 액션을 받아 서버에서
  // 상태를 전이시키고 양 클라에 새 public state 를 broadcast.
  // 종결 액션이면 _resolveWithVerdict 로 기존 result 흐름 재사용.
  async submitAction({ duelId, userId, action }) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'in_game') {
      return { ok: false, error: 'DUEL_NOT_ACTIVE' };
    }
    if (userId !== record.challengerId && userId !== record.targetId) {
      return { ok: false, error: 'NOT_PARTICIPANT' };
    }

    const participants = [record.challengerId, record.targetId];
    const result = processMinigameAction(record.minigameType, {
      params: record.params,
      actorId: userId,
      action,
      participants,
    });
    if (!result) {
      return { ok: false, error: 'NOT_ACTION_GAME' };
    }
    if (!result.ok) {
      return result;
    }

    record.params = result.params;

    const publicParams = buildPublicMinigameParams(
      record.minigameType,
      record.params,
      null,
    );
    this._emitToBoth(record, 'fw:duel:state', {
      duelId,
      minigameType: record.minigameType,
      state: publicParams?.state ?? null,
    });

    if (result.terminal) {
      await this._resolveWithVerdict(duelId, result.verdict);
    }
    return { ok: true, terminal: !!result.terminal };
  }

  handleDisconnect(userId) {
    const duelId = playerDuelMap.get(userId);
    if (!duelId) {
      return;
    }

    const record = activeDuels.get(duelId);
    if (!record) {
      return;
    }

    const terminalStatuses = ['resolved', 'cancelled', 'rejected', 'invalidated'];
    if (terminalStatuses.includes(record.status)) {
      return;
    }

    this._invalidate(duelId, 'disconnect');
  }

  getDuelForUser(userId) {
    const duelId = playerDuelMap.get(userId);
    return duelId ? (activeDuels.get(duelId) ?? null) : null;
  }

  getDuel(duelId) {
    return activeDuels.get(duelId) ?? null;
  }

  isInDuel(userId) {
    return playerDuelMap.has(userId);
  }

  invalidate(duelId, reason = 'invalid_state') {
    this._invalidate(duelId, reason);
  }

  async _resolve(duelId) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'in_game' || record._terminating) {
      return;
    }
    record._terminating = true;

    clearTimeout(record._gameTimer);
    clearTimeout(record._prePlayFallbackTimer);

    const subResults = Object.fromEntries(
      Object.entries(record.submissions).map(([userId, submission]) => [userId, submission.result]),
    );

    let verdict = judgeMinigame(
      record.minigameType,
      record.seed,
      subResults,
      record.params,
    );
    verdict = await this._finalizeVerdict(record, verdict, record.resolvedAt ?? Date.now());

    const resultPayload = {
      duelId,
      minigameType: record.minigameType,
      verdict,
      resolvedAt: record.resolvedAt,
    };

    this._emitResult(record, resultPayload);
    this._close(record, 'resolved');
  }

  // 턴 기반 미니게임의 종결 verdict 로 결과 흐름 진입. submission 기반 _resolve 가
  // judge() 호출까지 포함하는 것과 달리, 이쪽은 processAction 이 이미 verdict 를
  // 산출했으므로 _finalizeVerdict + emit + close 만 수행.
  async _resolveWithVerdict(duelId, verdict) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'in_game' || record._terminating) {
      return;
    }
    record._terminating = true;

    clearTimeout(record._gameTimer);
    clearTimeout(record._prePlayFallbackTimer);

    const finalVerdict = await this._finalizeVerdict(record, verdict, Date.now());

    const resultPayload = {
      duelId,
      minigameType: record.minigameType,
      verdict: finalVerdict,
      resolvedAt: record.resolvedAt,
    };

    this._emitResult(record, resultPayload);
    this._close(record, 'resolved');
  }

  async _resolveTimeout(duelId) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'in_game' || record._terminating) {
      return;
    }
    record._terminating = true;

    clearTimeout(record._gameTimer);
    clearTimeout(record._prePlayFallbackTimer);

    const submitted = new Set(Object.keys(record.submissions));
    const participants = [record.challengerId, record.targetId];
    const didNotSubmit = participants.filter((id) => !submitted.has(id));
    const didSubmit = participants.filter((id) => submitted.has(id));

    let verdict;
    if (didNotSubmit.length === 1) {
      verdict = {
        winner: didSubmit[0],
        loser: didNotSubmit[0],
        reason: 'opponent_timeout',
      };
    } else {
      verdict = { winner: null, loser: null, reason: 'both_timed_out' };
    }

    verdict = await this._finalizeVerdict(record, verdict, Date.now());

    const resultPayload = {
      duelId,
      minigameType: record.minigameType,
      verdict,
      resolvedAt: record.resolvedAt,
      timedOut: true,
    };

    this._emitResult(record, resultPayload);
    this._close(record, 'resolved');
  }

  async _finalizeVerdict(record, verdict, resolvedAt) {
    record.resolvedAt = resolvedAt;

    if (!record.onResolve) {
      return verdict;
    }

    const resolution = await Promise.resolve(
      record.onResolve({
        duelId: record.duelId,
        challengerId: record.challengerId,
        targetId: record.targetId,
        winnerId: verdict.winner,
        loserId: verdict.loser,
        reason: verdict.reason,
        minigameType: record.minigameType,
        sessionId: record.sessionId,
      }),
    ).catch((err) => {
      console.error('[Duel] onResolve error:', err);
      return null;
    });

    let nextVerdict = verdict;
    if (resolution?.verdict) {
      nextVerdict = { ...nextVerdict, ...resolution.verdict };
    }
    if (resolution?.effects) {
      nextVerdict = { ...nextVerdict, effects: resolution.effects };
    }
    return nextVerdict;
  }

  _invalidate(duelId, reason) {
    const record = activeDuels.get(duelId);
    if (!record || record._terminating) {
      return;
    }
    record._terminating = true;

    clearTimeout(record._challengeTimer);
    clearTimeout(record._gameTimer);
    clearTimeout(record._prePlayFallbackTimer);

    this._emitToBoth(record, 'fw:duel:invalidated', { duelId, reason });
    if (record.onInvalidate) {
      Promise.resolve(
        record.onInvalidate({
          duelId,
          sessionId: record.sessionId,
          challengerId: record.challengerId,
          targetId: record.targetId,
          reason,
        }),
      ).catch((err) => {
        console.error('[Duel] onInvalidate error:', err);
      });
    }

    this._close(record, 'invalidated');
    console.log(`[Duel] invalidated duelId=${duelId} reason=${reason}`);
  }

  _createDuelRecord({
    duelId,
    sessionId,
    challengerId,
    targetId,
    seed,
    transport,
    onResolve,
    onInvalidate,
  }) {
    return {
      duelId,
      sessionId,
      challengerId,
      targetId,
      seed,
      status: 'challenged',
      minigameType: null,
      params: null,
      submissions: {},
      startedAt: null,
      resolvedAt: null,
      onResolve,
      onInvalidate,
      _transport: transport,
      _challengeTimer: null,
      _gameTimer: null,
      _prePlayFallbackTimer: null,
      _playStarted: false,
      _terminating: false,
    };
  }

  _getPendingDuel(duelId) {
    const record = activeDuels.get(duelId);
    if (!record || record.status !== 'challenged') {
      return null;
    }
    return record;
  }

  _emitResult(record, payload) {
    // result 는 두 참가자만 직접 송신. 세션 단위 알림이 필요하면 fw:duel_log 가 따로
    // 담당한다 (duelHandlers.js: emitFantasyWarsDuelLog). 과거에는 sendToSession 으로
    // 같은 페이로드를 broadcast 했지만, 비참가자 클라가 onFwDuelResult 로 자기 duel
    // state.phase 를 'result' 로 덮어써 결과 오버레이가 잘못 노출되는 원인이었다.
    record._transport.sendToUser(record.challengerId, 'fw:duel:result', payload);
    record._transport.sendToUser(record.targetId, 'fw:duel:result', payload);
  }

  _emitToBoth(record, event, payload) {
    record._transport.sendToUser(record.challengerId, event, payload);
    record._transport.sendToUser(record.targetId, event, payload);
  }

  _close(record, finalStatus) {
    record.status = finalStatus;
    playerDuelMap.delete(record.challengerId);
    playerDuelMap.delete(record.targetId);
    activeDuels.delete(record.duelId);
  }
}

export const duelService = new DuelService();
