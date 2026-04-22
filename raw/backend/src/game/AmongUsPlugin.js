const AmongUsPlugin = {
  gameType:    'among_us',
  displayName: '어몽어스',

  configSchema: {
    impostorCount:  { type: 'number', default: 1, min: 1, max: 3 },
    killCooldown:   { type: 'number', default: 30, min: 10, max: 60 },
    discussionTime: { type: 'number', default: 90, min: 30, max: 180 },
    voteTime:       { type: 'number', default: 30, min: 15, max: 60 },
    missionPerCrew: { type: 'number', default: 3, min: 1, max: 5 },
    killDistance:   { type: 'number', default: 3, min: 1, max: 10 },
  },

  requiredModules: ['proximity', 'vote', 'mission', 'item'],

  assignRoles(members, config) {
    const count     = config.impostorCount || 1;
    const shuffled  = [...members].sort(() => Math.random() - 0.5);
    const impostors = new Set(shuffled.slice(0, count).map(m => m.user_id));
    return members.map(m => ({
      userId:    m.user_id,
      role:      impostors.has(m.user_id) ? 'impostor' : 'crew',
      team:      impostors.has(m.user_id) ? 'impostor' : 'crew',
    }));
  },

  checkWinCondition(gameState) {
    const aliveImpostors = gameState.impostors.filter(id =>
      gameState.aliveMembers.includes(id)
    );
    const aliveCrew = gameState.aliveMembers.filter(id =>
      !gameState.impostors.includes(id)
    );

    if (aliveImpostors.length === 0)
      return { winner: 'crew', reason: 'impostors_ejected' };
    if (aliveImpostors.length >= aliveCrew.length)
      return { winner: 'impostor', reason: 'outnumbered' };
    return null;
  },

  getCurrentPhase(gameState) {
    return gameState?.status ?? 'playing';
  },

  getSystemPrompt(role, nickname) {
    const base = `너는 어몽어스 오프라인 게임의 AI 진행자야. 플레이어 닉네임: ${nickname}\n답변은 반드시 완전한 문장으로 끝내고, 5문장을 넘지 마.`;
    if (role === 'impostor') {
      return base + '\n이 플레이어는 임포스터야. 전략적으로 조언하되 다른 플레이어에게 정체가 들키지 않도록 해.';
    }
    return base + '\n이 플레이어는 크루원이야. 미션 완수와 임포스터 색출을 도와줘. 임포스터가 누구인지는 절대 알려주지 마.';
  },

  buildStateContext(gameState, player) {
    // players가 Map이면 .size, 배열이면 .length, alivePlayerIds가 있으면 그걸 우선 사용
    const aliveCount =
      gameState.alivePlayerIds?.length ??
      (gameState.players instanceof Map
        ? gameState.players.size
        : gameState.players?.length) ??
      gameState.aliveMembers?.length ??
      0;
    return [
      `생존자 수: ${aliveCount}명`,
      `킬 로그: ${gameState.killLog?.length ?? 0}건`,
      `내 역할: ${player.roleId ?? player.role}`,
      `내 팀: ${player.team}`,
    ].join('\n');
  },

  getKnowledgeChunks() {
    // 나중에 mafia 등 추가 시 여기만 교체하면 됨
    return import('./knowledgeBase/index.js');
  },
};

export default AmongUsPlugin;
