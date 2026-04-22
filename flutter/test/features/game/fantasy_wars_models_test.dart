import 'package:flutter_test/flutter_test.dart';
import 'package:location_sharing_app/features/game/providers/fantasy_wars_provider.dart';

void main() {
  group('Fantasy Wars models', () {
    test('FwDuelResult parses verdict effects and draw state', () {
      final draw = FwDuelResult.fromMap({
        'verdict': {
          'winner': null,
          'loser': null,
          'reason': 'both_timed_out',
        },
      });
      expect(draw.isDraw, isTrue);
      expect(draw.reason, 'both_timed_out');

      final resolved = FwDuelResult.fromMap({
        'verdict': {
          'winner': 'user-a',
          'loser': 'user-b',
          'reason': 'minigame',
          'effects': {
            'shieldAbsorbed': true,
            'executionTriggered': false,
            'warriorHp': 1,
          },
        },
      });
      expect(resolved.isDraw, isFalse);
      expect(resolved.winnerId, 'user-a');
      expect(resolved.loserId, 'user-b');
      expect(resolved.shieldAbsorbed, isTrue);
      expect(resolved.warriorHpResult, 1);
    });

    test('FwControlPoint parses capture preparation and blockade state', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final controlPoint = FwControlPoint.fromMap({
        'id': 'cp-1',
        'displayName': 'Ancient Gate',
        'capturedBy': 'guild_alpha',
        'capturingGuild': 'guild_beta',
        'captureProgress': 42,
        'captureStartedAt': now - 1000,
        'readyCount': 2,
        'requiredCount': 2,
        'blockadedBy': 'guild_gamma',
        'blockadeExpiresAt': now + 5000,
        'location': {
          'lat': 37.123,
          'lng': 127.456,
        },
      });

      expect(controlPoint.id, 'cp-1');
      expect(controlPoint.displayName, 'Ancient Gate');
      expect(controlPoint.capturingGuild, 'guild_beta');
      expect(controlPoint.captureProgress, 42);
      expect(controlPoint.readyCount, 2);
      expect(controlPoint.requiredCount, 2);
      expect(controlPoint.isPreparing, isTrue);
      expect(controlPoint.isBlockaded, isTrue);
      expect(controlPoint.lat, 37.123);
      expect(controlPoint.lng, 127.456);
    });

    test('FwDungeonState parses nested artifact state', () {
      final dungeon = FwDungeonState.fromMap({
        'id': 'dungeon_1',
        'displayName': 'Forgotten Vault',
        'status': 'contested',
        'artifact': {
          'id': 'artifact_main',
          'heldBy': 'user-99',
        },
      });

      expect(dungeon.id, 'dungeon_1');
      expect(dungeon.displayName, 'Forgotten Vault');
      expect(dungeon.status, 'contested');
      expect(dungeon.artifact.id, 'artifact_main');
      expect(dungeon.artifact.heldBy, 'user-99');
    });

    test('FwMyState computed flags reflect active timed effects', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final myState = FwMyState(
        job: 'rogue',
        shieldCount: 1,
        executionArmedUntil: now + 5000,
        buffedUntil: now + 5000,
        revealUntil: now + 5000,
      );

      expect(myState.isExecutionReady, isTrue);
      expect(myState.isBuffActive, isTrue);
      expect(myState.isRevealActive, isTrue);
    });
  });
}
