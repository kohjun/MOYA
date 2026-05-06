import 'package:flutter/foundation.dart';

const Object _fwSentinel = Object();

@immutable
class FwGeoPoint {
  const FwGeoPoint({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;

  factory FwGeoPoint.fromMap(Map<String, dynamic> map) => FwGeoPoint(
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
      );
}

@immutable
class FwSpawnZone {
  const FwSpawnZone({
    required this.teamId,
    required this.polygonPoints,
    this.displayName,
    this.colorHex,
  });

  final String teamId;
  final String? displayName;
  final String? colorHex;
  final List<FwGeoPoint> polygonPoints;

  factory FwSpawnZone.fromMap(Map<String, dynamic> map) => FwSpawnZone(
        teamId: map['teamId'] as String? ?? '',
        displayName: map['displayName'] as String?,
        colorHex: map['color'] as String?,
        polygonPoints: ((map['polygonPoints'] as List?) ?? const [])
            .whereType<Map>()
            .map(
                (value) => FwGeoPoint.fromMap(Map<String, dynamic>.from(value)))
            .toList(),
      );
}

@immutable
class FwDuelResult {
  const FwDuelResult({
    required this.winnerId,
    required this.loserId,
    required this.reason,
    this.shieldAbsorbed = false,
    this.executionTriggered = false,
    this.warriorHpResult,
  });

  final String? winnerId;
  final String? loserId;
  final String reason;
  final bool shieldAbsorbed;
  final bool executionTriggered;
  final int? warriorHpResult;

  bool get isDraw => winnerId == null || winnerId!.isEmpty;

  factory FwDuelResult.fromMap(Map<String, dynamic> map) {
    final verdict = (map['verdict'] as Map?)?.cast<String, dynamic>() ?? map;
    final effects =
        (verdict['effects'] as Map?)?.cast<String, dynamic>() ?? const {};
    final winner = verdict['winner'] as String?;
    final loser = verdict['loser'] as String?;

    return FwDuelResult(
      winnerId: (winner == null || winner.isEmpty) ? null : winner,
      loserId: (loser == null || loser.isEmpty) ? null : loser,
      reason: verdict['reason'] as String? ?? 'minigame',
      shieldAbsorbed: effects['shieldAbsorbed'] as bool? ?? false,
      executionTriggered: effects['executionTriggered'] as bool? ?? false,
      warriorHpResult: (effects['warriorHp'] as num?)?.toInt(),
    );
  }

  static FwDuelResult invalidated() => const FwDuelResult(
        winnerId: null,
        loserId: null,
        reason: 'invalidated',
      );
}

@immutable
class FwArtifactState {
  const FwArtifactState({
    required this.id,
    this.heldBy,
  });

  final String id;
  final String? heldBy;

  factory FwArtifactState.fromMap(Map<String, dynamic> map) => FwArtifactState(
        id: map['id'] as String? ?? 'artifact_main',
        heldBy: map['heldBy'] as String?,
      );
}

@immutable
class FwDungeonState {
  const FwDungeonState({
    required this.id,
    required this.displayName,
    this.status = 'open',
    this.artifact = const FwArtifactState(id: 'artifact_main'),
  });

  final String id;
  final String displayName;
  final String status;
  final FwArtifactState artifact;

  factory FwDungeonState.fromMap(Map<String, dynamic> map) => FwDungeonState(
        id: map['id'] as String? ?? 'dungeon_main',
        displayName:
            map['displayName'] as String? ?? map['id'] as String? ?? 'Dungeon',
        status: map['status'] as String? ?? 'open',
        artifact: FwArtifactState.fromMap(
          (map['artifact'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );
}

@immutable
class FwControlPoint {
  const FwControlPoint({
    required this.id,
    required this.displayName,
    this.capturedBy,
    this.capturingGuild,
    this.captureProgress = 0,
    this.captureStartedAt,
    this.captureDurationSec,
    this.readyCount = 0,
    this.requiredCount = 0,
    this.blockadedBy,
    this.blockadeExpiresAt,
    this.lat,
    this.lng,
  });

  final String id;
  final String displayName;
  final String? capturedBy;
  final String? capturingGuild;
  final int captureProgress;
  final int? captureStartedAt;
  // 점령에 필요한 총 시간 (초). server.fw:capture_started.durationSec 에서 받는다.
  // 클라 ticker 가 (now - captureStartedAt) / (captureDurationSec * 1000) 비율로
  // 부드러운 progress 를 계산한다. null 이면 30s 폴백.
  final int? captureDurationSec;
  final int readyCount;
  final int requiredCount;
  final String? blockadedBy;
  final int? blockadeExpiresAt;
  final double? lat;
  final double? lng;

  bool get isBlockaded {
    if (blockadedBy == null) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return blockadeExpiresAt == null || blockadeExpiresAt! > now;
  }

  bool get isPreparing => readyCount > 0 && capturingGuild != null;

  factory FwControlPoint.fromMap(Map<String, dynamic> map) {
    final location =
        (map['location'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FwControlPoint(
      id: map['id'] as String,
      displayName: map['displayName'] as String? ?? map['id'] as String,
      capturedBy: map['capturedBy'] as String?,
      capturingGuild: map['capturingGuild'] as String?,
      captureProgress: (map['captureProgress'] as num?)?.toInt() ?? 0,
      captureStartedAt: (map['captureStartedAt'] as num?)?.toInt(),
      captureDurationSec: (map['captureDurationSec'] as num?)?.toInt(),
      readyCount: (map['readyCount'] as num?)?.toInt() ?? 0,
      requiredCount: (map['requiredCount'] as num?)?.toInt() ?? 0,
      blockadedBy: map['blockadedBy'] as String?,
      blockadeExpiresAt: (map['blockadeExpiresAt'] as num?)?.toInt(),
      lat: (location['lat'] as num?)?.toDouble(),
      lng: (location['lng'] as num?)?.toDouble(),
    );
  }

  FwControlPoint copyWith({
    Object? capturedBy = _fwSentinel,
    Object? capturingGuild = _fwSentinel,
    int? captureProgress,
    Object? captureStartedAt = _fwSentinel,
    Object? captureDurationSec = _fwSentinel,
    int? readyCount,
    int? requiredCount,
    Object? blockadedBy = _fwSentinel,
    Object? blockadeExpiresAt = _fwSentinel,
  }) {
    return FwControlPoint(
      id: id,
      displayName: displayName,
      capturedBy:
          capturedBy == _fwSentinel ? this.capturedBy : capturedBy as String?,
      capturingGuild: capturingGuild == _fwSentinel
          ? this.capturingGuild
          : capturingGuild as String?,
      captureProgress: captureProgress ?? this.captureProgress,
      captureStartedAt: captureStartedAt == _fwSentinel
          ? this.captureStartedAt
          : captureStartedAt as int?,
      captureDurationSec: captureDurationSec == _fwSentinel
          ? this.captureDurationSec
          : captureDurationSec as int?,
      readyCount: readyCount ?? this.readyCount,
      requiredCount: requiredCount ?? this.requiredCount,
      blockadedBy: blockadedBy == _fwSentinel
          ? this.blockadedBy
          : blockadedBy as String?,
      blockadeExpiresAt: blockadeExpiresAt == _fwSentinel
          ? this.blockadeExpiresAt
          : blockadeExpiresAt as int?,
      lat: lat,
      lng: lng,
    );
  }
}

@immutable
class FwGuildInfo {
  const FwGuildInfo({
    required this.guildId,
    required this.displayName,
    this.score = 0,
    this.memberIds = const [],
    this.guildMasterId,
  });

  final String guildId;
  final String displayName;
  final int score;
  final List<String> memberIds;
  final String? guildMasterId;

  factory FwGuildInfo.fromMap(Map<String, dynamic> map) => FwGuildInfo(
        guildId: map['guildId'] as String,
        displayName: map['displayName'] as String? ?? map['guildId'] as String,
        score: (map['score'] as num?)?.toInt() ?? 0,
        memberIds: (map['memberIds'] as List?)?.whereType<String>().toList() ??
            const [],
        guildMasterId: map['guildMasterId'] as String?,
      );
}

@immutable
class FwMyState {
  const FwMyState({
    this.guildId,
    this.job,
    this.isGuildMaster = false,
    this.isAlive = true,
    this.hp = 100,
    this.remainingLives = 1,
    this.shieldCount = 0,
    this.captureZone,
    this.inDuel = false,
    this.duelExpiresAt,
    this.executionArmedUntil,
    this.buffedUntil,
    this.revealUntil,
    this.trackedTargetUserId,
    this.dungeonEntered = false,
    this.nextReviveChance,
    this.nextReviveAt,
    this.reviveReady = false,
    this.skillUsedAt = const {},
  });

  final String? guildId;
  final String? job;
  final bool isGuildMaster;
  final bool isAlive;
  final int hp;
  final int remainingLives;
  final int shieldCount;
  final String? captureZone;
  final bool inDuel;
  final int? duelExpiresAt;
  final int? executionArmedUntil;
  final int? buffedUntil;
  final int? revealUntil;
  final String? trackedTargetUserId;
  final bool dungeonEntered;
  final double? nextReviveChance;
  final int? nextReviveAt;
  final bool reviveReady;
  final Map<String, int> skillUsedAt;

  bool get isExecutionReady =>
      executionArmedUntil != null &&
      executionArmedUntil! > DateTime.now().millisecondsSinceEpoch;

  bool get isRevealActive =>
      revealUntil != null &&
      revealUntil! > DateTime.now().millisecondsSinceEpoch;

  bool get isBuffActive =>
      buffedUntil != null &&
      buffedUntil! > DateTime.now().millisecondsSinceEpoch;

  FwMyState copyWith({
    Object? guildId = _fwSentinel,
    Object? job = _fwSentinel,
    bool? isGuildMaster,
    bool? isAlive,
    int? hp,
    int? remainingLives,
    int? shieldCount,
    Object? captureZone = _fwSentinel,
    bool? inDuel,
    Object? duelExpiresAt = _fwSentinel,
    Object? executionArmedUntil = _fwSentinel,
    Object? buffedUntil = _fwSentinel,
    Object? revealUntil = _fwSentinel,
    Object? trackedTargetUserId = _fwSentinel,
    bool? dungeonEntered,
    Object? nextReviveChance = _fwSentinel,
    Object? nextReviveAt = _fwSentinel,
    bool? reviveReady,
    Map<String, int>? skillUsedAt,
  }) {
    return FwMyState(
      guildId: guildId == _fwSentinel ? this.guildId : guildId as String?,
      job: job == _fwSentinel ? this.job : job as String?,
      isGuildMaster: isGuildMaster ?? this.isGuildMaster,
      isAlive: isAlive ?? this.isAlive,
      hp: hp ?? this.hp,
      remainingLives: remainingLives ?? this.remainingLives,
      shieldCount: shieldCount ?? this.shieldCount,
      captureZone: captureZone == _fwSentinel
          ? this.captureZone
          : captureZone as String?,
      inDuel: inDuel ?? this.inDuel,
      duelExpiresAt: duelExpiresAt == _fwSentinel
          ? this.duelExpiresAt
          : duelExpiresAt as int?,
      executionArmedUntil: executionArmedUntil == _fwSentinel
          ? this.executionArmedUntil
          : executionArmedUntil as int?,
      buffedUntil:
          buffedUntil == _fwSentinel ? this.buffedUntil : buffedUntil as int?,
      revealUntil:
          revealUntil == _fwSentinel ? this.revealUntil : revealUntil as int?,
      trackedTargetUserId: trackedTargetUserId == _fwSentinel
          ? this.trackedTargetUserId
          : trackedTargetUserId as String?,
      dungeonEntered: dungeonEntered ?? this.dungeonEntered,
      nextReviveChance: nextReviveChance == _fwSentinel
          ? this.nextReviveChance
          : nextReviveChance as double?,
      nextReviveAt: nextReviveAt == _fwSentinel
          ? this.nextReviveAt
          : nextReviveAt as int?,
      reviveReady: reviveReady ?? this.reviveReady,
      skillUsedAt: skillUsedAt ?? this.skillUsedAt,
    );
  }
}

@immutable
class FwDuelState {
  const FwDuelState({
    this.duelId,
    this.opponentId,
    this.phase = 'idle',
    this.minigameType,
    this.minigameParams,
    this.duelResult,
    this.submitted = false,
  });

  final String? duelId;
  final String? opponentId;
  final String phase;
  final String? minigameType;
  final Map<String, dynamic>? minigameParams;
  final FwDuelResult? duelResult;
  final bool submitted;

  FwDuelState copyWith({
    Object? duelId = _fwSentinel,
    Object? opponentId = _fwSentinel,
    String? phase,
    Object? minigameType = _fwSentinel,
    Object? minigameParams = _fwSentinel,
    Object? duelResult = _fwSentinel,
    bool? submitted,
  }) {
    return FwDuelState(
      duelId: duelId == _fwSentinel ? this.duelId : duelId as String?,
      opponentId:
          opponentId == _fwSentinel ? this.opponentId : opponentId as String?,
      phase: phase ?? this.phase,
      minigameType: minigameType == _fwSentinel
          ? this.minigameType
          : minigameType as String?,
      minigameParams: minigameParams == _fwSentinel
          ? this.minigameParams
          : minigameParams as Map<String, dynamic>?,
      duelResult: duelResult == _fwSentinel
          ? this.duelResult
          : duelResult as FwDuelResult?,
      submitted: submitted ?? this.submitted,
    );
  }
}

@immutable
class FwDuelDebugInfo {
  const FwDuelDebugInfo({
    required this.stage,
    required this.ok,
    required this.recordedAt,
    this.code,
    this.distanceMeters,
    this.duelRangeMeters,
    this.proximitySource,
    this.bleConfirmed,
    this.gpsFallbackUsed,
    this.mutualProximity,
    this.recentProximityReports,
    this.freshestEvidenceAgeMs,
    this.bleEvidenceFreshnessMs,
    this.allowGpsFallbackWithoutBle,
  });

  final String stage;
  final bool ok;
  final String? code;
  final int recordedAt;
  final int? distanceMeters;
  final int? duelRangeMeters;
  final String? proximitySource;
  final bool? bleConfirmed;
  final bool? gpsFallbackUsed;
  final bool? mutualProximity;
  final int? recentProximityReports;
  final int? freshestEvidenceAgeMs;
  final int? bleEvidenceFreshnessMs;
  final bool? allowGpsFallbackWithoutBle;

  factory FwDuelDebugInfo.fromResponse({
    required String stage,
    required Map<String, dynamic> response,
  }) {
    return FwDuelDebugInfo(
      stage: stage,
      ok: response['ok'] == true,
      code: response['ok'] == true ? null : response['error'] as String?,
      recordedAt: DateTime.now().millisecondsSinceEpoch,
      distanceMeters: (response['distanceMeters'] as num?)?.toInt(),
      duelRangeMeters: (response['duelRangeMeters'] as num?)?.toInt(),
      proximitySource: response['proximitySource'] as String?,
      bleConfirmed: response['bleConfirmed'] as bool?,
      gpsFallbackUsed: response['gpsFallbackUsed'] as bool?,
      mutualProximity: response['mutualProximity'] as bool?,
      recentProximityReports:
          (response['recentProximityReports'] as num?)?.toInt(),
      freshestEvidenceAgeMs:
          (response['freshestEvidenceAgeMs'] as num?)?.toInt(),
      bleEvidenceFreshnessMs:
          (response['bleEvidenceFreshnessMs'] as num?)?.toInt(),
      allowGpsFallbackWithoutBle:
          response['allowGpsFallbackWithoutBle'] as bool?,
    );
  }

  factory FwDuelDebugInfo.invalidated(String? reason) {
    return FwDuelDebugInfo(
      stage: 'invalidated',
      ok: false,
      code: reason ?? 'invalid_state',
      recordedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

@immutable
class FwRecentEvent {
  const FwRecentEvent({
    required this.kind,
    required this.message,
    required this.recordedAt,
    this.primaryUserId,
    this.secondaryUserId,
    this.controlPointId,
  });

  final String kind;
  final String message;
  final int recordedAt;
  final String? primaryUserId;
  final String? secondaryUserId;
  final String? controlPointId;

  bool get hasFocusTarget =>
      controlPointId != null ||
      primaryUserId != null ||
      secondaryUserId != null;
}

@immutable
class FantasyWarsGameState {
  const FantasyWarsGameState({
    this.status = 'none',
    this.duelRangeMeters = 20,
    this.bleEvidenceFreshnessMs = 12000,
    this.allowGpsFallbackWithoutBle = false,
    this.guilds = const {},
    this.controlPoints = const [],
    this.playableArea = const [],
    this.spawnZones = const [],
    this.dungeons = const [],
    this.alivePlayerIds = const [],
    this.eliminatedPlayerIds = const [],
    this.winCondition,
    this.myState = const FwMyState(),
    this.duel = const FwDuelState(),
    this.duelDebug,
    this.recentEvents = const [],
  });

  final String status;
  final int duelRangeMeters;
  final int bleEvidenceFreshnessMs;
  final bool allowGpsFallbackWithoutBle;
  final Map<String, FwGuildInfo> guilds;
  final List<FwControlPoint> controlPoints;
  final List<FwGeoPoint> playableArea;
  final List<FwSpawnZone> spawnZones;
  final List<FwDungeonState> dungeons;
  final List<String> alivePlayerIds;
  final List<String> eliminatedPlayerIds;
  final Map<String, dynamic>? winCondition;
  final FwMyState myState;
  final FwDuelState duel;
  final FwDuelDebugInfo? duelDebug;
  final List<FwRecentEvent> recentEvents;

  bool get isStarted => status == 'in_progress';
  bool get isFinished => status == 'finished';

  FantasyWarsGameState copyWith({
    String? status,
    int? duelRangeMeters,
    int? bleEvidenceFreshnessMs,
    bool? allowGpsFallbackWithoutBle,
    Map<String, FwGuildInfo>? guilds,
    List<FwControlPoint>? controlPoints,
    List<FwGeoPoint>? playableArea,
    List<FwSpawnZone>? spawnZones,
    List<FwDungeonState>? dungeons,
    List<String>? alivePlayerIds,
    List<String>? eliminatedPlayerIds,
    Object? winCondition = _fwSentinel,
    FwMyState? myState,
    FwDuelState? duel,
    Object? duelDebug = _fwSentinel,
    List<FwRecentEvent>? recentEvents,
  }) {
    return FantasyWarsGameState(
      status: status ?? this.status,
      duelRangeMeters: duelRangeMeters ?? this.duelRangeMeters,
      bleEvidenceFreshnessMs:
          bleEvidenceFreshnessMs ?? this.bleEvidenceFreshnessMs,
      allowGpsFallbackWithoutBle:
          allowGpsFallbackWithoutBle ?? this.allowGpsFallbackWithoutBle,
      guilds: guilds ?? this.guilds,
      controlPoints: controlPoints ?? this.controlPoints,
      playableArea: playableArea ?? this.playableArea,
      spawnZones: spawnZones ?? this.spawnZones,
      dungeons: dungeons ?? this.dungeons,
      alivePlayerIds: alivePlayerIds ?? this.alivePlayerIds,
      eliminatedPlayerIds: eliminatedPlayerIds ?? this.eliminatedPlayerIds,
      winCondition: winCondition == _fwSentinel
          ? this.winCondition
          : winCondition as Map<String, dynamic>?,
      myState: myState ?? this.myState,
      duel: duel ?? this.duel,
      duelDebug: duelDebug == _fwSentinel
          ? this.duelDebug
          : duelDebug as FwDuelDebugInfo?,
      recentEvents: recentEvents ?? this.recentEvents,
    );
  }
}
