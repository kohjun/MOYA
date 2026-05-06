import 'dart:math' as math;

import '../../../../../map/presentation/map_session_models.dart';
import '../../../../providers/fantasy_wars_provider.dart';

class FantasyWarsGeoService {
  const FantasyWarsGeoService();

  static const double defaultCaptureRadiusMeters = 40;
  static const int defaultMinCaptureMemberCount = 2;

  String? guildIdForUser(Map<String, FwGuildInfo> guilds, String userId) {
    for (final guild in guilds.values) {
      if (guild.memberIds.contains(userId)) {
        return guild.guildId;
      }
    }
    return null;
  }

  ({double lat, double lng})? myPosition(
    MapSessionState mapState,
    String? myId,
  ) {
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

  double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
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

  double? distanceToControlPoint(
    FwControlPoint controlPoint,
    MapSessionState mapState,
    String? myId,
  ) {
    final position = myPosition(mapState, myId);
    if (position == null ||
        controlPoint.lat == null ||
        controlPoint.lng == null) {
      return null;
    }

    return distanceMeters(
      position.lat,
      position.lng,
      controlPoint.lat!,
      controlPoint.lng!,
    );
  }

  double? distanceToMember(
    String userId,
    MapSessionState mapState,
    String? myId,
  ) {
    final cachedDistance = mapState.memberDistances[userId];
    if (cachedDistance != null) {
      return cachedDistance;
    }

    final position = myPosition(mapState, myId);
    final member = mapState.members[userId];
    if (position == null ||
        member == null ||
        (member.lat == 0 && member.lng == 0)) {
      return null;
    }

    return distanceMeters(
      position.lat,
      position.lng,
      member.lat,
      member.lng,
    );
  }

  ({int count, int required}) captureCrewStatus(
    FwControlPoint controlPoint,
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId, {
    double captureRadiusMeters = defaultCaptureRadiusMeters,
    int minCaptureMemberCount = defaultMinCaptureMemberCount,
  }) {
    final guildId = fwState.myState.guildId;
    final required = captureRequiredCount(
      controlPoint,
      minCaptureMemberCount: minCaptureMemberCount,
    );

    if (guildId == null ||
        controlPoint.lat == null ||
        controlPoint.lng == null) {
      return (count: 0, required: required);
    }

    final guild = fwState.guilds[guildId];
    final candidateIds = <String>{
      if (myId != null) myId,
      ...?guild?.memberIds,
    };

    var count = 0;
    for (final userId in candidateIds) {
      if (fwState.eliminatedPlayerIds.contains(userId)) {
        continue;
      }

      ({double lat, double lng})? position;
      if (userId == myId) {
        position = myPosition(mapState, myId);
      } else {
        final member = mapState.members[userId];
        if (member != null && (member.lat != 0 || member.lng != 0)) {
          position = (lat: member.lat, lng: member.lng);
        }
      }

      if (position == null) {
        continue;
      }

      final distance = distanceMeters(
        position.lat,
        position.lng,
        controlPoint.lat!,
        controlPoint.lng!,
      );
      if (distance <= captureRadiusMeters) {
        count++;
      }
    }

    return (count: count, required: required);
  }

  int captureRequiredCount(
    FwControlPoint controlPoint, {
    int minCaptureMemberCount = defaultMinCaptureMemberCount,
  }) {
    if (controlPoint.requiredCount > 0) {
      return controlPoint.requiredCount;
    }
    return minCaptureMemberCount;
  }

  bool isOutsideBattlefield(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    if (fwState.playableArea.length < 3) {
      return false;
    }
    final position = myPosition(mapState, myId);
    if (position == null) {
      return false;
    }
    return !containsPoint(
      polygon: fwState.playableArea,
      lat: position.lat,
      lng: position.lng,
    );
  }

  bool containsPoint({
    required List<FwGeoPoint> polygon,
    required double lat,
    required double lng,
  }) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      final crosses = ((pi.lng > lng) != (pj.lng > lng)) &&
          (lat <
              (pj.lat - pi.lat) *
                      (lng - pi.lng) /
                      ((pj.lng - pi.lng).abs() < 0.0000001
                          ? 0.0000001
                          : pj.lng - pi.lng) +
                  pi.lat);
      if (crosses) {
        inside = !inside;
      }
    }
    return inside;
  }

  ({double lat, double lng})? battlefieldCenter(
    FantasyWarsGameState fwState,
  ) {
    if (fwState.playableArea.isEmpty) {
      return null;
    }

    var latSum = 0.0;
    var lngSum = 0.0;
    for (final point in fwState.playableArea) {
      latSum += point.lat;
      lngSum += point.lng;
    }

    return (
      lat: latSum / fwState.playableArea.length,
      lng: lngSum / fwState.playableArea.length,
    );
  }
}
