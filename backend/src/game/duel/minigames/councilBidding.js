'use strict';

import { sr, clampInt } from './shared.js';

// Council 전쟁 평의회 — 디자인 핸드오프 사양.
// 100 토큰 / 3 라운드 BO3 / 1.0–2.0× 배율을 시작 시 1개 받음 (0.2 단위 6 단계 균등 추첨).
// 배율은 단 한 라운드에만 적용 가능. 먼저 2승 도달 시 종료.
const COUNCIL_ROUNDS = 3;
const COUNCIL_TOKEN_POOL = 100;
const COUNCIL_MULTIPLIER_LADDER = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0];

// Council — 시드 + 인덱스 기반으로 1.0–2.0× 배율 한 칸 균등 추첨.
function pickCouncilMultiplier(seed, idx) {
  const r = sr(seed, 50 + idx);
  const step = Math.min(
    COUNCIL_MULTIPLIER_LADDER.length - 1,
    Math.floor(r * COUNCIL_MULTIPLIER_LADDER.length),
  );
  return COUNCIL_MULTIPLIER_LADDER[step];
}

// 클라이언트 제출 페이로드 sanitization.
// - bids: 비음 정수 3 개. 합 > tokenPool 이면 비례 축소.
// - applyMultiplier: 정확히 0개 또는 1개 라운드에만 true (그 외 무시).
function sanitizeCouncilRounds(rounds) {
  const cleaned = [];
  let multiplierUsed = false;
  let totalBid = 0;

  for (let i = 0; i < COUNCIL_ROUNDS; i += 1) {
    const r = Array.isArray(rounds) ? rounds[i] : null;
    const bid = clampInt(r?.bid, 0, COUNCIL_TOKEN_POOL, 0);
    let applyMultiplier = r?.applyMultiplier === true;
    if (applyMultiplier && multiplierUsed) {
      applyMultiplier = false; // 두 번째 이후 적용은 무시.
    }
    if (applyMultiplier) {
      multiplierUsed = true;
    }
    cleaned.push({ bid, applyMultiplier });
    totalBid += bid;
  }

  if (totalBid > COUNCIL_TOKEN_POOL) {
    const scale = COUNCIL_TOKEN_POOL / totalBid;
    cleaned.forEach((r) => {
      r.bid = Math.floor(r.bid * scale);
    });
  }

  return cleaned;
}

// BO3 라운드 진행. 먼저 2승 도달 시 즉시 종료.
// 동률 라운드는 누구도 승리하지 않음. 모두 동률이면 (또는 1승씩 + 동률 1회 등) draw.
function judgeCouncilBidding(p1, p2, rounds1, rounds2, m1, m2) {
  let wins1 = 0;
  let wins2 = 0;
  const roundResults = [];

  for (let i = 0; i < COUNCIL_ROUNDS; i += 1) {
    const r1 = rounds1[i];
    const r2 = rounds2[i];
    const e1 = r1.bid * (r1.applyMultiplier ? m1 : 1);
    const e2 = r2.bid * (r2.applyMultiplier ? m2 : 1);
    let roundWinner = null;
    if (e1 > e2) {
      wins1 += 1;
      roundWinner = p1;
    } else if (e2 > e1) {
      wins2 += 1;
      roundWinner = p2;
    }
    roundResults.push({
      round: i + 1,
      bids: { [p1]: r1.bid, [p2]: r2.bid },
      effective: { [p1]: e1, [p2]: e2 },
      multiplierUsed: { [p1]: r1.applyMultiplier, [p2]: r2.applyMultiplier },
      winner: roundWinner,
    });
    if (wins1 >= 2 || wins2 >= 2) {
      break; // 먼저 2승 도달 시 종료 — 남은 라운드는 의미 없음.
    }
  }

  if (wins1 > wins2) {
    return { winner: p1, loser: p2, reason: 'council_majority', roundResults };
  }
  if (wins2 > wins1) {
    return { winner: p2, loser: p1, reason: 'council_majority', roundResults };
  }
  return { winner: null, loser: null, reason: 'council_draw', roundResults };
}

export function generateParams(seed, participants) {
  // 양쪽 플레이어에 독립 배율을 추첨해 비공개 저장. buildPublic 에서 본인 것만 노출.
  const multipliersByUser = {};
  participants.forEach((userId, idx) => {
    multipliersByUser[userId] = pickCouncilMultiplier(seed, idx);
  });
  return {
    rounds: COUNCIL_ROUNDS,
    tokenPool: COUNCIL_TOKEN_POOL,
    multiplierLadder: [...COUNCIL_MULTIPLIER_LADDER],
    multipliersByUser,
  };
}

export function buildPublic(params, participantId) {
  // 본인 배율만 노출 — 상대 배율은 결과 공개 전까지 비공개.
  return {
    rounds: params?.rounds ?? COUNCIL_ROUNDS,
    tokenPool: params?.tokenPool ?? COUNCIL_TOKEN_POOL,
    multiplierLadder:
      Array.isArray(params?.multiplierLadder)
        ? params.multiplierLadder
        : [...COUNCIL_MULTIPLIER_LADDER],
    myMultiplier:
      params?.multipliersByUser?.[participantId] ??
      COUNCIL_MULTIPLIER_LADDER[0],
  };
}

export function judge({ p1, p2, s1, s2, params }) {
  const m1 = params?.multipliersByUser?.[p1] ?? 1;
  const m2 = params?.multipliersByUser?.[p2] ?? 1;
  const r1 = sanitizeCouncilRounds(s1?.rounds);
  const r2 = sanitizeCouncilRounds(s2?.rounds);
  return judgeCouncilBidding(p1, p2, r1, r2, m1, m2);
}
