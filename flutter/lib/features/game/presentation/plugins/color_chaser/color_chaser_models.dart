// Color Chaser — 게임 상태 모델 (Phase 1+2 범위).
// Phase 3 이후 tag/mission/hint 필드를 추가한다.

import 'package:flutter/foundation.dart';

@immutable
class CcColor {
  const CcColor({
    required this.id,
    required this.label,
    required this.hex,
  });

  final String id;
  final String label;
  final String hex;

  factory CcColor.fromMap(Map<String, dynamic> map) => CcColor(
        id: map['id'] as String? ?? '',
        label: map['label'] as String? ?? '',
        hex: map['hex'] as String? ?? '#9CA3AF',
      );
}

@immutable
class CcColorCount {
  const CcColorCount({
    required this.colorId,
    required this.colorLabel,
    required this.colorHex,
    required this.aliveCount,
  });

  final String colorId;
  final String colorLabel;
  final String colorHex;
  final int aliveCount;

  factory CcColorCount.fromMap(Map<String, dynamic> map) => CcColorCount(
        colorId: map['colorId'] as String? ?? '',
        colorLabel: map['colorLabel'] as String? ?? '',
        colorHex: map['colorHex'] as String? ?? '#9CA3AF',
        aliveCount: (map['aliveCount'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class CcGeoPoint {
  const CcGeoPoint({required this.lat, required this.lng});
  final double lat;
  final double lng;

  factory CcGeoPoint.fromMap(Map<String, dynamic> map) => CcGeoPoint(
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
      );
}

@immutable
class CcControlPoint {
  const CcControlPoint({
    required this.id,
    required this.displayName,
    required this.status,
    this.location,
    this.activatedAt,
    this.expiresAt,
    this.claimedBy,
  });

  final String id;
  final String displayName;
  final String status; // 'inactive' | 'active' | 'claimed' | 'expired'
  final CcGeoPoint? location; // inactive 일 땐 null (위치 비공개)
  final int? activatedAt;
  final int? expiresAt;
  final String? claimedBy;

  factory CcControlPoint.fromMap(Map<String, dynamic> map) {
    final locRaw = map['location'];
    return CcControlPoint(
      id: map['id'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      status: map['status'] as String? ?? 'inactive',
      location: locRaw is Map
          ? CcGeoPoint.fromMap(Map<String, dynamic>.from(locRaw))
          : null,
      activatedAt: (map['activatedAt'] as num?)?.toInt(),
      expiresAt: (map['expiresAt'] as num?)?.toInt(),
      claimedBy: map['claimedBy'] as String?,
    );
  }
}

@immutable
class CcActiveMission {
  const CcActiveMission({
    required this.cpId,
    required this.word,
    required this.startedAt,
    required this.expiresAt,
  });

  final String cpId;
  final String word;
  final int startedAt;
  final int expiresAt;

  factory CcActiveMission.fromMap(Map<String, dynamic> map) => CcActiveMission(
        cpId: map['cpId'] as String? ?? '',
        word: map['word'] as String? ?? '',
        startedAt: (map['startedAt'] as num?)?.toInt() ?? 0,
        expiresAt: (map['expiresAt'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class CcAttributeOption {
  const CcAttributeOption({required this.id, required this.label});
  final String id;
  final String label;

  factory CcAttributeOption.fromMap(Map<String, dynamic> map) =>
      CcAttributeOption(
        id: map['id'] as String? ?? '',
        label: map['label'] as String? ?? '',
      );
}

@immutable
class CcAttributeDef {
  const CcAttributeDef({
    required this.key,
    required this.label,
    required this.options,
  });

  final String key;
  final String label;
  final List<CcAttributeOption> options;

  factory CcAttributeDef.fromMap(String key, Map<String, dynamic> map) {
    final raw = (map['options'] as List?) ?? const [];
    return CcAttributeDef(
      key: key,
      label: map['label'] as String? ?? key,
      options: raw
          .whereType<Map>()
          .map((m) => CcAttributeOption.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false),
    );
  }
}

@immutable
class CcHint {
  const CcHint({
    required this.attribute,
    required this.attributeLabel,
    required this.value,
    required this.optionLabel,
    required this.candidateCountAfter,
    required this.revealedAt,
  });

  final String attribute;
  final String attributeLabel;
  final String value;
  final String optionLabel;
  final int candidateCountAfter;
  final int revealedAt;

  factory CcHint.fromMap(Map<String, dynamic> map) => CcHint(
        attribute: map['attribute'] as String? ?? '',
        attributeLabel: map['attributeLabel'] as String? ?? '',
        value: map['value'] as String? ?? '',
        optionLabel: map['optionLabel'] as String? ?? '',
        candidateCountAfter:
            (map['candidateCountAfter'] as num?)?.toInt() ?? 0,
        revealedAt: (map['revealedAt'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class CcCandidate {
  const CcCandidate({required this.userId, required this.nickname});
  final String userId;
  final String nickname;

  factory CcCandidate.fromMap(Map<String, dynamic> map) => CcCandidate(
        userId: map['userId'] as String? ?? '',
        nickname: map['nickname'] as String? ?? '',
      );
}

@immutable
class CcWinCondition {
  const CcWinCondition({
    this.winnerUserId,
    this.winnerNickname,
    this.winnerColorLabel,
    this.winnerColorHex,
    required this.reason,
    this.tagCount,
    this.leaderCount,
  });

  final String? winnerUserId;
  final String? winnerNickname;
  final String? winnerColorLabel;
  final String? winnerColorHex;
  final String reason; // 'last_survivor' | 'time_up' | 'time_up_tied' | 'all_dead'
  final int? tagCount;
  final int? leaderCount;

  factory CcWinCondition.fromMap(Map<String, dynamic> map) => CcWinCondition(
        winnerUserId: map['winner'] as String?,
        winnerNickname: map['winnerNickname'] as String?,
        winnerColorLabel: map['winnerColorLabel'] as String?,
        winnerColorHex: map['winnerColorHex'] as String?,
        reason: map['reason'] as String? ?? 'last_survivor',
        tagCount: (map['tagCount'] as num?)?.toInt(),
        leaderCount: (map['leaderCount'] as num?)?.toInt(),
      );
}

@immutable
class CcScoreEntry {
  const CcScoreEntry({
    required this.userId,
    required this.nickname,
    required this.colorLabel,
    required this.colorHex,
    required this.tagCount,
    required this.isAlive,
    required this.missionsCompleted,
  });

  final String userId;
  final String nickname;
  final String colorLabel;
  final String colorHex;
  final int tagCount;
  final bool isAlive;
  final int missionsCompleted;

  factory CcScoreEntry.fromMap(Map<String, dynamic> map) => CcScoreEntry(
        userId: map['userId'] as String? ?? '',
        nickname: map['nickname'] as String? ?? '',
        colorLabel: map['colorLabel'] as String? ?? '',
        colorHex: map['colorHex'] as String? ?? '#9CA3AF',
        tagCount: (map['tagCount'] as num?)?.toInt() ?? 0,
        isAlive: map['isAlive'] as bool? ?? false,
        missionsCompleted: (map['missionsCompleted'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class CcMyState {
  const CcMyState({
    this.colorId,
    this.colorLabel,
    this.colorHex,
    this.targetColorId,
    this.targetColorLabel,
    this.targetColorHex,
    this.isAlive = true,
    this.missionsCompleted = 0,
    this.activeMission,
    this.bodyProfile = const {},
    this.bodyProfileComplete = false,
    this.unlockedHints = const [],
    this.candidates = const [],
  });

  final String? colorId;
  final String? colorLabel;
  final String? colorHex;
  final String? targetColorId;
  final String? targetColorLabel;
  final String? targetColorHex;
  final bool isAlive;
  final int missionsCompleted;
  final CcActiveMission? activeMission;
  final Map<String, String> bodyProfile;
  final bool bodyProfileComplete;
  final List<CcHint> unlockedHints;
  final List<CcCandidate> candidates;

  bool get hasIdentity => colorId != null && targetColorId != null;
}

@immutable
class CcTagEvent {
  const CcTagEvent({
    required this.success,
    required this.eliminatedUserId,
    required this.eliminatedColorLabel,
    required this.killedBy,
    required this.reason,
    this.wrongTargetId,
    required this.occurredAt,
  });

  final bool success;
  final String eliminatedUserId;
  final String? eliminatedColorLabel;
  final String? killedBy;
  final String reason; // 'tagged' | 'wrong_tag'
  final String? wrongTargetId;
  final int occurredAt;

  factory CcTagEvent.fromMap(Map<String, dynamic> map) => CcTagEvent(
        success: map['success'] as bool? ?? false,
        eliminatedUserId: map['eliminatedUserId'] as String? ?? '',
        eliminatedColorLabel: map['eliminatedColorLabel'] as String?,
        killedBy: map['killedBy'] as String?,
        reason: map['reason'] as String? ?? 'tagged',
        wrongTargetId: map['wrongTargetId'] as String?,
        occurredAt: (map['occurredAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
}

@immutable
class ColorChaserGameState {
  const ColorChaserGameState({
    this.status = 'none',
    this.startedAt,
    this.finishedAt,
    this.aliveCount = 0,
    this.alivePlayerIds = const [],
    this.eliminatedPlayerIds = const [],
    this.palette = const [],
    this.colorCounts = const [],
    this.myState = const CcMyState(),
    this.winCondition,
    this.scoreboard = const [],
    this.timeLimitSec = 1200,
    this.recentTags = const [],
    this.controlPoints = const [],
    this.playableArea = const [],
    this.activeControlPointId,
    this.nextActivationAt,
    this.controlPointRadiusMeters = 15,
    this.tagRangeMeters = 5,
    this.missionTimeoutSec = 15,
    this.cpActivationIntervalSec = 90,
    this.cpLifespanSec = 60,
    this.bodyAttributes = const [],
    this.bodyProfileSubmittedUserIds = const [],
  });

  final String status; // 'none' | 'in_progress' | 'finished'
  final int? startedAt;
  final int? finishedAt;
  final int aliveCount;
  final List<String> alivePlayerIds;
  final List<String> eliminatedPlayerIds;
  final List<CcColor> palette;
  final List<CcColorCount> colorCounts;
  final CcMyState myState;
  final CcWinCondition? winCondition;
  final List<CcScoreEntry> scoreboard;
  final int timeLimitSec;
  final List<CcTagEvent> recentTags;
  final List<CcControlPoint> controlPoints;
  final List<CcGeoPoint> playableArea;
  final String? activeControlPointId;
  final int? nextActivationAt;
  final double controlPointRadiusMeters;
  final double tagRangeMeters;
  final int missionTimeoutSec;
  final int cpActivationIntervalSec;
  final int cpLifespanSec;
  final List<CcAttributeDef> bodyAttributes;
  final List<String> bodyProfileSubmittedUserIds;

  ColorChaserGameState copyWith({
    String? status,
    int? startedAt,
    int? finishedAt,
    int? aliveCount,
    List<String>? alivePlayerIds,
    List<String>? eliminatedPlayerIds,
    List<CcColor>? palette,
    List<CcColorCount>? colorCounts,
    CcMyState? myState,
    CcWinCondition? winCondition,
    List<CcScoreEntry>? scoreboard,
    int? timeLimitSec,
    List<CcTagEvent>? recentTags,
    List<CcControlPoint>? controlPoints,
    List<CcGeoPoint>? playableArea,
    String? activeControlPointId,
    int? nextActivationAt,
    double? controlPointRadiusMeters,
    double? tagRangeMeters,
    int? missionTimeoutSec,
    int? cpActivationIntervalSec,
    int? cpLifespanSec,
    List<CcAttributeDef>? bodyAttributes,
    List<String>? bodyProfileSubmittedUserIds,
  }) {
    return ColorChaserGameState(
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      aliveCount: aliveCount ?? this.aliveCount,
      alivePlayerIds: alivePlayerIds ?? this.alivePlayerIds,
      eliminatedPlayerIds: eliminatedPlayerIds ?? this.eliminatedPlayerIds,
      palette: palette ?? this.palette,
      colorCounts: colorCounts ?? this.colorCounts,
      myState: myState ?? this.myState,
      winCondition: winCondition ?? this.winCondition,
      scoreboard: scoreboard ?? this.scoreboard,
      timeLimitSec: timeLimitSec ?? this.timeLimitSec,
      recentTags: recentTags ?? this.recentTags,
      controlPoints: controlPoints ?? this.controlPoints,
      playableArea: playableArea ?? this.playableArea,
      activeControlPointId: activeControlPointId ?? this.activeControlPointId,
      nextActivationAt: nextActivationAt ?? this.nextActivationAt,
      controlPointRadiusMeters:
          controlPointRadiusMeters ?? this.controlPointRadiusMeters,
      tagRangeMeters: tagRangeMeters ?? this.tagRangeMeters,
      missionTimeoutSec: missionTimeoutSec ?? this.missionTimeoutSec,
      cpActivationIntervalSec:
          cpActivationIntervalSec ?? this.cpActivationIntervalSec,
      cpLifespanSec: cpLifespanSec ?? this.cpLifespanSec,
      bodyAttributes: bodyAttributes ?? this.bodyAttributes,
      bodyProfileSubmittedUserIds:
          bodyProfileSubmittedUserIds ?? this.bodyProfileSubmittedUserIds,
    );
  }
}
