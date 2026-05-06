import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notification_catalog.dart';

// 발화된 알림을 표현. game screen 이 stream 을 listen 해서 토스트로 표시.
class FwNotifyEvent {
  const FwNotifyEvent({
    required this.kind,
    required this.message,
    required this.toastKind,
  });

  final FwNotifyKind kind;
  final String message;
  final String toastKind;
}

typedef FwSoundPlayer = Future<void> Function(String assetPath);
typedef FwHapticTrigger = void Function(FwNotifyHaptic level);

// 정책:
// - 같은 kind 가 preset.dedupeMs 안에 또 발생 → 무시
// - heavy 햅틱은 heavyHapticBudget 안에 1회 — 직전이 heavy 였으면 medium 으로 강등
// - 사운드 자산이 없거나 재생 실패 → catch 후 silent (텍스트/햅틱은 정상 발동)
// - 동시 사운드는 같은 AudioPlayer 인스턴스라 직전 재생 stop 후 새로 재생
class FwNotificationService {
  FwNotificationService({
    FwSoundPlayer? playSound,
    FwHapticTrigger? triggerHaptic,
    Duration heavyHapticBudget = const Duration(seconds: 1),
  })  : _playSound = playSound ?? _defaultPlaySound,
        _triggerHapticImpl = triggerHaptic ?? _defaultTriggerHaptic,
        _heavyHapticBudget = heavyHapticBudget;

  final FwSoundPlayer _playSound;
  final FwHapticTrigger _triggerHapticImpl;
  final Duration _heavyHapticBudget;
  final Map<FwNotifyKind, DateTime> _lastFiredAt = {};
  DateTime? _lastHeavyHapticAt;
  final StreamController<FwNotifyEvent> _events =
      StreamController<FwNotifyEvent>.broadcast();

  Stream<FwNotifyEvent> get events => _events.stream;

  Future<void> notify(
    FwNotifyKind kind, {
    Map<String, dynamic> params = const {},
    DateTime? now,
  }) async {
    final preset = kFwNotifyCatalog[kind];
    if (preset == null) return;

    final t = now ?? DateTime.now();
    final last = _lastFiredAt[kind];
    if (last != null &&
        t.difference(last).inMilliseconds < preset.dedupeMs) {
      return; // dedupe — 같은 kind 너무 자주 발생
    }
    _lastFiredAt[kind] = t;

    // 텍스트 emit (UI 가 토스트로 표시)
    final message = preset.text(params);
    if (!_events.isClosed) {
      _events.add(FwNotifyEvent(
        kind: kind,
        message: message,
        toastKind: preset.toastKind,
      ));
    }

    // 햅틱 (heavy budget 검사)
    final hapticToFire = _resolveHaptic(preset.haptic, t);
    _triggerHapticImpl(hapticToFire);
    if (hapticToFire == FwNotifyHaptic.heavy) {
      _lastHeavyHapticAt = t;
    }

    // 사운드 (silent 폴백)
    if (preset.soundAsset != null) {
      try {
        await _playSound(preset.soundAsset!);
      } catch (_) {
        // 자산 누락 / codec 오류 등 — 텍스트/햅틱은 이미 발동했으므로 무시.
      }
    }
  }

  FwNotifyHaptic _resolveHaptic(FwNotifyHaptic requested, DateTime now) {
    if (requested != FwNotifyHaptic.heavy) return requested;
    final last = _lastHeavyHapticAt;
    if (last == null) return requested;
    if (now.difference(last) < _heavyHapticBudget) {
      return FwNotifyHaptic.medium; // 강등
    }
    return requested;
  }

  Future<void> dispose() async {
    await _events.close();
  }
}

// 기본 사운드 재생: 단일 AudioPlayer 인스턴스 + lazy init.
AudioPlayer? _defaultPlayer;
Future<void> _defaultPlaySound(String assetPath) async {
  final player = _defaultPlayer ??= AudioPlayer(playerId: 'fw-notify');
  await player.stop();
  await player.play(AssetSource(assetPath));
}

void _defaultTriggerHaptic(FwNotifyHaptic level) {
  switch (level) {
    case FwNotifyHaptic.none:
      return;
    case FwNotifyHaptic.light:
      HapticFeedback.lightImpact();
      return;
    case FwNotifyHaptic.medium:
      HapticFeedback.mediumImpact();
      return;
    case FwNotifyHaptic.heavy:
      HapticFeedback.heavyImpact();
      return;
  }
}

// Riverpod provider — 앱 단일 인스턴스. game screen 이 watch/listen.
final fwNotificationServiceProvider = Provider<FwNotificationService>((ref) {
  final service = FwNotificationService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
