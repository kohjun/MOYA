'use strict';

// [DEV DEFAULT] Local/emulator-friendly minimums (3 total / 1 per team).
// Production typically requires stricter values (e.g. 9 total / 3 per team for full 3-3-3 capture play).
//
// 현재 구조상 이 두 상수는 module-level 하드코딩이라 host config 또는 env 로 직접 override 가 불가능.
// 운영 전환 시 권장 도입 방식:
//   1) schema.js 에 minTotalPlayers, minPlayersPerTeam 필드를 추가 (default: 3 / 1, min: 1)
//   2) validateFantasyWarsStart(members, config) 에서 config 우선 사용,
//      fallback 으로 본 module-level 상수 — 즉 dev default 와 schema default 의 일관성 유지
//   3) host UI 또는 env 로 lobby 생성 시 더 엄격한 minimum 을 명시할 수 있게 노출
// 도입 전까지는 운영 배포 시 본 상수 값을 직접 변경 (e.g. 9 / 2) 하는 것이 minimal route.
// 자세한 운영 전환 체크리스트는 루트 README.md 를 참조.
const DEFAULT_MIN_TOTAL_PLAYERS = 3;
const MIN_PLAYERS_PER_TEAM = 1;

function getConfiguredTeams(config = {}) {
  const teams = Array.isArray(config.teams) ? config.teams : [];
  return teams.filter((team) => typeof team?.teamId === 'string' && team.teamId);
}

export function validateFantasyWarsStart(members = [], config = {}) {
  const teams = getConfiguredTeams(config);
  const teamIds = teams.map((team) => team.teamId);
  const teamCounts = Object.fromEntries(teamIds.map((teamId) => [teamId, 0]));
  let unassignedCount = 0;

  members.forEach((member) => {
    const teamId = member?.team_id;
    if (!teamId || !(teamId in teamCounts)) {
      unassignedCount += 1;
      return;
    }

    teamCounts[teamId] += 1;
  });

  const requiredTotalPlayers = Math.max(
    DEFAULT_MIN_TOTAL_PLAYERS,
    Math.max(teams.length, 1) * 1,
  );
  const undersizedTeams = teams
    .filter((team) => (teamCounts[team.teamId] ?? 0) < MIN_PLAYERS_PER_TEAM)
    .map((team) => ({
      teamId: team.teamId,
      displayName: team.displayName ?? team.teamId,
      memberCount: teamCounts[team.teamId] ?? 0,
      requiredCount: MIN_PLAYERS_PER_TEAM,
    }));

  if (members.length < requiredTotalPlayers) {
    const error = new Error('FANTASY_WARS_NOT_ENOUGH_PLAYERS');
    error.details = {
      required: requiredTotalPlayers,
      current: members.length,
      perTeamTarget: 1,
      teamCounts,
    };
    throw error;
  }

  if (unassignedCount > 0) {
    const error = new Error('FANTASY_WARS_TEAM_ASSIGNMENT_REQUIRED');
    error.details = {
      unassignedCount,
      teamCounts,
    };
    throw error;
  }

  if (undersizedTeams.length > 0) {
    const error = new Error('FANTASY_WARS_TEAM_SIZE_TOO_SMALL');
    error.details = {
      minimumPlayersPerTeam: MIN_PLAYERS_PER_TEAM,
      undersizedTeams,
      teamCounts,
    };
    throw error;
  }

  return {
    requiredTotalPlayers,
    minimumPlayersPerTeam: MIN_PLAYERS_PER_TEAM,
    teamCounts,
  };
}
