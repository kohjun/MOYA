'use strict';

import { BODY_ATTRIBUTES, BODY_ATTRIBUTE_KEYS } from './schema.js';

// 미션 성공 시 호출. 본인 타겟의 미공개 attribute 1개를 무작위로 공개하고
// candidatePool 에서 매칭되지 않는 사람을 제거한다.
//
// fallback 정책:
//   - 타겟의 attribute 가 'unknown' (입력 안 함) → 그 키는 공개 후보에서 제외.
//     → 모든 키가 unknown 이면 unlock 불가, null 반환.
//   - 후보의 attribute 가 'unknown' → 매칭으로 간주 (후보로 유지).
//     입력 안 한 사람이 부당하게 narrowing 당하지 않게 함.
export function unlockHintForPlayer(pluginState, ownerUserId) {
  const player = pluginState.playerStates?.[ownerUserId];
  if (!player) return null;

  const targetUserId = player.targetUserId;
  if (!targetUserId) return null;

  const targetProfile = (pluginState.bodyProfiles ?? {})[targetUserId] ?? {};
  const alreadyRevealed = new Set(
    (player.unlockedHints ?? []).map((h) => h.attribute),
  );

  const revealable = BODY_ATTRIBUTE_KEYS.filter(
    (key) => !alreadyRevealed.has(key) && targetProfile[key], // 'unknown' 제외
  );

  if (revealable.length === 0) {
    return null; // 더 공개할 게 없음
  }

  const attribute = revealable[Math.floor(Math.random() * revealable.length)];
  const value = targetProfile[attribute];
  const def = BODY_ATTRIBUTES[attribute];
  const optionLabel =
    def.options.find((opt) => opt.id === value)?.label ?? value;

  // 후보군 narrowing — 같은 attribute=value 거나 unknown 인 사람만 유지
  const newPool = (player.candidatePool ?? []).filter((uid) => {
    const cProfile = (pluginState.bodyProfiles ?? {})[uid] ?? {};
    if (!cProfile[attribute]) return true; // unknown → 유지
    return cProfile[attribute] === value;
  });

  const hint = {
    attribute,
    attributeLabel: def.label,
    value,
    optionLabel,
    revealedAt: Date.now(),
    candidateCountAfter: newPool.length,
  };

  player.unlockedHints = [...(player.unlockedHints ?? []), hint];
  player.candidatePool = newPool;

  return hint;
}

// 사망/이탈 시 모든 살아있는 플레이어의 candidatePool 에서 해당 userId 제거.
export function pruneCandidatePools(pluginState, removedUserId) {
  Object.values(pluginState.playerStates ?? {}).forEach((player) => {
    if (!Array.isArray(player.candidatePool)) return;
    player.candidatePool = player.candidatePool.filter(
      (uid) => uid !== removedUserId,
    );
  });
}
