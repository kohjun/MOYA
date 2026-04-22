// lib/features/game/data/game_models.dart

enum MissionType { coinCollect, minigame, captureAnimal }

enum MissionStatus { locked, started, ready, completed }

extension MissionTypeX on MissionType {
  static MissionType fromWire(String? raw) {
    switch (raw) {
      case 'COIN_COLLECT':
      case 'coin_collect':
        return MissionType.coinCollect;
      case 'CAPTURE_ANIMAL':
      case 'capture_animal':
        return MissionType.captureAnimal;
      case 'MINIGAME':
      case 'minigame':
      default:
        return MissionType.minigame;
    }
  }

  static MissionType fromTemplateTitle(String? raw) {
    switch (raw) {
      case '코인 수집':
        return MissionType.coinCollect;
      case '동물 포획':
        return MissionType.captureAnimal;
      case '미니게임':
      default:
        return MissionType.minigame;
    }
  }

  String get wireValue {
    switch (this) {
      case MissionType.coinCollect:
        return 'COIN_COLLECT';
      case MissionType.captureAnimal:
        return 'CAPTURE_ANIMAL';
      case MissionType.minigame:
        return 'MINIGAME';
    }
  }

  String get label {
    switch (this) {
      case MissionType.coinCollect:
        return '코인 수집';
      case MissionType.captureAnimal:
        return '동물 포획';
      case MissionType.minigame:
        return '미니게임';
    }
  }

  bool get isMapBased =>
      this == MissionType.coinCollect || this == MissionType.captureAnimal;
}

class Mission {
  final String id;
  final String title;
  final String description;
  final MissionType type;
  final MissionStatus status;
  final double? targetLatitude;
  final double? targetLongitude;
  final double radius;
  final String minigameId;
  final bool isFake;
  final bool isSabotaged;

  const Mission({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.minigameId,
    this.status = MissionStatus.locked,
    this.targetLatitude,
    this.targetLongitude,
    this.radius = 15.0,
    this.isFake = false,
    this.isSabotaged = false,
  });

  Mission copyWith({
    String? id,
    String? title,
    String? description,
    MissionType? type,
    MissionStatus? status,
    double? targetLatitude,
    double? targetLongitude,
    double? radius,
    String? minigameId,
    bool? isFake,
    bool? isSabotaged,
  }) =>
      Mission(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        type: type ?? this.type,
        status: status ?? this.status,
        targetLatitude: targetLatitude ?? this.targetLatitude,
        targetLongitude: targetLongitude ?? this.targetLongitude,
        radius: radius ?? this.radius,
        minigameId: minigameId ?? this.minigameId,
        isFake: isFake ?? this.isFake,
        isSabotaged: isSabotaged ?? this.isSabotaged,
      );
}

class CoinPoint {
  final double lat;
  final double lng;
  final bool collected;

  const CoinPoint({
    required this.lat,
    required this.lng,
    this.collected = false,
  });

  CoinPoint copyWith({double? lat, double? lng, bool? collected}) => CoinPoint(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        collected: collected ?? this.collected,
      );
}

class AnimalPoint {
  final double lat;
  final double lng;
  final double headingDeg;

  const AnimalPoint({
    required this.lat,
    required this.lng,
    this.headingDeg = 0,
  });

  AnimalPoint copyWith({double? lat, double? lng, double? headingDeg}) =>
      AnimalPoint(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        headingDeg: headingDeg ?? this.headingDeg,
      );
}

class GameRole {
  final String role; // 'crew' | 'impostor'
  final String team;
  final List<String> impostors;

  const GameRole({
    required this.role,
    required this.team,
    required this.impostors,
  });

  factory GameRole.fromMap(Map<String, dynamic> map) => GameRole(
        role: map['role'] as String,
        team: map['team'] as String,
        impostors: List<String>.from(map['impostors'] ?? []),
      );

  bool get isImpostor => role == 'impostor';
}

class GameMission {
  final String id;
  final String title;
  final String description;
  final String zone;
  final String type;
  final String status;
  final bool isFake;
  final String templateTitle;
  final String minigameId;
  final double? lat;
  final double? lng;

  const GameMission({
    required this.id,
    required this.title,
    required this.description,
    required this.zone,
    required this.type,
    required this.status,
    required this.isFake,
    required this.templateTitle,
    required this.minigameId,
    this.lat,
    this.lng,
  });

  factory GameMission.fromMap(Map<String, dynamic> map) {
    final templateTitle = map['templateTitle'] as String? ?? '';
    final title = map['title'] as String? ?? '';
    final description = map['description'] as String? ?? '';

    return GameMission(
      id: map['missionId'] as String? ?? map['id'] as String,
      title: title,
      description: description,
      zone: map['zone'] as String? ?? templateTitle,
      type: (map['type'] as String?)?.trim().isNotEmpty == true
          ? map['type'] as String
          : _inferType(templateTitle, title, description),
      status: map['status'] as String? ??
          ((map['done'] as bool? ?? false) ? 'completed' : 'pending'),
      isFake: map['isFake'] as bool? ?? map['fake'] as bool? ?? false,
      templateTitle: templateTitle,
      minigameId: (map['minigameId'] as String?)?.trim().isNotEmpty == true
          ? map['minigameId'] as String
          : _inferMinigameId(title, description),
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
    );
  }

  GameMission copyWith({
    String? id,
    String? title,
    String? description,
    String? zone,
    String? type,
    String? status,
    bool? isFake,
    String? templateTitle,
    String? minigameId,
    double? lat,
    double? lng,
  }) =>
      GameMission(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        zone: zone ?? this.zone,
        type: type ?? this.type,
        status: status ?? this.status,
        isFake: isFake ?? this.isFake,
        templateTitle: templateTitle ?? this.templateTitle,
        minigameId: minigameId ?? this.minigameId,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );

  bool get isCompleted => status == 'completed';

  bool get hasLocation => lat != null && lng != null;

  static String _inferType(
    String templateTitle,
    String title,
    String description,
  ) {
    if (templateTitle.isNotEmpty) {
      return MissionTypeX.fromTemplateTitle(templateTitle).wireValue;
    }

    final haystack = '$title $description'.toLowerCase();
    if (haystack.contains('코인') || haystack.contains('coin')) {
      return 'COIN_COLLECT';
    }
    if (haystack.contains('동물') || haystack.contains('animal')) {
      return 'CAPTURE_ANIMAL';
    }
    return 'MINIGAME';
  }

  static String _inferMinigameId(String title, String description) {
    final haystack = '$title $description'.toLowerCase();
    if (haystack.contains('전선') || haystack.contains('wire')) {
      return 'wire_fix';
    }
    if (haystack.contains('카드') ||
        haystack.contains('card') ||
        haystack.contains('swipe')) {
      return 'card_swipe';
    }
    return '';
  }
}

class VoteResult {
  final Map<String, int> voteCount;
  final String? ejectedId;
  final bool? wasImpostor;
  final bool isTied;
  final int totalVotes;

  const VoteResult({
    required this.voteCount,
    this.ejectedId,
    this.wasImpostor,
    required this.isTied,
    required this.totalVotes,
  });

  factory VoteResult.fromMap(Map<String, dynamic> map) => VoteResult(
        voteCount: Map<String, int>.from(
          (map['voteCount'] as Map?)
                  ?.map((k, v) => MapEntry(k as String, v as int)) ??
              {},
        ),
        ejectedId: (map['ejected'] as Map?)?['userId'] as String?,
        wasImpostor: map['wasImpostor'] as bool?,
        isTied: map['isTied'] as bool? ?? false,
        totalVotes: map['totalVotes'] as int? ?? 0,
      );
}

enum ChatLogType { aiAnnounce, aiReply, myQuestion, system }

class ChatLog {
  final String id;
  final ChatLogType type;
  final String message;
  final DateTime timestamp;

  const ChatLog({
    required this.id,
    required this.type,
    required this.message,
    required this.timestamp,
  });
}

class AmongUsGameState {
  final bool isStarted;
  final GameRole? myRole;
  final List<GameMission> missions;
  final Map<String, dynamic> missionProgress;
  final List<ChatLog> chatLogs;
  final String meetingPhase;
  final int meetingRemaining;
  final int totalVoted;
  final int totalPlayers;
  final VoteResult? voteResult;
  final String? gameOverWinner;
  final bool isAlive;
  final int preVoteCount;
  final bool shouldNavigateToRole;
  final List<Map<String, double>>? playableArea;
  final List<String> nearbyMissionIds;
  final List<Mission> myMissions;
  final Map<String, List<CoinPoint>> missionCoins;
  final Map<String, AnimalPoint> missionAnimals;
  final double totalTaskProgress;
  final bool shouldNavigateToMeeting;
  final bool isMeetingCoolingDown;
  final bool isOutOfBounds;

  const AmongUsGameState({
    this.isStarted = false,
    this.myRole,
    this.missions = const [],
    this.missionProgress = const {
      'completed': 0,
      'total': 0,
      'percent': 0,
    },
    this.chatLogs = const [],
    this.meetingPhase = 'none',
    this.meetingRemaining = 0,
    this.totalVoted = 0,
    this.totalPlayers = 0,
    this.voteResult,
    this.gameOverWinner,
    this.isAlive = true,
    this.preVoteCount = 0,
    this.shouldNavigateToRole = false,
    this.playableArea,
    this.nearbyMissionIds = const [],
    this.myMissions = const [],
    this.missionCoins = const {},
    this.missionAnimals = const {},
    this.totalTaskProgress = 0.0,
    this.shouldNavigateToMeeting = false,
    this.isMeetingCoolingDown = false,
    this.isOutOfBounds = false,
  });

  AmongUsGameState copyWith({
    bool? isStarted,
    GameRole? myRole,
    List<GameMission>? missions,
    Map<String, dynamic>? missionProgress,
    List<ChatLog>? chatLogs,
    String? meetingPhase,
    int? meetingRemaining,
    int? totalVoted,
    int? totalPlayers,
    VoteResult? voteResult,
    String? gameOverWinner,
    bool? isAlive,
    int? preVoteCount,
    bool? shouldNavigateToRole,
    List<Map<String, double>>? playableArea,
    List<String>? nearbyMissionIds,
    List<Mission>? myMissions,
    Map<String, List<CoinPoint>>? missionCoins,
    Map<String, AnimalPoint>? missionAnimals,
    double? totalTaskProgress,
    bool? shouldNavigateToMeeting,
    bool? isMeetingCoolingDown,
    bool? isOutOfBounds,
  }) =>
      AmongUsGameState(
        isStarted: isStarted ?? this.isStarted,
        myRole: myRole ?? this.myRole,
        missions: missions ?? this.missions,
        missionProgress: missionProgress ?? this.missionProgress,
        chatLogs: chatLogs ?? this.chatLogs,
        meetingPhase: meetingPhase ?? this.meetingPhase,
        meetingRemaining: meetingRemaining ?? this.meetingRemaining,
        totalVoted: totalVoted ?? this.totalVoted,
        totalPlayers: totalPlayers ?? this.totalPlayers,
        voteResult: voteResult ?? this.voteResult,
        gameOverWinner: gameOverWinner ?? this.gameOverWinner,
        isAlive: isAlive ?? this.isAlive,
        preVoteCount: preVoteCount ?? this.preVoteCount,
        shouldNavigateToRole:
            shouldNavigateToRole ?? this.shouldNavigateToRole,
        playableArea: playableArea ?? this.playableArea,
        nearbyMissionIds: nearbyMissionIds ?? this.nearbyMissionIds,
        myMissions: myMissions ?? this.myMissions,
        missionCoins: missionCoins ?? this.missionCoins,
        missionAnimals: missionAnimals ?? this.missionAnimals,
        totalTaskProgress: totalTaskProgress ?? this.totalTaskProgress,
        shouldNavigateToMeeting:
            shouldNavigateToMeeting ?? this.shouldNavigateToMeeting,
        isMeetingCoolingDown:
            isMeetingCoolingDown ?? this.isMeetingCoolingDown,
        isOutOfBounds: isOutOfBounds ?? this.isOutOfBounds,
      );
}
