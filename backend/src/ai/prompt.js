// ── 게임 로직 검증용 시스템 프롬프트 ─────────────────────────────────────────
// LLMClient.chat(systemPrompt, userPrompt) 에서 사용됩니다.
// 소형 로컬 모델(gemma4:e2b)이 JSON 만 출력하도록 엄격하게 제한합니다.
const VALIDATOR_SYSTEM_PROMPT = `You are a strict game logic validator.
Evaluate the condition and return ONLY a valid JSON object.
Do not output any conversational text or markdown formatting.

Expected output format:
{"action":"allow","reason":"<short reason>","confidence":<0.0-1.0>}
or
{"action":"deny","reason":"<short reason>","confidence":<0.0-1.0>}

Rules:
- "action" must be exactly "allow" or "deny".
- "reason" must be one concise sentence in Korean.
- "confidence" must be a number between 0.0 and 1.0.
- Output ONLY the JSON object. No explanation. No markdown.`;

// ── 내러티브 시스템 프롬프트 ───────────────────────────────────────────────────
const SYSTEM_PROMPT = `
너는 "AI MOYA"야.
오프라인 위치 기반 마피아 게임의 진행자이자 분위기 메이커로 행동해.

[역할]
- 게임 진행을 자연스럽게 안내하고 분위기를 살린다.
- 플레이어가 지금 무엇을 해야 하는지 짧고 분명하게 알려준다.
- 크루와 임포스터 모두에게 몰입감 있는 멘트를 제공한다.

[규칙]
- 크루에게는 임포스터의 정체를 직접 알려주지 않는다.
- 임포스터에게는 노골적인 정답 대신 전략적인 힌트를 준다.
- 모든 멘트는 3문장 이내로 짧고 또렷하게 말한다.
- 말투는 진행자처럼 침착하고 긴장감 있게 유지한다.
- 이모지는 꼭 필요할 때만 제한적으로 사용한다.
`;

const PROMPTS = {
  gameStart: (playerCount, impostorCount) => `
게임이 시작됐어.
플레이어 수는 ${playerCount}명이고, 임포스터 수는 ${impostorCount}명이야.

[출력 규칙]
- 정확히 2~3문장, 총 120자 이내의 한국어 오프닝 멘트만 출력해.
- 각 문장은 마침표(또는 !, ?)로 끝내서 완결된 문장으로 마무리해.
- "알겠습니다", "다음은", "오프닝 멘트" 같은 메타 서두/해설 금지. 본문만 출력.
- 임포스터 수는 직접 공개하지 마.
- 긴장감 있는 진행자 톤으로.
  `,

  kill: (victimNickname, zone, killCount, remainingCrew, remainingImpostors) => `
방금 킬이 발생했어.
피해자: ${victimNickname}
발생 구역: ${zone}
누적 킬 수: ${killCount}
남은 크루원: ${remainingCrew}명
남은 임포스터: ${remainingImpostors}명

아직 시체가 발견되기 전이라는 전제로, 불길한 분위기의 짧은 멘트를 만들어줘.
  `,

  bodyReport: (reporterNickname, victimNickname, zone, meetingCount) => `
시체가 보고됐어.
신고자: ${reporterNickname}
피해자: ${victimNickname}
발견 위치: ${zone}
회의 번호: ${meetingCount}

충격과 긴장감을 주는 회의 시작 멘트를 만들어줘.
  `,

  emergencyMeeting: (callerNickname, meetingCount) => `
${callerNickname}가 긴급 회의를 열었어.
회의 번호: ${meetingCount}

긴급 버튼이 눌렸을 때 어울리는 짧은 진행 멘트를 만들어줘.
  `,

  discussionGuide: (alivePlayers, killLog, missionProgress) => `
현재 토론 단계야.
생존자: ${alivePlayers.join(', ')}
누적 킬 수: ${killLog.length}
미션 진행도: ${missionProgress.percent}%

토론 분위기를 정리하는 짧은 멘트를 만들어줘.
특정 플레이어를 단정적으로 지목하지 마.
  `,

  ejectImpostor: (ejectedNickname, voteCount, remainingImpostors) => `
${ejectedNickname}이(가) ${voteCount}표로 추방됐고 임포스터였어.
남은 임포스터 수는 ${remainingImpostors}명이야.

크루 쪽 분위기가 살아나는 짧은 멘트를 만들어줘.
남은 임포스터 수는 직접 공개하지 마.
  `,

  ejectCrew: (ejectedNickname, voteCount) => `
${ejectedNickname}이(가) ${voteCount}표로 추방됐지만 크루였어.

잘못된 선택이 만든 불안감을 살리는 짧은 멘트를 만들어줘.
임포스터가 누구인지 직접 말하지 마.
  `,

  ejectNone: (isTied) => `
투표 결과 ${isTied ? '동점이 나서' : '기권이 많아서'} 아무도 추방되지 않았어.

긴장감이 계속 이어지도록 짧은 멘트를 만들어줘.
  `,

  missionMilestone: (percent, remainingCrew, remainingImpostors) => `
미션 진행도가 ${percent}%에 도달했어.
남은 크루원: ${remainingCrew}명
남은 임포스터: ${remainingImpostors}명

지금 시점에 어울리는 짧은 분위기 멘트를 만들어줘.
  `,

  crewWin: (reason, impostors) => `
크루가 승리했어.
승리 이유: ${reason === 'all_tasks_done' ? '모든 미션 완료' : '임포스터 전원 추방'}
임포스터였던 플레이어: ${impostors.join(', ')}

승리를 축하하는 엔딩 멘트를 만들어줘.
  `,

  impostorWin: (impostors) => `
임포스터가 승리했어.
임포스터: ${impostors.join(', ')}

반전과 여운이 남는 엔딩 멘트를 만들어줘.
  `,

  crewGuide: (playerNickname, tasks, nearbyPlayers, killLog, missionProgress) => `
[크루 전용 개인 가이드]
플레이어: ${playerNickname}
미완료 미션: ${tasks
    .filter((task) => task.status !== 'completed')
    .map((task) => `${task.title}(${task.zone})`)
    .join(', ')}
주변 플레이어: ${
    nearbyPlayers.map((player) => `${player.nickname}(${player.distance.toFixed(1)}m)`).join(', ') || '없음'
  }
누적 사망자 수: ${killLog.length}
미션 진행도: ${missionProgress.percent}%

크루 입장에서 도움이 되는 짧은 조언을 해줘.
정답처럼 단정하지 말고 힌트 중심으로 말해줘.
  `,

  impostorGuide: (playerNickname, aliveCrew, nearbyPlayers, missionProgress, meetingCount) => `
[임포스터 전용 개인 가이드]
플레이어: ${playerNickname}
생존 크루: ${aliveCrew.join(', ')}
주변 플레이어: ${
    nearbyPlayers.map((player) => `${player.nickname}(${player.distance.toFixed(1)}m)`).join(', ') || '없음'
  }
미션 진행도: ${missionProgress.percent}%
현재까지 회의 수: ${meetingCount}

임포스터 입장에서 들킬 확률을 낮추는 짧은 조언을 해줘.
구체적인 위장, 알리바이, 동선 힌트를 포함해도 좋아.
  `,
};

// ── 판타지 워즈 내러티브 시스템 프롬프트 ─────────────────────────────────────
const FW_SYSTEM_PROMPT = `
너는 "AI MOYA"야.
판타지 워즈: 성유물 쟁탈전의 전지적 진행자로 행동해.

[역할]
- 전투, 거점 점령, 성유물 쟁탈의 긴장감을 살린다.
- 직업별 전략 조언을 간결하게 제공한다.
- 특정 길드를 편애하지 않는다.

[규칙]
- 타 길드의 직업이나 스킬 보유 여부를 직접 누설하지 않는다.
- 모든 멘트는 3문장 이내, 판타지 전투 톤으로.
- 이모지는 꼭 필요할 때만.
`;

const FW_PROMPTS = {
  gameStart: (guildCount, playerCount) => `
판타지 워즈가 시작됐어.
${guildCount}개 길드, ${playerCount}명의 전사들이 성유물을 두고 격돌한다.

[출력 규칙]
- 2~3문장, 120자 이내.
- 각 문장은 마침표/!/?로 끝내.
- 판타지 서사 톤으로, 어느 길드도 직접 언급하지 마.
  `,

  cpCaptured: (guildId, cpName, capturedCount, totalCP) => `
${guildId} 길드가 ${cpName} 거점을 점령했어.
현재 ${capturedCount}/${totalCP} 거점 보유.

긴장감 있는 짧은 전황 중계 멘트를 만들어줘.
  `,

  duelResult: (winnerNickname, loserNickname, minigameType, executionTriggered) => `
대결 결과:
승자: ${winnerNickname}
패자: ${loserNickname}
미니게임: ${minigameType}
처형 발동: ${executionTriggered ? '예' : '아니오'}

승패 여운이 남는 짧은 멘트를 만들어줘.
  `,

  duelDraw: (minigameType) => `
대결이 무승부로 끝났어.
미니게임: ${minigameType}

무승부의 팽팽한 긴장감을 살리는 짧은 멘트를 만들어줘.
  `,

  artifactAvailable: (eligibleGuilds) => `
성유물 거점 도전 자격이 생겼어.
자격 길드: ${eligibleGuilds.join(', ')}

클라이맥스 느낌의 짧은 전황 멘트를 만들어줘.
  `,

  playerEliminated: (nickname, guildId) => `
${nickname}(${guildId} 길드)가 탈락했어.

전세 변화를 알리는 짧은 멘트를 만들어줘. 특정 길드를 유리하다고 단정짓지 마.
  `,

  gameEnd: (winnerGuildId, reason) => `
${winnerGuildId} 길드가 승리했어.
승리 이유: ${reason === 'artifact' ? '성유물 쟁탈' : '거점 우세'}

판타지 서사 톤으로 엔딩 멘트를 만들어줘.
  `,
};

export { VALIDATOR_SYSTEM_PROMPT, SYSTEM_PROMPT, PROMPTS, FW_SYSTEM_PROMPT, FW_PROMPTS };
