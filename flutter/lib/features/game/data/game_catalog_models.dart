// lib/features/game/data/game_catalog_models.dart

class GameDescriptor {
  final String gameType;
  final String displayName;
  final Map<String, dynamic> configSchema;
  final Map<String, dynamic> defaultConfig;
  final List<String> capabilities;

  const GameDescriptor({
    required this.gameType,
    required this.displayName,
    required this.configSchema,
    required this.defaultConfig,
    required this.capabilities,
  });

  factory GameDescriptor.fromMap(Map<String, dynamic> m) {
    return GameDescriptor(
      gameType:     m['gameType'] as String,
      displayName:  m['displayName'] as String,
      configSchema: (m['configSchema'] as Map<String, dynamic>?) ?? {},
      defaultConfig: (m['defaultConfig'] as Map<String, dynamic>?) ?? {},
      capabilities: (m['capabilities'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          [],
    );
  }

  bool hasCapability(String cap) => capabilities.contains(cap);
}

class GameCatalog {
  final List<GameDescriptor> games;

  const GameCatalog({required this.games});

  GameDescriptor? findByType(String gameType) {
    try {
      return games.firstWhere((g) => g.gameType == gameType);
    } catch (_) {
      return null;
    }
  }
}
