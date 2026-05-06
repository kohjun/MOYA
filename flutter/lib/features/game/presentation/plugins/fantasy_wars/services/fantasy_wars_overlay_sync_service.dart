import 'dart:async';

import '../../../../../map/presentation/map_session_models.dart';
import '../../../../providers/fantasy_wars_provider.dart';

class FantasyWarsOverlaySyncService {
  Object? _lastFwStateIdentity;
  Object? _lastMapStateIdentity;
  String? _lastOverlaySignature;
  Timer? _overlaySyncTimer;
  int _overlaySyncRequestId = 0;

  bool isCurrent(int syncId) => syncId == _overlaySyncRequestId;

  void dispose() {
    _overlaySyncTimer?.cancel();
    _overlaySyncTimer = null;
    _overlaySyncRequestId++;
  }

  /// Bump the request id so any in-flight `syncOverlays` callback sees
  /// `isCurrent` as false and aborts. Pending debounce timer is also cancelled.
  /// Call this whenever the map PlatformView is recreated so that overlay set
  /// calls bound to the dead method channel (`flutter_naver_map_overlay#N`)
  /// are not dispatched.
  void invalidate() {
    _lastFwStateIdentity = null;
    _lastMapStateIdentity = null;
    _lastOverlaySignature = null;
    _overlaySyncTimer?.cancel();
    _overlaySyncTimer = null;
    _overlaySyncRequestId++;
  }

  void schedule({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
    required String? selectedMemberId,
    required String? selectedControlPointId,
    required Future<void> Function(int syncId) syncOverlays,
    void Function(Object error, StackTrace stackTrace)? onError,
    Duration debounce = const Duration(milliseconds: 600),
  }) {
    if (identical(_lastFwStateIdentity, fwState) &&
        identical(_lastMapStateIdentity, mapState)) {
      return;
    }
    _lastFwStateIdentity = fwState;
    _lastMapStateIdentity = mapState;

    final signature = _overlaySignature(
      fwState,
      mapState,
      myId,
      selectedMemberId,
      selectedControlPointId,
    );
    if (_lastOverlaySignature == signature) {
      return;
    }

    _lastOverlaySignature = signature;
    final syncId = ++_overlaySyncRequestId;
    _overlaySyncTimer?.cancel();
    _overlaySyncTimer = Timer(debounce, () {
      unawaited(() async {
        try {
          await syncOverlays(syncId);
        } catch (error, stackTrace) {
          onError?.call(error, stackTrace);
        }
      }());
    });
  }

  bool _shouldRenderPlayerMarker(
    String userId,
    FantasyWarsGameState fwState,
    String? myId,
  ) {
    if (userId == myId) {
      return false;
    }
    return fwState.myState.isRevealActive &&
        fwState.myState.trackedTargetUserId == userId;
  }

  String _overlaySignature(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
    String? selectedMemberId,
    String? selectedControlPointId,
  ) {
    final myPos = mapState.myPosition;
    // 사용자가 ~10m 이상 이동했을 때만 거리 라벨이 갱신되도록 양자화.
    final myLatBucket = myPos == null ? '_' : (myPos.latitude * 1e4).round();
    final myLngBucket = myPos == null ? '_' : (myPos.longitude * 1e4).round();
    final buffer = StringBuffer()
      ..write(myId ?? '')
      ..write('|')
      ..write(selectedMemberId ?? '')
      ..write('|')
      ..write(selectedControlPointId ?? '')
      ..write('|')
      ..write(fwState.myState.guildId ?? '')
      ..write('|')
      ..write(fwState.myState.trackedTargetUserId ?? '')
      ..write('|')
      ..write(fwState.myState.isRevealActive)
      ..write('|')
      ..write(mapState.eliminatedUserIds.length)
      ..write('|me:')
      ..write(myLatBucket)
      ..write(',')
      ..write(myLngBucket)
      ..write('|');

    for (final point in fwState.playableArea) {
      buffer
        ..write(point.lat)
        ..write(',')
        ..write(point.lng)
        ..write('|');
    }

    for (final spawnZone in fwState.spawnZones) {
      buffer
        ..write(spawnZone.teamId)
        ..write(':')
        ..write(spawnZone.colorHex ?? '')
        ..write(':');
      for (final point in spawnZone.polygonPoints) {
        buffer
          ..write(point.lat)
          ..write(',')
          ..write(point.lng)
          ..write(';');
      }
      buffer.write('|');
    }

    for (final controlPoint in fwState.controlPoints) {
      buffer
        ..write(controlPoint.id)
        ..write(':')
        ..write(controlPoint.capturedBy ?? '')
        ..write(':')
        ..write(controlPoint.capturingGuild ?? '')
        ..write(':')
        ..write(controlPoint.readyCount)
        ..write('/')
        ..write(controlPoint.requiredCount)
        ..write(':')
        ..write(controlPoint.blockadedBy ?? '')
        ..write(':')
        ..write(controlPoint.blockadeExpiresAt ?? 0)
        ..write(':')
        ..write(controlPoint.lat ?? 0)
        ..write(',')
        ..write(controlPoint.lng ?? 0)
        ..write('|');
    }

    final memberIds = mapState.members.keys.toList()..sort();
    for (final userId in memberIds) {
      if (!_shouldRenderPlayerMarker(userId, fwState, myId)) {
        continue;
      }
      final member = mapState.members[userId]!;
      buffer
        ..write(userId)
        ..write(':')
        ..write(member.lat)
        ..write(',')
        ..write(member.lng)
        ..write(':')
        ..write(mapState.eliminatedUserIds.contains(userId))
        ..write('|');
    }
    return buffer.toString();
  }
}
