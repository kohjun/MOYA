// src/ai/prompt.js

const SYSTEM_PROMPT = `
너는 "어몽어스 오프라인" 게임의 AI 마스터야.
실제 공간에서 사람들이 어몽어스를 오프라인으로 즐기고 있어.

[역할]
- 게임 진행을 중재하고 분위기를 살리는 해설자
- 각 플레이어에게 역할에 맞는 개인 가이드 제공
- 긴장감과 몰입감을 높이는 내레이터

[규칙]
- 크루원에게는 절대 임포스터가 누구인지 알려주지 마
- 임포스터에게는 은밀하고 전략적으로 조언해
- 모든 멘트는 3문장 이내로 짧고 임팩트 있게
- 한국어로 답변
- 이모지 적절히 사용해서 분위기 살리기
`;

const PROMPTS = {

  // ── 게임 시작 ───────────────────────────────────────────
  gameStart: (playerCount, impostorCount) => `
게임이 시작됐어.
플레이어 수: ${playerCount}명
임포스터 수: ${impostorCount}명 (플레이어들은 모름)

게임 시작을 알리는 긴장감 있는 멘트를 해줘.
임포스터가 몇 명인지는 언급하지 마.
  `,

  // ── 킬 발생 ────────────────────────────────────────────
  kill: (victimNickname, zone, killCount, remainingCrew, remainingImpostors) => `
방금 킬이 발생했어.
피해자: ${victimNickname}
발생 구역: ${zone}
누적 킬 수: ${killCount}번째
남은 크루원: ${remainingCrew}명
남은 임포스터: ${remainingImpostors}명 (공개 안 함)

시체가 발견되기 전까지는 아직 아무도 몰라.
크루원들에게 불길한 분위기를 조성하는 짧은 멘트를 해줘.
임포스터 수나 누가 죽었는지 직접 언급하지 마.
  `,

  // ── 시체 발견/신고 ─────────────────────────────────────
  bodyReport: (reporterNickname, victimNickname, zone, meetingCount) => `
시체가 신고됐어.
신고자: ${reporterNickname}
피해자: ${victimNickname}
발견 구역: ${zone}
이번이 ${meetingCount}번째 회의

긴급 회의 소집을 알리는 충격적인 멘트를 해줘.
  `,

  // ── 긴급 버튼 ──────────────────────────────────────────
  emergencyMeeting: (callerNickname, meetingCount) => `
${callerNickname}이(가) 긴급 버튼을 눌렀어.
이번이 ${meetingCount}번째 회의

긴급 회의 소집 멘트를 해줘.
왜 긴급버튼을 눌렀는지는 아직 모르니까 의문을 남겨줘.
  `,

  // ── 회의 진행 중 ───────────────────────────────────────
  discussionGuide: (alivePlayers, killLog, missionProgress) => `
현재 토론이 진행 중이야.

생존자 목록: ${alivePlayers.join(', ')}
지금까지 발생한 킬: ${killLog.length}건
미션 진행도: ${missionProgress.percent}%

토론을 유도하는 멘트를 해줘.
수상한 정황을 암시하되 특정인을 지목하지 마.
  `,

  // ── 투표 결과: 임포스터 추방 ───────────────────────────
  ejectImpostor: (ejectedNickname, voteCount, remainingImpostors) => `
${ejectedNickname}이(가) 추방됐고 임포스터였어.
득표 수: ${voteCount}표
남은 임포스터: ${remainingImpostors}명 (공개 안 함)

크루원의 승리에 가까워졌다는 분위기의 멘트를 해줘.
남은 임포스터 수는 언급하지 마.
  `,

  // ── 투표 결과: 크루원 추방 ─────────────────────────────
  ejectCrew: (ejectedNickname, voteCount) => `
${ejectedNickname}이(가) 추방됐는데 크루원이었어.
득표 수: ${voteCount}표

임포스터에게 유리해진 상황.
크루원들이 실수를 했다는 분위기의 멘트를 해줘.
임포스터가 누구인지는 절대 언급하지 마.
  `,

  // ── 투표 결과: 추방 없음 ───────────────────────────────
  ejectNone: (isTied) => `
투표 결과 ${isTied ? '동률이 나와서' : 'SKIP으로'} 아무도 추방되지 않았어.

긴장감을 높이는 멘트를 해줘.
임포스터가 살아남았다는 불안감을 조성해.
  `,

  // ── 미션 진행도 마일스톤 ───────────────────────────────
  missionMilestone: (percent, remainingCrew, remainingImpostors) => `
미션 진행도가 ${percent}%가 됐어.
남은 크루원: ${remainingCrew}명

${percent >= 75
  ? '크루원이 거의 이길 것 같은 긴박한 상황이야. 임포스터 입장에서의 위기감을 표현해줘.'
  : percent >= 50
    ? '미션이 절반 완료됐어. 팽팽한 긴장감을 표현해줘.'
    : '미션이 아직 많이 남았어. 크루원들에게 독려하는 멘트를 해줘.'
}
  `,

  // ── 게임 종료: 크루원 승리 ─────────────────────────────
  crewWin: (reason, impostors) => `
크루원이 승리했어!
승리 이유: ${reason === 'all_tasks_done' ? '미션 전부 완료' : '임포스터 전원 추방'}
임포스터였던 플레이어: ${impostors.join(', ')}

크루원의 승리를 축하하는 멘트를 해줘. 임포스터도 공개해줘.
  `,

  // ── 게임 종료: 임포스터 승리 ──────────────────────────
  impostorWin: (impostors) => `
임포스터가 승리했어!
임포스터: ${impostors.join(', ')}

임포스터의 승리를 선언하고 반전을 강조하는 멘트를 해줘.
  `,

  // ── 역할별 개인 가이드: 크루원 ────────────────────────
  crewGuide: (playerNickname, tasks, nearbyPlayers, killLog, missionProgress) => `
[크루원 개인 가이드 - 본인에게만 전달]
플레이어: ${playerNickname}

미완료 미션: ${tasks.filter(t => t.status !== 'completed').map(t => `${t.title}(${t.zone})`).join(', ')}
주변 플레이어: ${nearbyPlayers.map(p => `${p.nickname}(${p.distance.toFixed(1)}m)`).join(', ') || '없음'}
누적 사망: ${killLog.length}명
미션 진행도: ${missionProgress.percent}%

이 크루원에게 지금 상황에 맞는 전략적 조언을 해줘.
수상한 점이 있으면 힌트를 줘도 되지만 임포스터가 누구인지는 절대 말하지 마.
  `,

  // ── 역할별 개인 가이드: 임포스터 ─────────────────────
  impostorGuide: (playerNickname, aliveCrew, nearbyPlayers, missionProgress, meetingCount) => `
[임포스터 개인 가이드 - 본인에게만 전달]
플레이어: ${playerNickname}

남은 크루원: ${aliveCrew.join(', ')}
주변 크루원: ${nearbyPlayers.map(p => `${p.nickname}(${p.distance.toFixed(1)}m)`).join(', ') || '없음'}
미션 진행도: ${missionProgress.percent}% (높을수록 위험)
지금까지 회의 수: ${meetingCount}번

임포스터에게 지금 상황에서 살아남을 전략을 은밀하게 조언해줘.
킬 타이밍, 알리바이, 투표 전략 등을 구체적으로 조언해줘.
  `,
};

export { SYSTEM_PROMPT, PROMPTS };
