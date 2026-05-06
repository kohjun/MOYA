'use strict';

const BLOCKADE_DURATION_MS = 60_000;
const REVEAL_DURATION_MS = 60_000;
const EXECUTION_ARM_WINDOW_MS = 60_000;

const JOB_SKILL = {
  priest: 'shield',
  mage: 'blockade',
  ranger: 'reveal',
  rogue: 'execution',
};

export function validateSkill(job, skill) {
  const expected = JOB_SKILL[job];
  if (!expected) {
    return { ok: false, error: 'NO_ACTIVE_SKILL' };
  }
  if (skill !== expected) {
    return { ok: false, error: 'WRONG_SKILL' };
  }
  return { ok: true, effect: skill };
}

export function applySkillEffect(effect, { player, targetPlayer, cp, now = Date.now() }) {
  switch (effect) {
    case 'shield': {
      if (!targetPlayer?.isAlive) {
        return null;
      }
      if (targetPlayer.guildId !== player.guildId) {
        return { type: 'shield', error: 'TARGET_NOT_ALLY' };
      }
      if (targetPlayer.inDuel && targetPlayer.duelExpiresAt > now) {
        return { type: 'shield', error: 'TARGET_IN_DUEL' };
      }
      if (!targetPlayer.shields) {
        targetPlayer.shields = [];
      }
      targetPlayer.shields.push({
        from: player.userId,
        grantedAt: now,
        expiresAt: null,
      });
      return {
        type: 'shield',
        targetUserId: targetPlayer.userId,
        shieldCount: targetPlayer.shields.length,
      };
    }

    case 'blockade': {
      if (!cp) {
        return null;
      }
      // 점령 진행 중인 CP 에 봉쇄가 걸리면 봉쇄는 정상 적용되고, 봉쇄 효과로 점령이
      // 강제 종료된다 (= 봉쇄 동안 다른 길드도 점령 불가). disrupted 플래그가 켜진
      // result 를 본 핸들러가 resetCaptureState + cancelCaptureTimer +
      // fw:capture_cancelled 까지 처리해 capture state 를 일관되게 클린업.
      const interruptedGuild = cp.capturingGuild ?? null;
      cp.blockadedBy = player.guildId;
      cp.blockadeExpiresAt = now + BLOCKADE_DURATION_MS;
      const result = {
        type: 'blockade',
        cpId: cp.id,
        expiresAt: cp.blockadeExpiresAt,
      };
      if (interruptedGuild) {
        result.disrupted = true;
        result.interruptedGuild = interruptedGuild;
      }
      return result;
    }

    case 'reveal': {
      if (!targetPlayer?.isAlive) {
        return null;
      }
      if (targetPlayer.guildId === player.guildId) {
        return { type: 'reveal', error: 'TARGET_NOT_ENEMY' };
      }
      player.revealUntil = now + REVEAL_DURATION_MS;
      player.trackedTargetUserId = targetPlayer.userId;
      return {
        type: 'reveal',
        targetUserId: targetPlayer.userId,
        revealUntil: player.revealUntil,
      };
    }

    case 'execution': {
      player.executionArmedUntil = now + EXECUTION_ARM_WINDOW_MS;
      return {
        type: 'execution',
        armedUntil: player.executionArmedUntil,
      };
    }

    default:
      return null;
  }
}

export function activeShields(player, now = Date.now()) {
  return (player?.shields ?? []).filter(
    (shield) => shield && (shield.expiresAt == null || shield.expiresAt > now),
  );
}

export function consumeShield(player, now = Date.now()) {
  const shields = player?.shields ?? [];
  const activeIndex = shields.findIndex(
    (shield) => shield && (shield.expiresAt == null || shield.expiresAt > now),
  );
  if (activeIndex === -1) {
    return false;
  }
  shields.splice(activeIndex, 1);
  return true;
}

export function isExecutionArmed(player, now = Date.now()) {
  return Boolean(player?.executionArmedUntil && player.executionArmedUntil > now);
}
