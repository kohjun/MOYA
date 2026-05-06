import test from 'node:test';
import assert from 'node:assert/strict';

import { validateFantasyWarsStart } from '../../src/game/plugins/fantasy_wars_artifact/startValidation.js';

function makeConfig() {
  return {
    teamCount: 3,
    teams: [
      { teamId: 'guild_alpha', displayName: '붉은 길드' },
      { teamId: 'guild_beta', displayName: '푸른 길드' },
      { teamId: 'guild_gamma', displayName: '초록 길드' },
    ],
  };
}

function makeMembers(teamAssignments) {
  return teamAssignments.map((teamId, index) => ({
    user_id: `user-${index + 1}`,
    team_id: teamId,
  }));
}

test('validateFantasyWarsStart accepts a 3-3-3 lobby', () => {
  const result = validateFantasyWarsStart(
    makeMembers([
      'guild_alpha', 'guild_alpha', 'guild_alpha',
      'guild_beta', 'guild_beta', 'guild_beta',
      'guild_gamma', 'guild_gamma', 'guild_gamma',
    ]),
    makeConfig(),
  );

  assert.equal(result.requiredTotalPlayers, 3);
  assert.equal(result.minimumPlayersPerTeam, 1);
  assert.deepEqual(result.teamCounts, {
    guild_alpha: 3,
    guild_beta: 3,
    guild_gamma: 3,
  });
});

test('validateFantasyWarsStart rejects lobbies below the minimum total player count (dev default)', () => {
  // [DEV DEFAULT] 현재 DEFAULT_MIN_TOTAL_PLAYERS=3, MIN_PLAYERS_PER_TEAM=1 (에뮬레이터/QA 친화).
  // 운영 전환 시 startValidation.js 의 상수 또는 config override 로 강화 (전형 9 / 3) 필요.
  // 자세한 운영 override 구조는 README 의 운영 전환 체크리스트 + 본 파일 하단 주석 참조.
  assert.throws(
    () => validateFantasyWarsStart(
      makeMembers([
        'guild_alpha',
        'guild_beta',
      ]),
      makeConfig(),
    ),
    (error) => {
      assert.equal(error.message, 'FANTASY_WARS_NOT_ENOUGH_PLAYERS');
      assert.equal(error.details.required, 3);
      assert.equal(error.details.current, 2);
      return true;
    },
  );
});

test('validateFantasyWarsStart rejects unassigned players before game start', () => {
  assert.throws(
    () => validateFantasyWarsStart(
      makeMembers([
        'guild_alpha', 'guild_alpha', 'guild_alpha',
        'guild_beta', 'guild_beta', 'guild_beta',
        'guild_gamma', 'guild_gamma', null,
      ]),
      makeConfig(),
    ),
    (error) => {
      assert.equal(error.message, 'FANTASY_WARS_TEAM_ASSIGNMENT_REQUIRED');
      assert.equal(error.details.unassignedCount, 1);
      return true;
    },
  );
});

test('validateFantasyWarsStart rejects teams that cannot support capture play (dev default)', () => {
  // [DEV DEFAULT] MIN_PLAYERS_PER_TEAM=1. 운영에서는 보통 2-3 명을 강제.
  // dev 룰에서는 0 명 팀만 undersized 로 분류된다. unassigned 와 구분되므로 별도 길드에 0명 배정 시나리오.
  // 단, member 가 모두 valid teamId 를 가지면 unassigned 가 아닌 빈 팀 상황은 실제로 발생 안 하며,
  // 운영 룰 (per-team minimum 강화) 도입 후 의미 있는 검증이 가능해진다 (하단 운영 override 테스트 참조).
  assert.throws(
    () => validateFantasyWarsStart(
      // alpha 0, beta 2, gamma 1 → alpha 가 0 < 1 = MIN_PLAYERS_PER_TEAM
      makeMembers([
        'guild_beta', 'guild_beta',
        'guild_gamma',
      ]),
      makeConfig(),
    ),
    (error) => {
      assert.equal(error.message, 'FANTASY_WARS_TEAM_SIZE_TOO_SMALL');
      assert.equal(error.details.minimumPlayersPerTeam, 1);
      assert.deepEqual(error.details.undersizedTeams, [
        {
          teamId: 'guild_alpha',
          displayName: '붉은 길드',
          memberCount: 0,
          requiredCount: 1,
        },
      ]);
      return true;
    },
  );
});
