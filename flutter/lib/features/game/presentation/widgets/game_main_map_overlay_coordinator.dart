import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../../data/game_models.dart';
import '../../../map/presentation/map_session_models.dart';

/// NaverMap 위에 올라가는 게임 오버레이(플레이 영역 폴리곤, 유저 마커,
/// 미션 코인/동물 마커)의 수명주기를 한곳에서 관리한다.
///
/// - 유저 마커는 id 단위로 `setPosition`으로 이동시켜 깜빡임을 줄인다.
/// - 폴리곤/미션 마커는 재동기화 시 전체 삭제 후 재생성(idempotent).
/// - 비동기 경계마다 [isAlive]와 [controllerGetter]로 재확인해 dispose
///   이후·지도 재생성 이후의 오버레이 호출을 안전하게 무시한다.
class MapOverlayCoordinator {
  MapOverlayCoordinator({
    required this.controllerGetter,
    required this.isAlive,
    required this.readGameState,
  });

  final NaverMapController? Function() controllerGetter;
  final bool Function() isAlive;
  final AmongUsGameState Function() readGameState;

  final Map<String, NMarker> _liveUserMarkers = {};
  final Set<String> _liveMissionMarkerIds = {};
  int _overlaySyncRequestId = 0;

  static const String _kPlayableAreaOverlayId = 'playable_area_polygon';

  /// 플레이 영역 폴리곤을 맵에 idempotent하게 적용한다.
  /// - 기존에 동일 ID의 폴리곤이 있으면 먼저 제거한 뒤 재생성.
  /// - 좌표가 3개 미만이면 제거만 수행하고 종료.
  Future<void> applyPlayableAreaPolygon({NaverMapController? controller}) async {
    final ctrl = controller ?? controllerGetter();
    if (ctrl == null) return;

    try {
      await ctrl.deleteOverlay(
        const NOverlayInfo(
          type: NOverlayType.polygonOverlay,
          id: _kPlayableAreaOverlayId,
        ),
      );
    } catch (_) {
      // 오버레이 미존재 가능 — 무시
    }
    if (!_stillValid(ctrl)) return;

    final area = readGameState().playableArea;
    if (area == null || area.length < 3) return;

    final coords = area
        .map((p) => NLatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
        .toList();
    if (coords.isNotEmpty && coords.first != coords.last) {
      coords.add(coords.first);
    }

    final polygon = NPolygonOverlay(
      id: _kPlayableAreaOverlayId,
      coords: coords,
      color: Colors.red.withValues(alpha: 0.3),
      outlineColor: Colors.red.withValues(alpha: 0.6),
      outlineWidth: 3,
    );
    if (!_stillValid(ctrl)) return;
    try {
      await ctrl.addOverlay(polygon);
    } catch (e) {
      debugPrint('[MapOverlayCoordinator] addPolygon 실패: $e');
    }
  }

  /// 멤버 위치에 맞춰 NMarker를 동기화한다.
  /// - 이미 있는 마커: setPosition/setCaption으로 제자리 이동.
  /// - 새 멤버: addOverlay.
  /// - 빠진 멤버/탈락/숨김: deleteOverlay.
  Future<void> syncUserMarkers(
    Map<String, MemberState> members,
    String? myUserId,
    Set<String> hiddenMembers,
    Set<String> eliminatedUserIds,
  ) async {
    final ctrl = controllerGetter();
    if (ctrl == null) return;

    final wantedIds = <String>{};

    for (final m in members.values) {
      if (m.lat == 0 && m.lng == 0) continue;
      if (m.userId == myUserId) continue;
      if (hiddenMembers.contains(m.userId)) continue;

      wantedIds.add(m.userId);

      final isEliminated = eliminatedUserIds.contains(m.userId);
      final newPos = NLatLng(m.lat, m.lng);
      final nameCaption = isEliminated ? '[탈락] ${m.nickname}' : m.nickname;
      final pinColor = isEliminated ? Colors.grey : Colors.redAccent;
      final captionColor = isEliminated ? Colors.grey : Colors.black87;
      final snippetText = isEliminated ? '탈락' : _markerSnippet(m);

      final existing = _liveUserMarkers[m.userId];
      if (existing != null) {
        existing.setPosition(newPos);
        existing.setIconTintColor(pinColor);
        existing.setCaption(NOverlayCaption(
          text: nameCaption,
          textSize: 14,
          color: captionColor,
          haloColor: Colors.white,
        ));
        existing.setSubCaption(NOverlayCaption(
          text: snippetText,
          textSize: 12,
          color: isEliminated ? Colors.grey : Colors.grey[700]!,
          haloColor: Colors.white,
        ));
      } else {
        final marker = NMarker(id: m.userId, position: newPos)
          ..setIconTintColor(pinColor)
          ..setCaption(NOverlayCaption(
            text: nameCaption,
            textSize: 14,
            color: captionColor,
            haloColor: Colors.white,
          ))
          ..setSubCaption(NOverlayCaption(
            text: snippetText,
            textSize: 12,
            color: isEliminated ? Colors.grey : Colors.grey[700]!,
            haloColor: Colors.white,
          ));
        _liveUserMarkers[m.userId] = marker;
        try {
          await ctrl.addOverlay(marker);
        } catch (_) {}
        if (!_stillValid(ctrl)) return;
      }
    }

    final toRemove = _liveUserMarkers.keys
        .where((id) => !wantedIds.contains(id))
        .toList(growable: false);
    for (final id in toRemove) {
      _liveUserMarkers.remove(id);
      try {
        await ctrl.deleteOverlay(NOverlayInfo(type: NOverlayType.marker, id: id));
      } catch (_) {}
      if (!_stillValid(ctrl)) return;
    }
  }

  /// 폴리곤 + 미션 오버레이(코인/동물)를 전면 재동기화한다.
  /// 유저 마커(NOverlayType.marker)는 건드리지 않는다.
  Future<void> syncOverlays() async {
    final ctrl = controllerGetter();
    if (ctrl == null) return;
    final syncRequestId = ++_overlaySyncRequestId;

    try {
      await ctrl.clearOverlays(type: NOverlayType.polygonOverlay);
    } catch (_) {}
    if (!_stillValidForSync(ctrl, syncRequestId)) return;

    await applyPlayableAreaPolygon(controller: ctrl);
    if (!_stillValidForSync(ctrl, syncRequestId)) return;

    await _applyMissionOverlays(controller: ctrl);
  }

  Future<void> _applyMissionOverlays({NaverMapController? controller}) async {
    final ctrl = controller ?? controllerGetter();
    if (ctrl == null) return;
    final gameState = readGameState();

    for (final id in _liveMissionMarkerIds) {
      try {
        await ctrl.deleteOverlay(NOverlayInfo(type: NOverlayType.marker, id: id));
      } catch (_) {}
    }
    _liveMissionMarkerIds.clear();
    if (!_stillValid(ctrl)) return;

    for (final entry in gameState.missionCoins.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final coin = entry.value[i];
        if (coin.collected) continue;
        final markerId = 'coin_${entry.key}_$i';
        final marker = NMarker(
          id: markerId,
          position: NLatLng(coin.lat, coin.lng),
        )
          ..setIconTintColor(const Color(0xFFFFC107))
          ..setCaption(const NOverlayCaption(
            text: '코인',
            textSize: 11,
            color: Color(0xFFB8860B),
            haloColor: Colors.white,
          ));
        try {
          await ctrl.addOverlay(marker);
          _liveMissionMarkerIds.add(markerId);
        } catch (_) {}
        if (!_stillValid(ctrl)) return;
      }
    }

    for (final entry in gameState.missionAnimals.entries) {
      final animal = entry.value;
      final markerId = 'animal_${entry.key}';
      final marker = NMarker(
        id: markerId,
        position: NLatLng(animal.lat, animal.lng),
      )
        ..setIconTintColor(const Color(0xFF8B4513))
        ..setCaption(const NOverlayCaption(
          text: '동물',
          textSize: 11,
          color: Color(0xFF5D2F0C),
          haloColor: Colors.white,
        ));
      try {
        await ctrl.addOverlay(marker);
        _liveMissionMarkerIds.add(markerId);
      } catch (_) {}
      if (!_stillValid(ctrl)) return;
    }
  }

  bool _stillValid(NaverMapController capturedCtrl) {
    if (!isAlive()) return false;
    return controllerGetter() == capturedCtrl;
  }

  bool _stillValidForSync(NaverMapController capturedCtrl, int syncId) {
    if (!_stillValid(capturedCtrl)) return false;
    return syncId == _overlaySyncRequestId;
  }

  String _markerSnippet(MemberState m) {
    final parts = <String>[];
    parts.add(m.status == 'moving' ? '이동중' : '정지');
    if (m.battery != null) parts.add('배터리(${m.battery}%)');
    return parts.join(' ');
  }

  /// 화면이 dispose될 때 내부 캐시를 비운다.
  /// 맵 컨트롤러 자체는 게임 화면이 소유하므로 여기서 건드리지 않는다.
  void dispose() {
    _liveUserMarkers.clear();
    _liveMissionMarkerIds.clear();
  }
}
