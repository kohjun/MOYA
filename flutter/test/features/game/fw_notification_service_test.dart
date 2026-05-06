import 'package:flutter_test/flutter_test.dart';
import 'package:location_sharing_app/features/game/presentation/plugins/fantasy_wars/notification_catalog.dart';
import 'package:location_sharing_app/features/game/presentation/plugins/fantasy_wars/services/fw_notification_service.dart';

void main() {
  group('FwNotificationService', () {
    late List<FwNotifyHaptic> hapticCalls;
    late List<String> soundCalls;
    late FwNotificationService service;

    setUp(() {
      hapticCalls = [];
      soundCalls = [];
      service = FwNotificationService(
        playSound: (asset) async {
          soundCalls.add(asset);
        },
        triggerHaptic: hapticCalls.add,
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('notify emits event with text + toastKind from catalog', () async {
      final received = <FwNotifyEvent>[];
      final sub = service.events.listen(received.add);
      addTearDown(sub.cancel);

      await service.notify(
        FwNotifyKind.cpCapturedByUs,
        params: const {'cpName': 'A 거점'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.kind, FwNotifyKind.cpCapturedByUs);
      expect(received.first.message, 'A 거점 확보!');
      expect(received.first.toastKind, 'capture');
    });

    test('dedupes same kind within preset.dedupeMs', () async {
      final received = <FwNotifyEvent>[];
      final sub = service.events.listen(received.add);
      addTearDown(sub.cancel);

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      await service.notify(FwNotifyKind.duelWon, now: t0);
      await service.notify(
        FwNotifyKind.duelWon,
        now: t0.add(const Duration(milliseconds: 1500)),
      );
      await Future<void>.delayed(Duration.zero);

      // 1.5s < dedupeMs(3000) → 두 번째 호출은 무시되어야 한다.
      expect(received, hasLength(1));
      expect(hapticCalls, [FwNotifyHaptic.light]);
      expect(soundCalls, hasLength(1));
    });

    test('different kinds within same window are not deduped', () async {
      final received = <FwNotifyEvent>[];
      final sub = service.events.listen(received.add);
      addTearDown(sub.cancel);

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      await service.notify(FwNotifyKind.duelWon, now: t0);
      await service.notify(
        FwNotifyKind.cpCapturedByUs,
        params: const {'cpName': 'B'},
        now: t0.add(const Duration(milliseconds: 200)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
    });

    test('demotes heavy haptic to medium when within heavy budget', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      // 첫 heavy → heavy 그대로 발동
      await service.notify(FwNotifyKind.eliminatedSelf, now: t0);
      // 600ms 후 다른 heavy 이벤트 → 강등 (1초 budget)
      await service.notify(
        FwNotifyKind.masterEliminatedUs,
        now: t0.add(const Duration(milliseconds: 600)),
      );

      expect(hapticCalls, [FwNotifyHaptic.heavy, FwNotifyHaptic.medium]);
    });

    test('heavy haptic restored after budget elapsed', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      await service.notify(FwNotifyKind.eliminatedSelf, now: t0);
      // 1.5s 후 (budget 1s 초과) heavy 다시 정상 발동
      await service.notify(
        FwNotifyKind.gameLost,
        now: t0.add(const Duration(milliseconds: 1500)),
      );

      expect(hapticCalls, [FwNotifyHaptic.heavy, FwNotifyHaptic.heavy]);
    });

    test('catalog text falls back when params missing', () async {
      final received = <FwNotifyEvent>[];
      final sub = service.events.listen(received.add);
      addTearDown(sub.cancel);

      await service.notify(FwNotifyKind.cpCapturedByUs);
      await Future<void>.delayed(Duration.zero);

      expect(received.first.message, '거점 확보!');
    });

    test('silent sound asset failure does not block emission', () async {
      final received = <FwNotifyEvent>[];
      final flakyService = FwNotificationService(
        playSound: (_) => Future.error(Exception('asset missing')),
        triggerHaptic: hapticCalls.add,
      );
      addTearDown(flakyService.dispose);
      final sub = flakyService.events.listen(received.add);
      addTearDown(sub.cancel);

      await flakyService.notify(FwNotifyKind.duelWon);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(hapticCalls, [FwNotifyHaptic.light]);
    });
  });

  group('Catalog completeness', () {
    test('all FwNotifyKind values have a preset', () {
      for (final kind in FwNotifyKind.values) {
        expect(
          kFwNotifyCatalog[kind],
          isNotNull,
          reason: '$kind 의 preset 이 누락',
        );
      }
    });
  });
}
