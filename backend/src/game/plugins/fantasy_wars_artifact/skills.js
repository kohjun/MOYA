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
      cp.blockadedBy = player.guildId;
      cp.blockadeExpiresAt = now + BLOCKADE_DURATION_MS;
      return {
        type: 'blockade',
        cpId: cp.id,
        expiresAt: cp.blockadeExpiresAt,
      };
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

export function hasActiveShield(player, now = Date.now()) {
  return activeShields(player, now).length > 0;
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
