// src/game/KillCooldownManager.js

class KillCooldownManager {
  constructor() {
    // cooldowns: Map<`${sessionId}:${killerId}`, expiresAt (ms)>
    this._cooldowns = new Map();
  }

  _key(sessionId, killerId) {
    return `${sessionId}:${killerId}`;
  }

  /**
   * 킬 가능 여부 확인
   * @param {string} sessionId
   * @param {string} killerId
   * @returns {boolean}
   */
  canKill(sessionId, killerId) {
    const key     = this._key(sessionId, killerId);
    const expires = this._cooldowns.get(key);
    if (!expires) return true;
    if (Date.now() >= expires) {
      this._cooldowns.delete(key);
      return true;
    }
    return false;
  }

  /**
   * 킬 쿨다운 설정
   * @param {string} sessionId
   * @param {string} killerId
   * @param {number} seconds  쿨다운 시간 (초)
   */
  setKillCooldown(sessionId, killerId, seconds) {
    const key = this._key(sessionId, killerId);
    this._cooldowns.set(key, Date.now() + seconds * 1000);
  }

  /**
   * 남은 쿨다운 시간 반환 (초). 쿨다운 없으면 0.
   * @param {string} sessionId
   * @param {string} killerId
   * @returns {number}
   */
  remainingSeconds(sessionId, killerId) {
    const key     = this._key(sessionId, killerId);
    const expires = this._cooldowns.get(key);
    if (!expires) return 0;
    const remaining = Math.ceil((expires - Date.now()) / 1000);
    return remaining > 0 ? remaining : 0;
  }

  /**
   * 세션 종료 시 해당 세션의 모든 쿨다운 제거
   * @param {string} sessionId
   */
  clearSession(sessionId) {
    const prefix = `${sessionId}:`;
    for (const key of this._cooldowns.keys()) {
      if (key.startsWith(prefix)) {
        this._cooldowns.delete(key);
      }
    }
  }
}

export default new KillCooldownManager();
