import 'fantasy_wars_models.dart';

Map<String, FwGuildInfo> parseGuilds(Object? raw) {
  final guilds = <String, FwGuildInfo>{};
  if (raw is! Map) {
    return guilds;
  }

  raw.forEach((key, value) {
    if (key is String && value is Map) {
      guilds[key] = FwGuildInfo.fromMap(Map<String, dynamic>.from(value));
    }
  });
  return guilds;
}

List<FwControlPoint> parseControlPoints(Object? raw) {
  if (raw is! List) {
    return const [];
  }

  return raw
      .whereType<Map>()
      .map(
          (value) => FwControlPoint.fromMap(Map<String, dynamic>.from(value)))
      .toList(growable: false);
}

List<FwGeoPoint> parseGeoPoints(Object? raw) {
  if (raw is! List) {
    return const [];
  }

  return raw
      .whereType<Map>()
      .map((value) => FwGeoPoint.fromMap(Map<String, dynamic>.from(value)))
      .toList(growable: false);
}

List<FwSpawnZone> parseSpawnZones(Object? raw) {
  if (raw is! List) {
    return const [];
  }

  return raw
      .whereType<Map>()
      .map((value) => FwSpawnZone.fromMap(Map<String, dynamic>.from(value)))
      .toList(growable: false);
}

List<FwDungeonState> parseDungeons(Object? raw) {
  if (raw is! List) {
    return const [];
  }

  return raw
      .whereType<Map>()
      .map(
          (value) => FwDungeonState.fromMap(Map<String, dynamic>.from(value)))
      .toList(growable: false);
}

FwMyState parseMyState(FwMyState current, Map<String, dynamic> data) {
  final rawSkillUsedAt =
      (data['skillUsedAt'] as Map?)?.cast<String, dynamic>() ?? const {};
  final skillUsedAt = <String, int>{};
  rawSkillUsedAt.forEach((skill, usedAt) {
    final lastUsedAt = (usedAt as num?)?.toInt();
    if (lastUsedAt == null) {
      return;
    }
    skillUsedAt[skill] = lastUsedAt + cooldownMsForSkill(skill);
  });

  final hasSkillUsedAt = data.containsKey('skillUsedAt');
  final shields = data['shields'];
  final shieldCount = shields is List ? shields.length : current.shieldCount;
  final isAlive = data['isAlive'] as bool? ?? current.isAlive;
  final nextReviveChance = (data['nextReviveChance'] as num?)?.toDouble();
  final dungeonEntered = data['dungeonEntered'] as bool?;
  final nextReviveAt = (data['nextReviveAt'] as num?)?.toInt();
  final reviveReady = data['reviveReady'] as bool?;

  return current.copyWith(
    guildId: data['guildId'] as String?,
    job: data['job'] as String?,
    isGuildMaster: data['isGuildMaster'] as bool? ?? current.isGuildMaster,
    isAlive: isAlive,
    hp: (data['hp'] as num?)?.toInt() ?? current.hp,
    remainingLives:
        (data['remainingLives'] as num?)?.toInt() ?? current.remainingLives,
    shieldCount: shieldCount,
    captureZone: data['captureZone'] as String?,
    inDuel: data['inDuel'] as bool? ?? current.inDuel,
    duelExpiresAt: (data['duelExpiresAt'] as num?)?.toInt(),
    executionArmedUntil: (data['executionArmedUntil'] as num?)?.toInt(),
    buffedUntil: (data['buffedUntil'] as num?)?.toInt(),
    revealUntil: (data['revealUntil'] as num?)?.toInt(),
    trackedTargetUserId: data['trackedTargetUserId'] as String?,
    dungeonEntered:
        dungeonEntered ?? (!isAlive ? current.dungeonEntered : false),
    nextReviveChance:
        isAlive ? null : (nextReviveChance ?? current.nextReviveChance),
    nextReviveAt: isAlive ? null : (nextReviveAt ?? current.nextReviveAt),
    reviveReady: isAlive ? false : (reviveReady ?? current.reviveReady),
    skillUsedAt: hasSkillUsedAt ? skillUsedAt : current.skillUsedAt,
  );
}

int cooldownMsForSkill(String skill) => switch (skill) {
      'shield' => 600000,
      'blockade' => 600000,
      'reveal' => 300000,
      'execution' => 600000,
      _ => 0,
    };
