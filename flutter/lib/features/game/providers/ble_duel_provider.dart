import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/fantasy_wars_ble_presence_service.dart';

enum BleDuelPhase { idle, starting, running, error, unsupported }

class BleDuelState {
  const BleDuelState({
    this.phase = BleDuelPhase.idle,
    this.message,
  });

  final BleDuelPhase phase;
  final String? message;

  bool get isActive => phase == BleDuelPhase.running;
  bool get canRetry =>
      phase == BleDuelPhase.error || phase == BleDuelPhase.unsupported;

  BleDuelState copyWith({BleDuelPhase? phase, String? message}) =>
      BleDuelState(phase: phase ?? this.phase, message: message ?? this.message);
}

class BleDuelNotifier extends StateNotifier<BleDuelState> {
  BleDuelNotifier() : super(const BleDuelState());

  final _ble = FantasyWarsBlePresenceService();
  StreamSubscription<BlePresenceStatus>? _statusSub;
  String? _sessionId;
  String? _userId;
  List<String> _memberIds = const [];

  /// 결투 요청이 수락되었을 때만 호출한다.
  Future<void> startForDuel({
    required String sessionId,
    required String userId,
    required List<String> memberUserIds,
  }) async {
    _sessionId = sessionId;
    _userId = userId;
    _memberIds = memberUserIds;

    state = const BleDuelState(phase: BleDuelPhase.starting);
    _subscribeStatus();

    await _ble.start(
      sessionId: sessionId,
      userId: userId,
      memberUserIds: memberUserIds,
    );
  }

  Future<void> retry() async {
    final s = _sessionId;
    final u = _userId;
    if (s == null || u == null) return;
    await startForDuel(sessionId: s, userId: u, memberUserIds: _memberIds);
  }

  Future<void> stopAfterDuel() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _ble.stop();
    state = const BleDuelState(phase: BleDuelPhase.idle);
  }

  void _subscribeStatus() {
    _statusSub?.cancel();
    _statusSub = _ble.statuses.listen((s) {
      switch (s.state) {
        case BlePresenceLifecycleState.running:
          state = const BleDuelState(phase: BleDuelPhase.running);
        case BlePresenceLifecycleState.unsupported:
          state = BleDuelState(
              phase: BleDuelPhase.unsupported, message: s.message);
        case BlePresenceLifecycleState.error:
        case BlePresenceLifecycleState.bluetoothUnavailable:
        case BlePresenceLifecycleState.permissionDenied:
          state = BleDuelState(phase: BleDuelPhase.error, message: s.message);
        case BlePresenceLifecycleState.starting:
        case BlePresenceLifecycleState.requestingPermission:
          state = const BleDuelState(phase: BleDuelPhase.starting);
        case BlePresenceLifecycleState.idle:
          break;
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}

final bleDuelProvider =
    StateNotifierProvider.autoDispose<BleDuelNotifier, BleDuelState>(
  (_) => BleDuelNotifier(),
);

/// 결투 중 상대방 근접 감지 스트림
final bleDuelSightingsProvider = StreamProvider.autoDispose<BlePresenceSighting>(
  (_) => FantasyWarsBlePresenceService().sightings,
);
