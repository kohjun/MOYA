// lib/features/game/data/game_catalog_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'game_catalog_models.dart';

class GameCatalogRepository {
  final ApiClient _api = ApiClient();

  Future<GameCatalog> listGames() async {
    final res = await _api.get('/games');
    final list = res.data['games'] as List<dynamic>? ?? [];
    return GameCatalog(
      games: list
          .whereType<Map<String, dynamic>>()
          .map(GameDescriptor.fromMap)
          .toList(),
    );
  }

  Future<GameDescriptor> getGame(String gameType) async {
    final res = await _api.get('/games/$gameType');
    return GameDescriptor.fromMap(
      res.data['game'] as Map<String, dynamic>,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final gameCatalogRepositoryProvider =
    Provider((ref) => GameCatalogRepository());

final gameCatalogProvider = FutureProvider<GameCatalog>((ref) {
  return ref.read(gameCatalogRepositoryProvider).listGames();
});
