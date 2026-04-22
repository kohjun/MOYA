// src/services/sessionService.js
import { query, withTransaction } from '../config/database.js';
import { setCache, getCache, delCache, delPattern } from '../config/redis.js';
import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';

const SESSION_CODE_LENGTH = 6;
const FANTASY_WARS_GAME_TYPE = 'fantasy_wars_artifact';
const LEGACY_FANTASY_WARS_GAME_TYPE = 'fantasy_wars';
const FANTASY_WARS_TEAM_DEFINITIONS = [
  { teamId: 'guild_alpha', displayName: '붉은 길드', color: '#DC2626' },
  { teamId: 'guild_beta', displayName: '푸른 길드', color: '#2563EB' },
  { teamId: 'guild_gamma', displayName: '초록 길드', color: '#16A34A' },
  { teamId: 'guild_delta', displayName: '황금 길드', color: '#D97706' },
];

const isFantasyWarsSession = (gameType) =>
  gameType === FANTASY_WARS_GAME_TYPE || gameType === LEGACY_FANTASY_WARS_GAME_TYPE;

const normalizeGameType = (gameType) =>
  isFantasyWarsSession(gameType) ? FANTASY_WARS_GAME_TYPE : (gameType ?? 'among_us');

const clampTeamCount = (value) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 3;
  }

  return Math.min(Math.max(Math.trunc(parsed), 3), FANTASY_WARS_TEAM_DEFINITIONS.length);
};

const normalizeGeoPoint = (point) => {
  const lat = Number(point?.lat ?? point?.latitude);
  const lng = Number(point?.lng ?? point?.longitude ?? point?.lon);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return null;
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return null;
  }

  return { lat, lng };
};

const normalizePolygon = (points) => {
  if (!Array.isArray(points)) {
    return null;
  }

  const polygon = points.map(normalizeGeoPoint).filter(Boolean);
  return polygon.length >= 3 ? polygon : null;
};

const normalizePointList = (points, expectedCount = null) => {
  if (!Array.isArray(points)) {
    return null;
  }

  const list = points.map(normalizeGeoPoint).filter(Boolean);
  if (expectedCount != null && list.length !== expectedCount) {
    return null;
  }

  return list;
};

const buildFantasyWarsTeams = (teamCount = 3) =>
  FANTASY_WARS_TEAM_DEFINITIONS.slice(0, clampTeamCount(teamCount));

const normalizeFantasyWarsTeamDisplayName = (displayName, fallback) => {
  const value = typeof displayName === 'string' ? displayName.trim() : '';
  if (!value) {
    return fallback;
  }

  switch (value) {
    case 'Red Guild':
      return '붉은 길드';
    case 'Blue Guild':
      return '푸른 길드';
    case 'Green Guild':
      return '초록 길드';
    case 'Gold Guild':
      return '황금 길드';
    case 'Red Team':
      return '붉은 팀';
    case 'Blue Team':
      return '푸른 팀';
    case 'Green Team':
      return '초록 팀';
    default:
      return value;
  }
};

const normalizeFantasyWarsTeam = (team, index = 0) => {
  const fallback = FANTASY_WARS_TEAM_DEFINITIONS[index]
    ?? FANTASY_WARS_TEAM_DEFINITIONS.find((candidate) => candidate.teamId === team?.teamId)
    ?? null;

  return {
    teamId: team?.teamId ?? fallback?.teamId ?? `guild_${index + 1}`,
    displayName: normalizeFantasyWarsTeamDisplayName(
      team?.displayName,
      fallback?.displayName ?? `길드 ${index + 1}`,
    ),
    color: team?.color ?? fallback?.color ?? '#9CA3AF',
  };
};

const buildFantasyWarsGameConfig = (gameConfig = {}) => {
  const teamCount = clampTeamCount(gameConfig.teamCount);
  const teams = buildFantasyWarsTeams(teamCount);

  return {
    ...gameConfig,
    teamCount,
    controlPointCount: Number.isFinite(Number(gameConfig.controlPointCount))
      ? Math.max(1, Math.trunc(Number(gameConfig.controlPointCount)))
      : 5,
    teams,
    controlPoints: Array.isArray(gameConfig.controlPoints) ? gameConfig.controlPoints : [],
    spawnZones: Array.isArray(gameConfig.spawnZones) ? gameConfig.spawnZones : [],
  };
};

const getSessionTeamDefinitions = (session) => {
  const configuredTeams = Array.isArray(session?.game_config?.teams)
    ? session.game_config.teams
    : [];

  if (configuredTeams.length > 0) {
    return configuredTeams.map((team, index) => normalizeFantasyWarsTeam(team, index));
  }

  return buildFantasyWarsTeams(session?.game_config?.teamCount);
};

const invalidateSessionCaches = async (sessionId, sessionCode = null) => {
  await delCache(`session:${sessionId}`);
  if (sessionCode) {
    await delCache(`session:code:${sessionCode}`);
  }
};

const resolveInitialTeamId = async (client, session) => {
  if (!isFantasyWarsSession(session?.game_type)) {
    return null;
  }

  const teams = getSessionTeamDefinitions(session);
  const { rows } = await client.query(
    `SELECT COALESCE(pre_game_team, game_team) AS team_id, COUNT(*)::int AS member_count
     FROM session_members
     WHERE session_id = $1 AND left_at IS NULL
     GROUP BY COALESCE(pre_game_team, game_team)`,
    [session.id]
  );

  const counts = new Map(teams.map((team) => [team.teamId, 0]));
  rows.forEach((row) => {
    if (counts.has(row.team_id)) {
      counts.set(row.team_id, row.member_count);
    }
  });

  return teams.reduce((bestTeamId, team) => {
    if (!bestTeamId) {
      return team.teamId;
    }

    return counts.get(team.teamId) < counts.get(bestTeamId)
      ? team.teamId
      : bestTeamId;
  }, null);
};

// ?????????????????????????????????????????????????????????????????????????????
// ?좊땲???몄뀡 肄붾뱶 ?앹꽦 (?レ옄 + ?臾몄옄 議고빀)
// ?????????????????????????????????????????????????????????????????????????????
const generateSessionCode = async () => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // ?쇰룞 臾몄옄 ?쒖쇅 (I,O,1,0)
  for (let attempt = 0; attempt < 10; attempt++) {
    let code = '';
    for (let i = 0; i < SESSION_CODE_LENGTH; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
    // 以묐났 ?뺤씤
    const { rows } = await query(
      "SELECT id FROM sessions WHERE session_code = $1 AND status = 'active'",
      [code]
    );
    if (rows.length === 0) return code;
  }
  throw new Error('SESSION_CODE_GENERATION_FAILED');
};

// ?????????????????????????????????????????????????????????????????????????????
// ?몄뀡 ?앹꽦
// ?????????????????????????????????????????????????????????????????????????????
export const createSession = async (hostUserId, {
  name,
  activeModules   = [],
  durationHours,
  maxMembers,
  gameType,
  gameConfig,
  gameVersion,
  impostorCount,
  killCooldown,
  discussionTime,
  voteTime,
  missionPerCrew,
} = {}) => {
  const code = await generateSessionCode();
  const expiresAt = new Date(Date.now() + ((durationHours ?? 24) * 60 * 60 * 1000));

  const rows = await withTransaction(async (client) => {
    // [Task 5] 寃뚯엫 ?ㅼ젙??module_configs JSONB ?먮룄 ???(?대씪?댁뼵???대갚??
    const resolvedKillCooldown   = killCooldown   ?? 30;
    const resolvedDiscussionTime = discussionTime ?? 90;
    const resolvedVoteTime       = voteTime       ?? 30;
    const resolvedMissionPerCrew = missionPerCrew ?? 3;
    const moduleConfigsJson = JSON.stringify({
      killCooldown:      resolvedKillCooldown,
      emergencyCooldown: resolvedDiscussionTime,
      voteTime:          resolvedVoteTime,
      missionPerCrew:    resolvedMissionPerCrew,
    });

    const resolvedGameType    = normalizeGameType(gameType);
    const resolvedGameConfig  = isFantasyWarsSession(resolvedGameType)
      ? buildFantasyWarsGameConfig(gameConfig ?? {})
      : (gameConfig ?? {});
    const resolvedGameVersion = gameVersion ?? '1.0';
    const initialTeamId = isFantasyWarsSession(resolvedGameType)
      ? buildFantasyWarsTeams(resolvedGameConfig.teamCount)[0]?.teamId ?? null
      : null;

    // ?몄뀡 ?앹꽦 (寃뚯엫 ?ㅼ젙 而щ읆 + module_configs ?ы븿)
    const session = await client.query(
      `INSERT INTO sessions
         (host_user_id, session_code, name, expires_at, active_modules,
          game_type, game_config, game_version,
          max_members, impostor_count, kill_cooldown, discussion_time, vote_time, mission_per_crew,
          module_configs)
       VALUES ($1, $2, $3, $4, $5,
               $6, $7::jsonb, $8,
               COALESCE($9, 50), COALESCE($10, 1), $11,
               $12, $13, $14, $15::jsonb)
       RETURNING id, host_user_id, session_code, name, status, created_at, expires_at,
                 active_modules, module_configs, max_members,
                 game_type, game_config, game_version,
                 impostor_count, kill_cooldown, discussion_time, vote_time, mission_per_crew`,
      [
        hostUserId, code, name || null, expiresAt, activeModules,
        resolvedGameType,
        JSON.stringify(resolvedGameConfig),
        resolvedGameVersion,
        maxMembers            ?? null,
        impostorCount         ?? null,
        resolvedKillCooldown,
        resolvedDiscussionTime,
        resolvedVoteTime,
        resolvedMissionPerCrew,
        moduleConfigsJson,
      ]
    );
    const sessionId = session.rows[0].id;

    // ?몄뒪?몃? 泥?踰덉㎏ 硫ㅻ쾭濡??먮룞 異붽? (role = 'host')
    await client.query(
      `INSERT INTO session_members (session_id, user_id, role, pre_game_team)
       VALUES ($1, $2, 'host', $3)`,
      [sessionId, hostUserId, initialTeamId]
    );

    return session.rows;
  });

  // Redis???몄뀡 ?뺣낫 罹먯떆 (24?쒓컙)
  await setCache(`session:code:${code}`, rows[0], 86400);
  await setCache(`session:${rows[0].id}`, rows[0], 86400);

  return rows[0];
};

// ?????????????????????????????????????????????????????????????????????????????
// ?몄뀡 李멸? (珥덈? 肄붾뱶濡?
// ?????????????????????????????????????????????????????????????????????????????
export const joinSession = async (userId, sessionCode) => {
  // 肄붾뱶濡??몄뀡 議고쉶 (罹먯떆 ?곗꽑)
  let session = await getCache(`session:code:${sessionCode.toUpperCase()}`);

  if (!session) {
    const { rows } = await query(
      `SELECT id, host_user_id, session_code, name, status, expires_at, max_members,
              game_type, game_config
       FROM sessions
       WHERE session_code = $1 AND status = 'active' AND expires_at > NOW()`,
      [sessionCode.toUpperCase()]
    );
    if (rows.length === 0) throw new Error('SESSION_NOT_FOUND');
    session = rows[0];
  }

  if (session.status !== 'active') throw new Error('SESSION_ENDED');
  if (new Date(session.expires_at) < new Date()) throw new Error('SESSION_EXPIRED');

  const { rows: memberCountRows } = await query(
    `SELECT COUNT(*)::int AS member_count
     FROM session_members
     WHERE session_id = $1 AND left_at IS NULL`,
    [session.id]
  );
  if (memberCountRows[0]?.member_count >= (session.max_members ?? 50)) {
    throw new Error('SESSION_FULL');
  }

  // ?대? 李멸? 以묒씤吏 ?뺤씤
  const { rows: existing } = await query(
    `SELECT id FROM session_members
     WHERE session_id = $1 AND user_id = $2 AND left_at IS NULL`,
    [session.id, userId]
  );
  if (existing.length > 0) throw new Error('ALREADY_IN_SESSION');

  // 硫ㅻ쾭 異붽?
  await withTransaction(async (client) => {
    const initialTeamId = await resolveInitialTeamId(client, session);

    await client.query(
      `INSERT INTO session_members (session_id, user_id, pre_game_team)
       VALUES ($1, $2, $3)
       ON CONFLICT (session_id, user_id)
       DO UPDATE SET left_at = NULL,
                     joined_at = NOW(),
                     pre_game_team = COALESCE(session_members.pre_game_team, EXCLUDED.pre_game_team)`,
      [session.id, userId, initialTeamId]
    );
  });

  return session;
};

// ?????????????????????????????????????????????????????????????????????????????
// ?몄뀡 ?섍?湲?// ?????????????????????????????????????????????????????????????????????????????
export const leaveSession = async (userId, sessionId) => {
  await query(
    `UPDATE session_members
     SET left_at = NOW()
     WHERE session_id = $1 AND user_id = $2 AND left_at IS NULL`,
    [sessionId, userId]
  );

  // ?ㅼ떆媛??꾩튂 罹먯떆 ??젣
  await delCache(`location:${sessionId}:${userId}`);
};

// ?????????????????????????????????????????????????????????????????????????????
// ?몄뀡 醫낅즺 (?몄뒪?몃쭔 媛??
// ?????????????????????????????????????????????????????????????????????????????
export const endSession = async (hostUserId, sessionId) => {
  const { rows } = await query(
    `UPDATE sessions
     SET status = 'ended', ended_at = NOW()
     WHERE id = $1 AND host_user_id = $2
     RETURNING *`,
    [sessionId, hostUserId]
  );
  if (rows.length === 0) throw new Error('SESSION_NOT_FOUND_OR_NOT_HOST');

  // 愿??罹먯떆 ?꾨? ??젣
  await delCache(`session:${sessionId}`);
  await delCache(`session:code:${rows[0].session_code}`);
  await delPattern(`location:${sessionId}:*`);

  return rows[0];
};

// ?????????????????????????????????????????????????????????????????????????????
// ?몄뀡 硫ㅻ쾭 紐⑸줉 議고쉶 (?꾩옱 ?꾩튂 ?ы븿)
// ?????????????????????????????????????????????????????????????????????????????
export const getSessionMembers = async (sessionId) => {
  const { rows } = await query(
    `SELECT sm.user_id, sm.joined_at, sm.sharing_enabled,
            CASE WHEN s.host_user_id = sm.user_id THEN 'host' ELSE 'member' END AS role,
            COALESCE(sm.pre_game_team, sm.game_team) AS team_id,
            u.nickname, u.avatar_url,
            (s.host_user_id = sm.user_id) AS is_host
     FROM session_members sm
     JOIN users u ON u.id = sm.user_id
     JOIN sessions s ON s.id = sm.session_id
     WHERE sm.session_id = $1 AND sm.left_at IS NULL
     ORDER BY sm.joined_at`,
    [sessionId]
  );

  // 媛?硫ㅻ쾭??理쒖떊 ?꾩튂瑜?Redis?먯꽌 議고쉶
  const membersWithLocation = await Promise.all(
    rows.map(async (member) => {
      const location = await getCache(`location:${sessionId}:${member.user_id}`);
      return { ...member, lastLocation: location };
    })
  );

  return membersWithLocation;
};

// ?????????????????????????????????????????????????????????????????????????????
// 硫ㅻ쾭 ??븷 蹂寃?(host/admin留?媛??
// ?????????????????????????????????????????????????????????????????????????????
// ?????????????????????????????????????????????????????????????????????????????
// 硫ㅻ쾭 媛뺤젣 ?댁옣 (host/admin留?媛??
// ?????????????????????????????????????????????????????????????????????????????
export const kickMember = async (requesterId, sessionId, targetUserId) => {
  if (requesterId === targetUserId) throw new Error('CANNOT_KICK_YOURSELF');

  const { rows } = await query(
    `SELECT s.host_user_id,
            sm_tgt.role AS target_role,
            sm_tgt.user_id AS target_exists
     FROM sessions s
     LEFT JOIN session_members sm_tgt
       ON sm_tgt.session_id = s.id AND sm_tgt.user_id = $2 AND sm_tgt.left_at IS NULL
     WHERE s.id = $1`,
    [sessionId, targetUserId]
  );
  if (rows.length === 0) throw new Error('SESSION_NOT_FOUND');

  const { host_user_id, target_role, target_exists } = rows[0];
  if (!target_exists) throw new Error('TARGET_NOT_A_MEMBER');

  const effectiveTargetRole    = targetUserId === host_user_id ? 'host' : (target_role ?? 'member');

  if (requesterId !== host_user_id) throw new Error('PERMISSION_DENIED');
  if (effectiveTargetRole === 'host') throw new Error('CANNOT_KICK_HOST');
  // 愿由ъ옄???ㅻⅨ 愿由ъ옄瑜?媛뺥눜 遺덇?

  await query(
    `UPDATE session_members SET left_at = NOW()
     WHERE session_id = $1 AND user_id = $2 AND left_at IS NULL`,
    [sessionId, targetUserId]
  );

  await delCache(`location:${sessionId}:${targetUserId}`);
};

// ?????????????????????????????????????????????????????????????????????????????
// ?닿? 李멸? 以묒씤 ?몄뀡 紐⑸줉
// ?????????????????????????????????????????????????????????????????????????????
export const getMySessions = async (userId) => {
  const { rows } = await query(
    `SELECT s.id, s.session_code, s.name, s.status,
            s.created_at, s.expires_at, s.active_modules, s.module_configs, s.max_members,
            s.game_type, s.game_config, s.game_version,
            s.host_user_id = $1 AS is_host,
            (SELECT COUNT(*) FROM session_members sm2
             WHERE sm2.session_id = s.id AND sm2.left_at IS NULL) AS member_count
     FROM sessions s
     JOIN session_members sm ON sm.session_id = s.id
     WHERE sm.user_id = $1 AND sm.left_at IS NULL AND s.status = 'active'
     ORDER BY sm.joined_at DESC`,
    [userId]
  );

  // game_status: Redis?먯꽌 寃뚯엫 ?쒖옉 ?щ? ?뺤씤 (??key ?곗꽑, ?덇굅???대갚)
  const withStatus = await Promise.all(
    rows.map(async (row) => {
      const started = await getCache(`game:started:${row.id}`)
                   ?? await getCache(`game:${row.id}:started`);
      return { ...row, game_status: started ? 'playing' : 'lobby' };
    })
  );
  return withStatus;
};

// ?????????????????????????????????????????????????????????????????????????????
// ?몄뀡 ?곸꽭 議고쉶
// ?????????????????????????????????????????????????????????????????????????????
export const getSession = async (sessionId) => {
  const cached = await getCache(`session:${sessionId}`);
  if (
    cached?.host_user_id
    && Object.prototype.hasOwnProperty.call(cached, 'game_type')
    && Object.prototype.hasOwnProperty.call(cached, 'game_config')
    && Object.prototype.hasOwnProperty.call(cached, 'playable_area')
  ) {
    return cached;
  }

  const { rows } = await query(
    `SELECT id, host_user_id, session_code, name, status,
            created_at, expires_at, ended_at, active_modules, module_configs, max_members,
            game_type, game_config, game_version,
            impostor_count, kill_cooldown, discussion_time, vote_time, mission_per_crew,
            playable_area
     FROM sessions
     WHERE id = $1`,
    [sessionId]
  );
  if (rows.length === 0) return null;

  await setCache(`session:${sessionId}`, rows[0], 86400);
  return rows[0];
};

// ?????????????????????????????????????????????????????????????????????????????
// ?뚮젅??媛???곸뿭(?대━怨? ???(?몄뒪?몃쭔 媛??
// polygonPoints: [{lat: number, lng: number}, ...]  理쒖냼 3媛?// ?????????????????????????????????????????????????????????????????????????????
export const setPlayableArea = async (hostUserId, sessionId, polygonPoints) => {
  if (!Array.isArray(polygonPoints) || polygonPoints.length < 3) {
    throw new Error('INVALID_POLYGON');
  }

  const { rows } = await query(
    `UPDATE sessions
     SET playable_area = $1::jsonb
     WHERE id = $2 AND host_user_id = $3
     RETURNING id, session_code, playable_area`,
    [JSON.stringify(polygonPoints), sessionId, hostUserId]
  );
  if (rows.length === 0) throw new Error('SESSION_NOT_FOUND_OR_NOT_HOST');

  // ?몄뀡 罹먯떆 臾댄슚??(?ㅼ쓬 getSession ?몄텧 ??DB?먯꽌 ?ъ“??
  await invalidateSessionCaches(sessionId, rows[0].session_code);
  return rows[0];
};

export const setFantasyWarsLayout = async (
  requesterId,
  sessionId,
  {
    playableArea,
    controlPoints,
    spawnZones,
  } = {},
) => {
  const session = await getSession(sessionId);
  if (!session || session.host_user_id !== requesterId) {
    throw new Error('SESSION_NOT_FOUND_OR_NOT_HOST');
  }
  if (!isFantasyWarsSession(session.game_type)) {
    throw new Error('INVALID_GAME_TYPE');
  }

  const normalizedArea = normalizePolygon(playableArea);
  if (!normalizedArea) {
    throw new Error('INVALID_POLYGON');
  }

  const config = buildFantasyWarsGameConfig(session.game_config ?? {});
  const teams = buildFantasyWarsTeams(config.teamCount);
  const expectedControlPointCount = config.controlPointCount ?? 5;
  const normalizedControlPoints = normalizePointList(controlPoints, expectedControlPointCount);

  if (!normalizedControlPoints) {
    throw new Error('INVALID_CONTROL_POINTS');
  }

  if (!Array.isArray(spawnZones) || spawnZones.length !== teams.length) {
    throw new Error('INVALID_SPAWN_ZONES');
  }

  const normalizedSpawnZones = teams.map((team) => {
    const rawZone = spawnZones.find((zone) => zone?.teamId === team.teamId);
    const polygon = normalizePolygon(rawZone?.polygonPoints ?? rawZone?.points);
    if (!rawZone || !polygon) {
      throw new Error('INVALID_SPAWN_ZONES');
    }

    return {
      teamId: team.teamId,
      displayName: team.displayName,
      color: team.color,
      polygonPoints: polygon,
    };
  });

  const nextConfig = {
    ...config,
    teams,
    controlPoints: normalizedControlPoints,
    spawnZones: normalizedSpawnZones,
    layoutConfiguredAt: new Date().toISOString(),
  };

  const { rows } = await query(
    `UPDATE sessions
     SET playable_area = $1::jsonb,
         game_config = $2::jsonb
     WHERE id = $3 AND host_user_id = $4
     RETURNING id, session_code, playable_area, game_config`,
    [
      JSON.stringify(normalizedArea),
      JSON.stringify(nextConfig),
      sessionId,
      requesterId,
    ]
  );
  if (rows.length === 0) {
    throw new Error('SESSION_NOT_FOUND_OR_NOT_HOST');
  }

  await invalidateSessionCaches(sessionId, rows[0].session_code);
  return rows[0];
};

export const moveMemberToTeam = async (requesterId, sessionId, targetUserId, teamId) => {
  const session = await getSession(sessionId);
  if (!session) {
    throw new Error('SESSION_NOT_FOUND');
  }
  if (!isFantasyWarsSession(session.game_type)) {
    throw new Error('INVALID_GAME_TYPE');
  }

  const requesterIsHost = requesterId === session.host_user_id;
  if (!requesterIsHost && requesterId !== targetUserId) {
    throw new Error('PERMISSION_DENIED');
  }

  const teams = getSessionTeamDefinitions(session);
  if (!teams.some((team) => team.teamId === teamId)) {
    throw new Error('INVALID_TEAM');
  }

  const { rows } = await query(
    `UPDATE session_members
     SET pre_game_team = $1
     WHERE session_id = $2 AND user_id = $3 AND left_at IS NULL
     RETURNING user_id, COALESCE(pre_game_team, game_team) AS team_id`,
    [teamId, sessionId, targetUserId]
  );
  if (rows.length === 0) {
    throw new Error('TARGET_NOT_A_MEMBER');
  }

  return rows[0];
};

