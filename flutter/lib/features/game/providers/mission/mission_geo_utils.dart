import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;

/// 게임 내 위치 기반 미션(코인/동물) 배치를 위한 순수 기하 유틸리티.
/// 상태를 보유하지 않으며, 모두 static 함수로만 구성된다.
class MissionGeoUtils {
  MissionGeoUtils._();

  /// 세션의 플레이 영역(`[{lat, lng}, ...]`)을 `mt.LatLng` 리스트로 변환한다.
  /// 3점 미만이면 null 반환.
  static List<mt.LatLng>? buildPolygon(List<Map<String, double>>? area) {
    if (area == null || area.length < 3) return null;
    return area
        .map((p) => mt.LatLng(p['lat'] ?? 0.0, p['lng'] ?? 0.0))
        .toList(growable: false);
  }

  /// 폴리곤 내부의 랜덤 좌표 하나. 실패 시 무게 중심 폴백.
  static mt.LatLng randomPointInPolygon(
    List<mt.LatLng> polygon, {
    int maxRetries = 60,
  }) {
    double minLat = polygon.first.latitude, maxLat = polygon.first.latitude;
    double minLng = polygon.first.longitude, maxLng = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final rng = math.Random();
    for (var i = 0; i < maxRetries; i++) {
      final candidate = mt.LatLng(
        minLat + rng.nextDouble() * (maxLat - minLat),
        minLng + rng.nextDouble() * (maxLng - minLng),
      );
      if (mt.PolygonUtil.containsLocation(candidate, polygon, false)) {
        return candidate;
      }
    }

    final cLat =
        polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final cLng =
        polygon.map((p) => p.longitude).reduce((a, b) => a + b) /
            polygon.length;
    return mt.LatLng(cLat, cLng);
  }

  /// 폴리곤 내부에서 서로 [minSep]m 이상 떨어진 [count]개의 좌표를 샘플링.
  static List<mt.LatLng> randomPointsInPolygon(
    List<mt.LatLng> polygon, {
    required int count,
    required double minSep,
    int maxGuard = 200,
  }) {
    final result = <mt.LatLng>[];
    var guard = 0;
    while (result.length < count && guard < maxGuard) {
      guard++;
      final p = randomPointInPolygon(polygon);
      final tooClose = result.any((q) =>
          Geolocator.distanceBetween(
              q.latitude, q.longitude, p.latitude, p.longitude) <
          minSep);
      if (tooClose) continue;
      result.add(p);
    }
    return result;
  }

  /// 주어진 좌표가 폴리곤 외부인지 여부.
  /// 폴리곤이 null이면 판정 불가이므로 null 반환.
  static bool? isOutsidePolygon(
    double lat,
    double lng,
    List<mt.LatLng>? polygon,
  ) {
    if (polygon == null) return null;
    return !mt.PolygonUtil.containsLocation(mt.LatLng(lat, lng), polygon, false);
  }
}
