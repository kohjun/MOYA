export function makePlayer(overrides = {}) {
  return {
    userId: 'user-1',
    guildId: 'guild_alpha',
    job: 'warrior',
    isAlive: true,
    hp: 100,
    remainingLives: 1,
    reviveAttempts: 0,
    dungeonEnteredAt: null,
    inDuel: false,
    duelExpiresAt: null,
    shields: [],
    trackedTargetUserId: null,
    revealUntil: null,
    executionArmedUntil: null,
    captureZone: null,
    ...overrides,
  };
}

export function makeControlPoint(overrides = {}) {
  return {
    id: 'cp-1',
    location: { lat: 37.0, lng: 127.0 },
    capturedBy: null,
    blockadedBy: null,
    blockadeExpiresAt: null,
    capturingGuild: null,
    captureProgress: 0,
    captureStartedAt: null,
    captureParticipantUserIds: [],
    readyCount: 0,
    requiredCount: 0,
    ...overrides,
  };
}

export function makeGameState(overrides = {}) {
  return {
    alivePlayerIds: [],
    pluginState: {
      eliminatedPlayerIds: [],
      controlPoints: [],
      captureIntents: {},
      playerStates: {},
      ...(overrides.pluginState ?? {}),
    },
    ...overrides,
  };
}
