import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/services/app_initialization_service.dart';
import '../../../../../core/services/socket_service.dart';
import '../../../../auth/data/auth_repository.dart';
import '../../../../home/data/session_repository.dart';
import '../../../../map/data/map_session_provider.dart';
import '../../../../map/presentation/map_session_models.dart';
import '../../../providers/fantasy_wars_provider.dart';
import 'duel/fw_duel_screen.dart' show FwDuelScreen;
import 'fantasy_wars_hud.dart';

class FantasyWarsGameScreen extends ConsumerStatefulWidget {
  const FantasyWarsGameScreen({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  ConsumerState<FantasyWarsGameScreen> createState() => _FantasyWarsGameScreenState();
}

class _FantasyWarsGameScreenState extends ConsumerState<FantasyWarsGameScreen> {
  NaverMapController? _mapController;
  bool _mapSdkReady = false;

  final Map<String, NCircleOverlay> _cpOverlays = {};
  final Map<String, NPolygonOverlay> _spawnZoneOverlays = {};
  final Map<String, NMarker> _playerMarkers = {};
  NPolygonOverlay? _playableAreaOverlay;

  Timer? _overlaySyncTimer;
  int _overlaySyncRequestId = 0;
  String? _lastOverlaySignature;
  String? _lastControlPointSignature;
  String? _lastBattlefieldSignature;
  bool _lastWasKicked = false;
  String? _lastDuelPhase;
  String? _selectedMemberId;
  String? _selectedControlPointId;

  @override
  void initState() {
    super.initState();
    unawaited(_initMap());
  }

  @override
  void dispose() {
    _overlaySyncTimer?.cancel();
    _cpOverlays.clear();
    _spawnZoneOverlays.clear();
    _playerMarkers.clear();
    _playableAreaOverlay = null;
    super.dispose();
  }

  Future<void> _initMap() async {
    await AppInitializationService().ensureNaverMapInitialized();
    if (!mounted) {
      return;
    }
    setState(() => _mapSdkReady = true);
  }

  Future<void> _syncMapOverlays(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
    int syncId,
  ) async {
    final controller = _mapController;
    if (controller == null || !mounted || syncId != _overlaySyncRequestId) {
      return;
    }

    await _syncBattlefieldOverlays(
      controller: controller,
      fwState: fwState,
      syncId: syncId,
    );
    if (!mounted || syncId != _overlaySyncRequestId) {
      return;
    }

    await _syncControlPointOverlays(
      controller: controller,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
      syncId: syncId,
    );
    if (!mounted || syncId != _overlaySyncRequestId) {
      return;
    }
    await _syncPlayerMarkers(
      controller: controller,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
      syncId: syncId,
    );
  }

  Future<void> _syncBattlefieldOverlays({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required int syncId,
  }) async {
    final signature = _battlefieldSignature(fwState);
    if (_lastBattlefieldSignature == signature) {
      return;
    }

    if (_playableAreaOverlay != null) {
      try {
        await controller.deleteOverlay(
          const NOverlayInfo(type: NOverlayType.polygonOverlay, id: 'fw_playable_area'),
        );
      } catch (_) {}
      _playableAreaOverlay = null;
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    if (fwState.playableArea.length >= 3) {
      final polygon = NPolygonOverlay(
        id: 'fw_playable_area',
        coords: fwState.playableArea.map((point) => NLatLng(point.lat, point.lng)).toList(),
        color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
        outlineColor: const Color(0xFF38BDF8).withValues(alpha: 0.8),
        outlineWidth: 3,
      );
      _playableAreaOverlay = polygon;
      await controller.addOverlay(polygon);
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    final activeSpawnIds = <String>{};
    for (final spawnZone in fwState.spawnZones) {
      if (spawnZone.polygonPoints.length < 3) {
        continue;
      }

      final overlayId = 'spawn_${spawnZone.teamId}';
      activeSpawnIds.add(overlayId);
      final existing = _spawnZoneOverlays.remove(overlayId);
      if (existing != null) {
        try {
          await controller.deleteOverlay(
            NOverlayInfo(type: NOverlayType.polygonOverlay, id: overlayId),
          );
        } catch (_) {}
      }

      final color = _colorFromHex(spawnZone.colorHex) ?? guildColor(spawnZone.teamId);
      final overlay = NPolygonOverlay(
        id: overlayId,
        coords: spawnZone.polygonPoints
            .map((point) => NLatLng(point.lat, point.lng))
            .toList(),
        color: color.withValues(alpha: 0.14),
        outlineColor: color.withValues(alpha: 0.9),
        outlineWidth: 4,
      );
      _spawnZoneOverlays[overlayId] = overlay;
      await controller.addOverlay(overlay);
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    final staleSpawnIds = _spawnZoneOverlays.keys
        .where((overlayId) => !activeSpawnIds.contains(overlayId))
        .toList(growable: false);
    for (final overlayId in staleSpawnIds) {
      _spawnZoneOverlays.remove(overlayId);
      try {
        await controller.deleteOverlay(
          NOverlayInfo(type: NOverlayType.polygonOverlay, id: overlayId),
        );
      } catch (_) {}
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    _lastBattlefieldSignature = signature;
  }

  Future<void> _syncControlPointOverlays({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
    required int syncId,
  }) async {
    final signature = _controlPointSignature(fwState);
    if (_lastControlPointSignature == signature && _cpOverlays.isNotEmpty) {
      return;
    }

    final nextIds = <String>{};
    for (final controlPoint in fwState.controlPoints) {
      if (controlPoint.lat == null || controlPoint.lng == null) {
        continue;
      }

      nextIds.add(controlPoint.id);
      final existing = _cpOverlays[controlPoint.id];
      if (existing != null) {
        _applyControlPointOverlayState(
          overlay: existing,
          controlPoint: controlPoint,
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        );
        continue;
      }

      final overlay = _buildControlPointOverlay(
        controlPoint: controlPoint,
        fwState: fwState,
        mapState: mapState,
        myId: myId,
      );
      _cpOverlays[controlPoint.id] = overlay;
      await controller.addOverlay(overlay);
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    final staleIds = _cpOverlays.keys
        .where((controlPointId) => !nextIds.contains(controlPointId))
        .toList(growable: false);
    for (final controlPointId in staleIds) {
      _cpOverlays.remove(controlPointId);
      try {
        await controller.deleteOverlay(
          NOverlayInfo(type: NOverlayType.circleOverlay, id: 'cp_$controlPointId'),
        );
      } catch (_) {}
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    _lastControlPointSignature = signature;
  }

  NCircleOverlay _buildControlPointOverlay({
    required FwControlPoint controlPoint,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final overlay = NCircleOverlay(
      id: 'cp_${controlPoint.id}',
      center: NLatLng(controlPoint.lat!, controlPoint.lng!),
      radius: 30,
      color: _cpFillColor(controlPoint).withValues(alpha: 0.25),
      outlineColor: _cpFillColor(controlPoint).withValues(alpha: 0.84),
      outlineWidth: 3,
    );
    _applyControlPointOverlayState(
      overlay: overlay,
      controlPoint: controlPoint,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
    );
    return overlay;
  }

  void _applyControlPointOverlayState({
    required NCircleOverlay overlay,
    required FwControlPoint controlPoint,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final isSelected = controlPoint.id == _selectedControlPointId;
    final fillColor = _cpFillColor(controlPoint);
    final outlineColor = isSelected
        ? Colors.amberAccent
        : controlPoint.isBlockaded
            ? Colors.redAccent
            : fillColor.withValues(alpha: 0.84);

    overlay
      ..setCenter(NLatLng(controlPoint.lat!, controlPoint.lng!))
      ..setRadius(isSelected ? 38 : 30)
      ..setColor(fillColor.withValues(alpha: isSelected ? 0.34 : 0.25))
      ..setOutlineColor(outlineColor)
      ..setOutlineWidth(isSelected ? 5 : 3)
      ..setGlobalZIndex(isSelected ? 250 : 120)
      ..setOnTapListener((_) {
        unawaited(_handleControlPointTapped(
          controlPointId: controlPoint.id,
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        ));
      });
  }

  String _controlPointSignature(FantasyWarsGameState fwState) {
    final buffer = StringBuffer();
    buffer.write(_selectedControlPointId ?? '');
    buffer.write('|');
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
    return buffer.toString();
  }

  NMarker? _buildPlayerMarker({
    required String userId,
    required MemberState member,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
  }) {
    if ((member.lat == 0 && member.lng == 0) || mapState.eliminatedUserIds.contains(userId)) {
      return null;
    }

    final marker = NMarker(
      id: 'player_$userId',
      position: NLatLng(member.lat, member.lng),
    );
    _applyPlayerMarkerState(
      marker: marker,
      userId: userId,
      member: member,
      mapState: mapState,
      fwState: fwState,
      myId: myId,
    );
    return marker;
  }

  void _applyPlayerMarkerState({
    required NMarker marker,
    required String userId,
    required MemberState member,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
  }) {
    final memberGuildId = _guildIdForUser(fwState.guilds, userId);
    final isMe = userId == myId;
    final isAlly = memberGuildId == fwState.myState.guildId;
    final isTrackedTarget =
        fwState.myState.isRevealActive && fwState.myState.trackedTargetUserId == userId;
    final isSelected = userId == _selectedMemberId;

    final markerColor = isSelected
        ? Colors.amberAccent
        : isTrackedTarget
            ? Colors.amberAccent
            : isMe
                ? Colors.white
                : isAlly
                    ? guildColor(memberGuildId)
                    : Colors.red.shade300;
    final captionText = isMe
        ? '나'
        : isTrackedTarget
            ? '추적 ${member.nickname}'
            : member.nickname;

    marker.setIconTintColor(markerColor);
    marker.setCaption(
      NOverlayCaption(
        text: captionText,
        color: markerColor,
        textSize: 11,
        haloColor: Colors.black,
      ),
    );
    marker.setGlobalZIndex(isSelected ? 300 : isTrackedTarget ? 240 : 160);
    marker.setOnTapListener((_) {
      unawaited(_handleMemberTapped(
        userId: userId,
        fwState: fwState,
        mapState: mapState,
        myId: myId,
      ));
    });
  }

  Future<void> _syncPlayerMarkers({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
    required int syncId,
  }) async {
    final nextIds = <String>{};

    for (final entry in mapState.members.entries) {
      final userId = entry.key;
      final member = entry.value;
      if ((member.lat == 0 && member.lng == 0) || mapState.eliminatedUserIds.contains(userId)) {
        continue;
      }

      nextIds.add(userId);
      final existing = _playerMarkers[userId];
      if (existing != null) {
        existing.setPosition(NLatLng(member.lat, member.lng));
        _applyPlayerMarkerState(
          marker: existing,
          userId: userId,
          member: member,
          mapState: mapState,
          fwState: fwState,
          myId: myId,
        );
        continue;
      }

      final marker = _buildPlayerMarker(
        userId: userId,
        member: member,
        mapState: mapState,
        fwState: fwState,
        myId: myId,
      );
      if (marker == null) {
        continue;
      }

      _playerMarkers[userId] = marker;
      await controller.addOverlay(marker);
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }

    final staleIds = _playerMarkers.keys
        .where((userId) => !nextIds.contains(userId))
        .toList(growable: false);
    for (final userId in staleIds) {
      _playerMarkers.remove(userId);
      try {
        await controller.deleteOverlay(
          NOverlayInfo(type: NOverlayType.marker, id: 'player_$userId'),
        );
      } catch (_) {}
      if (!mounted || syncId != _overlaySyncRequestId) {
        return;
      }
    }
  }

  String _overlaySignature(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final buffer = StringBuffer()
      ..write(myId ?? '')
      ..write('|')
      ..write(_selectedMemberId ?? '')
      ..write('|')
      ..write(_selectedControlPointId ?? '')
      ..write('|')
      ..write(fwState.myState.guildId ?? '')
      ..write('|')
      ..write(fwState.myState.trackedTargetUserId ?? '')
      ..write('|')
      ..write(fwState.myState.isRevealActive)
      ..write('|')
      ..write(mapState.eliminatedUserIds.length)
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

  void _scheduleOverlaySync(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final signature = _overlaySignature(fwState, mapState, myId);
    if (_lastOverlaySignature == signature) {
      return;
    }

    _lastOverlaySignature = signature;
    final syncId = ++_overlaySyncRequestId;
    _overlaySyncTimer?.cancel();
    _overlaySyncTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) {
        return;
      }
      unawaited(_syncMapOverlays(fwState, mapState, myId, syncId));
    });
  }

  void _handleStateSideEffects(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    if (!_lastWasKicked && mapState.wasKicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoutes.home);
        }
      });
    }
    _lastWasKicked = mapState.wasKicked;

    if (_lastDuelPhase != 'invalidated' && fwState.duel.phase == 'invalidated') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('대결이 무효 처리되었습니다.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      });
    }
    _lastDuelPhase = fwState.duel.phase;

    _scheduleOverlaySync(fwState, mapState, myId);
  }

  Color _cpFillColor(FwControlPoint controlPoint) {
    if (controlPoint.capturedBy != null) {
      return guildColor(controlPoint.capturedBy);
    }
    if (controlPoint.capturingGuild != null) {
      return guildColor(controlPoint.capturingGuild).withValues(alpha: 0.5);
    }
    return Colors.white;
  }

  String _battlefieldSignature(FantasyWarsGameState fwState) {
    final buffer = StringBuffer();
    for (final point in fwState.playableArea) {
      buffer
        ..write(point.lat)
        ..write(',')
        ..write(point.lng)
        ..write('|');
    }
    buffer.write('#');
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
    return buffer.toString();
  }

  Color? _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) {
      return null;
    }

    final normalized = hex.replaceFirst('#', '');
    final argb = normalized.length == 6 ? 'FF$normalized' : normalized;
    final value = int.tryParse(argb, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(value);
  }

  Future<void> _confirmLeave() async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('게임 나가기'),
            content: const Text('정말로 게임을 나가시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('나가기'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLeave || !mounted) {
      return;
    }

    await ref.read(sessionRepositoryProvider).leaveSession(widget.sessionId).catchError((_) {});
    SocketService().leaveSession(sessionId: widget.sessionId);
    if (!mounted) {
      return;
    }
    context.go(AppRoutes.home);
  }

  String? _guildIdForUser(Map<String, FwGuildInfo> guilds, String userId) {
    for (final guild in guilds.values) {
      if (guild.memberIds.contains(userId)) {
        return guild.guildId;
      }
    }
    return null;
  }

  ({double lat, double lng})? _myPosition(MapSessionState mapState, String? myId) {
    if (mapState.myPosition != null) {
      return (
        lat: mapState.myPosition!.latitude,
        lng: mapState.myPosition!.longitude,
      );
    }

    if (myId == null) {
      return null;
    }

    final me = mapState.members[myId];
    if (me == null || (me.lat == 0 && me.lng == 0)) {
      return null;
    }

    return (lat: me.lat, lng: me.lng);
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  FwControlPoint? _nearestControlPoint(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final controlPoints = _candidateControlPoints(fwState, mapState, myId);
    return controlPoints.isEmpty ? null : controlPoints.first;
  }

  double? _distanceToControlPoint(
    FwControlPoint controlPoint,
    MapSessionState mapState,
    String? myId,
  ) {
    final myPosition = _myPosition(mapState, myId);
    if (myPosition == null || controlPoint.lat == null || controlPoint.lng == null) {
      return null;
    }
    return _distanceMeters(
      myPosition.lat,
      myPosition.lng,
      controlPoint.lat!,
      controlPoint.lng!,
    );
  }

  double? _distanceToMember(
    String userId,
    MapSessionState mapState,
    String? myId,
  ) {
    final cachedDistance = mapState.memberDistances[userId];
    if (cachedDistance != null) {
      return cachedDistance;
    }

    final myPosition = _myPosition(mapState, myId);
    final member = mapState.members[userId];
    if (myPosition == null || member == null || (member.lat == 0 && member.lng == 0)) {
      return null;
    }

    return _distanceMeters(
      myPosition.lat,
      myPosition.lng,
      member.lat,
      member.lng,
    );
  }

  List<String> _candidateMemberIds({
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
  }) {
    final ids = <String>{
      ...mapState.members.keys,
      ...mapState.memberDistances.keys,
    };
    if (includeSelf && myId != null) {
      ids.add(myId);
    }

    final candidates = ids.where((userId) {
      if (userId == myId && !includeSelf) {
        return false;
      }
      if (fwState.eliminatedPlayerIds.contains(userId)) {
        return false;
      }

      final memberGuildId = _guildIdForUser(fwState.guilds, userId);
      if (enemy) {
        return memberGuildId != null && memberGuildId != fwState.myState.guildId;
      }
      if (userId == myId) {
        return true;
      }
      return memberGuildId != null && memberGuildId == fwState.myState.guildId;
    }).toList();

    candidates.sort((a, b) {
      final aDistance = _distanceToMember(a, mapState, myId) ?? double.infinity;
      final bDistance = _distanceToMember(b, mapState, myId) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    return candidates;
  }

  List<FwControlPoint> _candidateControlPoints(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final controlPoints = fwState.controlPoints
        .where((controlPoint) => controlPoint.lat != null && controlPoint.lng != null)
        .toList();
    controlPoints.sort((a, b) {
      final aDistance = _distanceToControlPoint(a, mapState, myId) ?? double.infinity;
      final bDistance = _distanceToControlPoint(b, mapState, myId) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    return controlPoints;
  }

  Future<T?> _showTargetSheet<T>({
    required String title,
    required List<_TargetChoice<T>> choices,
  }) async {
    if (choices.isEmpty || !mounted) {
      return null;
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${choices.length}개',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: choices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final choice = choices[index];
                      final accent = choice.accentColor ?? Colors.white70;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(choice.value),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: choice.isHighlighted
                                  ? accent.withValues(alpha: 0.14)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: choice.isHighlighted
                                    ? accent.withValues(alpha: 0.8)
                                    : Colors.white12,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(choice.icon, color: accent),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                choice.label,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            if (choice.badge != null)
                                              _ChoiceBadge(
                                                label: choice.badge!,
                                                color: accent,
                                              ),
                                          ],
                                        ),
                                        if (choice.subtitle != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            choice.subtitle!,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        if (choice.helper != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            choice.helper!,
                                            style: TextStyle(
                                              color: accent.withValues(alpha: 0.92),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (choice.trailing != null) ...[
                                    const SizedBox(width: 12),
                                    Text(
                                      choice.trailing!,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _pickMemberTarget({
    required String title,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
  }) {
    final userIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: enemy,
      includeSelf: includeSelf,
    );

    final choices = userIds.map((userId) {
      final nickname = userId == myId ? '나' : _memberLabel(mapState.members, userId);
      final distance = _distanceToMember(userId, mapState, myId);
      final guildId = _guildIdForUser(fwState.guilds, userId);
      final guildName = guildId == null ? null : fwState.guilds[guildId]?.displayName ?? guildId;
      final isNearest = userIds.isNotEmpty && identical(userIds.first, userId);
      return _TargetChoice(
        value: userId,
        label: nickname,
        subtitle: guildName ?? (userId == myId ? '현재 플레이어' : '길드 정보 없음'),
        trailing: distance != null && distance.isFinite ? '${distance.round()}m' : '거리 불명',
        badge: userId == myId ? '자신' : enemy ? '적' : '아군',
        helper: isNearest ? '현재 위치 기준 가장 가까운 대상' : null,
        accentColor: userId == myId
            ? Colors.white
            : enemy
                ? Colors.redAccent
                : guildColor(guildId),
        icon: userId == myId
            ? Icons.person_pin_circle_outlined
            : enemy
                ? Icons.gps_fixed_rounded
                : Icons.shield_outlined,
        isHighlighted: isNearest,
      );
    }).toList();
    return _showTargetSheet(title: title, choices: choices);
  }

  Future<String?> _pickControlPointTarget({
    required String title,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final controlPoints = _candidateControlPoints(fwState, mapState, myId);
    final choices = controlPoints.map((controlPoint) {
      final distance = _distanceToControlPoint(controlPoint, mapState, myId);
      final isNearest = controlPoints.isNotEmpty && controlPoints.first.id == controlPoint.id;
      final ownerGuild = controlPoint.capturedBy == null
          ? null
          : fwState.guilds[controlPoint.capturedBy!]?.displayName ?? controlPoint.capturedBy;
      final isOwnedByMe = controlPoint.capturedBy == fwState.myState.guildId;
      final badge = controlPoint.isBlockaded
          ? '봉쇄'
          : ownerGuild == null
              ? '중립'
              : isOwnedByMe
                  ? '아군'
                  : '적군';
      final helper = controlPoint.requiredCount > 0
          ? '점령 준비 ${controlPoint.readyCount}/${controlPoint.requiredCount}'
          : controlPoint.capturingGuild != null
              ? '점령 진행 중'
              : null;
      return _TargetChoice(
        value: controlPoint.id,
        label: controlPoint.displayName,
        subtitle: ownerGuild == null ? '미점령 거점' : '점령 길드 · $ownerGuild',
        trailing: distance != null && distance.isFinite ? '${distance.round()}m' : '거리 불명',
        badge: badge,
        helper: helper ?? (isNearest ? '현재 위치 기준 가장 가까운 거점' : null),
        accentColor: controlPoint.isBlockaded ? Colors.redAccent : _cpFillColor(controlPoint),
        icon: Icons.place_rounded,
        isHighlighted: isNearest,
      );
    }).toList();
    return _showTargetSheet(title: title, choices: choices);
  }

  String _memberLabel(Map<String, MemberState> members, String? userId) {
    if (userId == null) {
      return '알 수 없음';
    }
    return members[userId]?.nickname ?? userId;
  }

  FwControlPoint? _controlPointById(FantasyWarsGameState fwState, String? controlPointId) {
    if (controlPointId == null) {
      return null;
    }
    for (final controlPoint in fwState.controlPoints) {
      if (controlPoint.id == controlPointId) {
        return controlPoint;
      }
    }
    return null;
  }

  String? _preferredSelectedMember({
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
  }) {
    final selectedUserId = _selectedMemberId;
    if (selectedUserId == null) {
      return null;
    }
    if (selectedUserId == myId && !includeSelf) {
      return null;
    }
    if (fwState.eliminatedPlayerIds.contains(selectedUserId)) {
      return null;
    }

    final memberGuildId = _guildIdForUser(fwState.guilds, selectedUserId);
    if (enemy) {
      return memberGuildId != null && memberGuildId != fwState.myState.guildId
          ? selectedUserId
          : null;
    }
    if (selectedUserId == myId) {
      return selectedUserId;
    }
    return memberGuildId != null && memberGuildId == fwState.myState.guildId
        ? selectedUserId
        : null;
  }

  void _setSelection({
    String? memberId,
    String? controlPointId,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedMemberId = memberId;
      _selectedControlPointId = controlPointId;
    });
  }

  Future<void> _handleMemberTapped({
    required String userId,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) async {
    _setSelection(memberId: userId, controlPointId: null);

    final member = mapState.members[userId];
    final guildId = _guildIdForUser(fwState.guilds, userId);
    final guildLabel = guildId == null ? '길드 정보 없음' : fwState.guilds[guildId]?.displayName ?? guildId;
    final distance = _distanceToMember(userId, mapState, myId);
    final isEnemy = guildId != null && guildId != fwState.myState.guildId;
    final isSelf = userId == myId;
    final isAlly = !isSelf && guildId != null && guildId == fwState.myState.guildId;
    final canAct = fwState.myState.isAlive && !fwState.myState.inDuel;
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);

    final actions = <_QuickAction>[];
    if (canAct && isEnemy && fwState.duel.phase == 'idle') {
      actions.add(
        _QuickAction(
          label: '대결 요청',
          icon: Icons.sports_martial_arts_rounded,
          color: const Color(0xFF991B1B),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.challengeDuel(userId));
          },
        ),
      );
    }
    if (canAct && fwState.myState.job == 'ranger' && isEnemy) {
      actions.add(
        _QuickAction(
          label: '추적 사용',
          icon: Icons.gps_fixed_rounded,
          color: const Color(0xFF0F766E),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(targetUserId: userId));
          },
        ),
      );
    }
    if (canAct && fwState.myState.job == 'priest' && (isAlly || isSelf)) {
      actions.add(
        _QuickAction(
          label: '보호막 부여',
          icon: Icons.shield_outlined,
          color: const Color(0xFF4338CA),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(targetUserId: userId));
          },
        ),
      );
    }

    await _showQuickActionSheet(
      title: member?.nickname ?? userId,
      subtitle: [
        guildLabel,
        if (distance != null && distance.isFinite) '${distance.round()}m',
        if (isSelf) '나',
      ].join(' · '),
      accentColor: isEnemy
          ? Colors.redAccent
          : isSelf
              ? Colors.white
              : guildColor(guildId),
      lines: [
        if (member != null) '상태 · ${member.status}',
        if (fwState.eliminatedPlayerIds.contains(userId)) '전투 불가 · 탈락 상태',
        if (isEnemy && !canAct) '현재 상태에서는 상호작용할 수 없습니다.',
      ],
      actions: actions,
    );
  }

  Future<void> _handleControlPointTapped({
    required String controlPointId,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) async {
    final controlPoint = _controlPointById(fwState, controlPointId);
    if (controlPoint == null) {
      return;
    }

    _setSelection(memberId: null, controlPointId: controlPointId);

    final distance = _distanceToControlPoint(controlPoint, mapState, myId);
    final canCapture = fwState.myState.isAlive &&
        !fwState.myState.inDuel &&
        (distance ?? double.infinity) <= 40 &&
        controlPoint.capturedBy != fwState.myState.guildId;
    final isCancelling = fwState.myState.captureZone == controlPoint.id &&
        controlPoint.capturingGuild == fwState.myState.guildId;
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);

    final actions = <_QuickAction>[];
    if (canCapture) {
      actions.add(
        _QuickAction(
          label: isCancelling ? '점령 취소' : '점령 시작',
          icon: isCancelling ? Icons.pause_circle_outline : Icons.flag_outlined,
          color: const Color(0xFF0F766E),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() {
              return isCancelling
                  ? notifier.cancelCapture(controlPoint.id)
                  : notifier.startCapture(controlPoint.id);
            });
          },
        ),
      );
    }
    if (fwState.myState.isAlive && !fwState.myState.inDuel && fwState.myState.job == 'mage') {
      actions.add(
        _QuickAction(
          label: '봉쇄 마법',
          icon: Icons.block_flipped,
          color: const Color(0xFF7C3AED),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(controlPointId: controlPoint.id));
          },
        ),
      );
    }

    final ownerGuild = controlPoint.capturedBy == null
        ? '미점령'
        : fwState.guilds[controlPoint.capturedBy!]?.displayName ?? controlPoint.capturedBy!;

    await _showQuickActionSheet(
      title: controlPoint.displayName,
      subtitle: [
        '점령 길드 · $ownerGuild',
        if (distance != null && distance.isFinite) '${distance.round()}m',
      ].join(' · '),
      accentColor: controlPoint.isBlockaded ? Colors.redAccent : _cpFillColor(controlPoint),
      lines: [
        if (controlPoint.isBlockaded) '현재 봉쇄 중입니다.',
        if (controlPoint.requiredCount > 0)
          '점령 준비 ${controlPoint.readyCount}/${controlPoint.requiredCount}',
        if (controlPoint.capturingGuild != null && controlPoint.requiredCount == 0)
          '점령 진행 중인 거점입니다.',
      ],
      actions: actions,
    );
  }

  Future<void> _showQuickActionSheet({
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<String> lines,
    required List<_QuickAction> actions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final line in lines) ...[
                    Text(
                      line,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final action in actions)
                        FilledButton.tonalIcon(
                          onPressed: () => unawaited(action.onTap()),
                          style: FilledButton.styleFrom(
                            backgroundColor: action.color.withValues(alpha: 0.18),
                            foregroundColor: action.color,
                          ),
                          icon: Icon(action.icon, size: 18),
                          label: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runAck(Future<Map<String, dynamic>> Function() action) async {
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      if (result['ok'] != true) {
        _showError(_errorLabel(result['error'] as String?));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  Future<void> _handleCaptureAction(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final nearest =
        _controlPointById(fwState, _selectedControlPointId) ?? _nearestControlPoint(fwState, mapState, myId);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    if (nearest == null) {
      _showError('근처 거점을 찾지 못했습니다.');
      return;
    }

    final isCancelling = fwState.myState.captureZone == nearest.id &&
        nearest.capturingGuild == fwState.myState.guildId;

    await _runAck(() {
      return isCancelling ? notifier.cancelCapture(nearest.id) : notifier.startCapture(nearest.id);
    });
  }

  Future<void> _handleSkillAction(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    final job = fwState.myState.job;

    String? targetUserId;
    String? controlPointId;

    switch (job) {
      case 'priest':
        targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: false,
          includeSelf: true,
        );
        if (targetUserId != null) {
          break;
        }
        targetUserId = await _pickMemberTarget(
          title: '보호막을 줄 아군 선택',
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          enemy: false,
          includeSelf: true,
        );
        if (targetUserId == null) {
          return;
        }
        break;
      case 'mage':
        controlPointId = _selectedControlPointId;
        if (controlPointId != null) {
          break;
        }
        controlPointId = await _pickControlPointTarget(
          title: '봉쇄할 거점 선택',
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        );
        if (controlPointId == null) {
          return;
        }
        break;
      case 'ranger':
        targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: true,
        );
        if (targetUserId != null) {
          break;
        }
        targetUserId = await _pickMemberTarget(
          title: '추적할 적 선택',
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          enemy: true,
        );
        if (targetUserId == null) {
          return;
        }
        break;
      case 'rogue':
        break;
      default:
        _showError('사용 가능한 스킬이 없습니다.');
        return;
    }

    await _runAck(() {
      return notifier.useSkill(
        targetUserId: targetUserId,
        controlPointId: controlPointId,
      );
    });
  }

  Future<void> _handleDuelAction(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: true,
        ) ??
        await _pickMemberTarget(
      title: '대결할 적 선택',
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
    );
    if (targetUserId == null) {
      return;
    }

    await _runAck(() {
      return ref.read(fantasyWarsProvider(widget.sessionId).notifier).challengeDuel(targetUserId);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  String _errorLabel(String? code) => switch (code) {
        'TARGET_OUT_OF_RANGE' => '대결 가능한 거리 밖입니다.',
        'LOCATION_UNAVAILABLE' => '위치 정보를 아직 받지 못했습니다.',
        'LOCATION_STALE' => '위치 정보가 오래되었습니다.',
        'NOT_IN_CAPTURE_ZONE' => '거점 반경 안에서만 점령을 시작할 수 있습니다.',
        'NOT_ENOUGH_TEAMMATES_IN_ZONE' => '같은 길드원이 2명 이상 필요합니다.',
        'ENEMY_IN_ZONE' => '적이 거점 안에 있어 점령을 시작할 수 없습니다.',
        'BLOCKADED' => '현재 봉쇄된 거점입니다.',
        'TARGET_IN_DUEL' => '대결 중인 대상에게는 사용할 수 없습니다.',
        'TARGET_NOT_ENEMY' => '적 대상이 필요합니다.',
        'TARGET_NOT_ALLY' => '아군 대상이 필요합니다.',
        'REVIVE_DISABLED_USE_DUNGEON' => '부활 시도는 던전에서만 가능합니다.',
        'DUNGEON_CLOSED' => '던전이 닫혀 있습니다.',
        'ALREADY_IN_DUNGEON' => '이미 던전에서 부활을 대기 중입니다.',
        'PLAYER_NOT_DEAD' => '던전 입장은 탈락 상태에서만 가능합니다.',
        'PLAYER_NOT_FOUND' => '플레이어 상태를 찾지 못했습니다.',
        'PLAYER_DEAD' => '탈락 상태에서는 해당 행동을 할 수 없습니다.',
        'ATTACK_DISABLED_USE_DUEL' => '직접 공격 대신 대결을 사용해주세요.',
        'CP_NOT_FOUND' => '거점 정보를 찾지 못했습니다.',
        'ACTION_REJECTED' => '요청이 거부되었습니다.',
        _ => code ?? '처리에 실패했습니다.',
      };

  @override
  Widget build(BuildContext context) {
    final fwState = ref.watch(fantasyWarsProvider(widget.sessionId));
    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    final authUser = ref.watch(authProvider).valueOrNull;
    final myId = authUser?.id;

    _handleStateSideEffects(fwState, mapState, myId);

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final chipOffset = bottomSafe + 80;
    final nearestControlPoint = _nearestControlPoint(fwState, mapState, myId);
    final nearestControlPointDistance = nearestControlPoint == null
        ? null
        : _distanceToControlPoint(nearestControlPoint, mapState, myId);
    final enemyCandidateIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
    );

    final canShowCapture = fwState.myState.isAlive &&
        !fwState.myState.inDuel &&
        nearestControlPoint != null &&
        (nearestControlPointDistance ?? double.infinity) <= 40 &&
        nearestControlPoint.capturedBy != fwState.myState.guildId;
    final capturePoint = canShowCapture ? nearestControlPoint : null;
    final isCancellingCapture = canShowCapture &&
        fwState.myState.captureZone == capturePoint?.id &&
        capturePoint?.capturingGuild == fwState.myState.guildId;

    final captureLabel = canShowCapture
        ? '${isCancellingCapture ? '점령 취소' : '점령 시작'} · ${capturePoint?.displayName ?? ''}'
        : null;
    final duelLabel = fwState.myState.isAlive &&
            !fwState.myState.inDuel &&
            fwState.duel.phase == 'idle' &&
            enemyCandidateIds.isNotEmpty
        ? '대결 요청'
        : null;
    final dungeonLabel = !fwState.myState.isAlive
        ? (fwState.myState.dungeonEntered
            ? '던전 대기 · ${(100 * (fwState.myState.nextReviveChance ?? 0.3)).round()}%'
            : '던전 입장')
        : null;

    final memberLabels = <String, String>{
      for (final entry in mapState.members.entries) entry.key: entry.value.nickname,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmLeave();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_mapSdkReady)
              Positioned.fill(
                child: NaverMap(
                  options: NaverMapViewOptions(
                    locationButtonEnable: false,
                    initialCameraPosition: NCameraPosition(
                      target: mapState.myPosition != null
                          ? NLatLng(
                              mapState.myPosition!.latitude,
                              mapState.myPosition!.longitude,
                            )
                          : const NLatLng(37.5665, 126.9780),
                      zoom: 16,
                    ),
                  ),
                  onMapTapped: (_, __) {
                    if (_selectedMemberId != null || _selectedControlPointId != null) {
                      _setSelection();
                    }
                  },
                  onMapReady: (controller) async {
                    _mapController = controller;
                    _lastOverlaySignature = null;
                    _lastControlPointSignature = null;
                    _lastBattlefieldSignature = null;
                    try {
                      controller.setLocationTrackingMode(NLocationTrackingMode.noFollow);
                    } catch (_) {}
                    _scheduleOverlaySync(fwState, mapState, myId);
                  },
                ),
              )
            else
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0xFF0F172A),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            FwTopHud(
              myState: fwState.myState,
              guilds: fwState.guilds,
              aliveCount: fwState.alivePlayerIds.length,
            ),
            FwWorldStatusPanel(
              myState: fwState.myState,
              dungeons: fwState.dungeons,
              memberLabels: memberLabels,
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: SafeArea(
                child: TextButton(
                  onPressed: _confirmLeave,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('나가기'),
                ),
              ),
            ),
            FwControlPointChips(
              controlPoints: fwState.controlPoints,
              myGuildId: fwState.myState.guildId,
              bottomOffset: chipOffset,
            ),
            FwActionDock(
              bottomOffset: chipOffset,
              captureLabel: captureLabel,
              onCapture: canShowCapture
                  ? () => unawaited(_handleCaptureAction(fwState, mapState, myId))
                  : null,
              duelLabel: duelLabel,
              onDuel: duelLabel == null
                  ? null
                  : () => unawaited(_handleDuelAction(fwState, mapState, myId)),
              dungeonLabel: dungeonLabel,
              onDungeon: (!fwState.myState.isAlive && !fwState.myState.dungeonEntered)
                  ? () => unawaited(_runAck(() {
                        return ref
                            .read(fantasyWarsProvider(widget.sessionId).notifier)
                            .enterDungeon();
                      }))
                  : null,
            ),
            if (fwState.myState.isAlive && !fwState.myState.inDuel)
              FwSkillButton(
                job: fwState.myState.job,
                skillUsedAt: fwState.myState.skillUsedAt,
                bottomOffset: chipOffset,
                onPressed: () => unawaited(_handleSkillAction(fwState, mapState, myId)),
              ),
            if (fwState.duel.phase == 'challenged' && fwState.duel.duelId != null)
              FwDuelChallengeDialog(
                duelId: fwState.duel.duelId!,
                opponentId: fwState.duel.opponentId,
                onAccept: () => unawaited(_runAck(() {
                  return ref
                      .read(fantasyWarsProvider(widget.sessionId).notifier)
                      .acceptDuel(fwState.duel.duelId!);
                })),
                onReject: () => unawaited(_runAck(() {
                  return ref
                      .read(fantasyWarsProvider(widget.sessionId).notifier)
                      .rejectDuel(fwState.duel.duelId!);
                })),
              ),
            if (fwState.duel.phase == 'challenging')
              FwChallengingIndicator(
                opponentId: fwState.duel.opponentId,
                onCancel: () => unawaited(_runAck(() {
                  return ref
                      .read(fantasyWarsProvider(widget.sessionId).notifier)
                      .cancelDuel();
                })),
              ),
            if (fwState.duel.phase == 'in_game')
              FwDuelScreen(
                sessionId: widget.sessionId,
                duel: fwState.duel,
              ),
            if (fwState.duel.phase == 'result' && fwState.duel.duelResult != null)
              FwDuelResultOverlay(
                result: fwState.duel.duelResult!,
                myId: myId,
                onClose: () => ref
                    .read(fantasyWarsProvider(widget.sessionId).notifier)
                    .clearDuelResult(),
              ),
            if (fwState.isFinished && fwState.winCondition != null)
              FwGameOverOverlay(
                winCondition: fwState.winCondition!,
                myGuildId: fwState.myState.guildId,
                guilds: fwState.guilds,
                onLeave: _confirmLeave,
              ),
          ],
        ),
      ),
    );
  }
}

class _TargetChoice<T> {
  const _TargetChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.trailing,
    this.badge,
    this.helper,
    this.accentColor,
    this.icon = Icons.person_outline_rounded,
    this.isHighlighted = false,
  });

  final T value;
  final String label;
  final String? subtitle;
  final String? trailing;
  final String? badge;
  final String? helper;
  final Color? accentColor;
  final IconData icon;
  final bool isHighlighted;
}

class _ChoiceBadge extends StatelessWidget {
  const _ChoiceBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;
}

