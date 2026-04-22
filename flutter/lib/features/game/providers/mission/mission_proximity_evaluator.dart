import 'package:geolocator/geolocator.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;

import '../../data/game_models.dart';
import 'mission_geo_utils.dart';

/// 하나의 GPS 위치 수신에 대한 미션 근접/영역 이탈 판정 결과.
class ProximityEvaluation {
  const ProximityEvaluation({
    required this.nearbyMissionIds,
    required this.isOutOfBounds,
  });

  /// 근접 판정된 맵 기반 미션 ID 목록 (started/ready 상태만 평가 대상).
  final List<String> nearbyMissionIds;

  /// 플레이 영역 이탈 여부. 폴리곤이 없으면 null (판정 불가).
  final bool? isOutOfBounds;
}

/// 위치 기반 미션의 근접/영역 이탈 판정을 수행하는 순수 계산기.
/// 상태를 보유하지 않으며 입력 → 결과로만 동작한다.
class MissionProximityEvaluator {
  MissionProximityEvaluator._();

  /// GPS 위치 1회 수신에 대해 근접 미션과 영역 이탈을 함께 판정한다.
  /// - 평가 대상: `MissionStatus.started` 또는 `MissionStatus.ready` 상태의
  ///   맵 기반(`isMapBased`) 미션. `locked`/`completed`/`minigame`은 제외.
  /// - 동물 포획(`captureAnimal`)은 [animalRadius]m 이내, 코인 수집은
  ///   [coinRadius]m 이내에서 근접으로 판정한다.
  static ProximityEvaluation evaluate({
    required List<Mission> myMissions,
    required Map<String, List<CoinPoint>> missionCoins,
    required Map<String, AnimalPoint> missionAnimals,
    required double lat,
    required double lng,
    required List<mt.LatLng>? polygon,
    required double coinRadius,
    required double animalRadius,
  }) {
    final outOfBounds = MissionGeoUtils.isOutsidePolygon(lat, lng, polygon);

    final nearby = <String>[];
    for (final mission in myMissions) {
      if (mission.status == MissionStatus.completed) continue;
      if (mission.status == MissionStatus.locked) continue;

      switch (mission.type) {
        case MissionType.coinCollect:
          final coins = missionCoins[mission.id];
          if (coins == null) break;
          final hit = coins.any((c) =>
              !c.collected &&
              Geolocator.distanceBetween(lat, lng, c.lat, c.lng) <= coinRadius);
          if (hit) nearby.add(mission.id);
          break;
        case MissionType.captureAnimal:
          final animal = missionAnimals[mission.id];
          if (animal == null) break;
          final d = Geolocator.distanceBetween(lat, lng, animal.lat, animal.lng);
          if (d <= animalRadius) nearby.add(mission.id);
          break;
        case MissionType.minigame:
          // MINIGAME은 위치 무관 — proximity 후보에서 제외.
          break;
      }
    }

    return ProximityEvaluation(
      nearbyMissionIds: nearby,
      isOutOfBounds: outOfBounds,
    );
  }

  /// proximity 결과에 맞춰 `myMissions`의 상태(started ↔ ready)를 전이시킨
  /// 새 리스트를 돌려준다. minigame/locked/completed는 그대로 유지한다.
  static List<Mission> applyProximityToMissions({
    required List<Mission> myMissions,
    required List<String> nearbyIds,
  }) {
    return myMissions.map((m) {
      if (m.status == MissionStatus.completed) return m;
      if (m.status == MissionStatus.locked) return m;
      if (m.type == MissionType.minigame) return m;
      final isNear = nearbyIds.contains(m.id);
      if (isNear && m.status == MissionStatus.started) {
        return m.copyWith(status: MissionStatus.ready);
      }
      if (!isNear && m.status == MissionStatus.ready) {
        return m.copyWith(status: MissionStatus.started);
      }
      return m;
    }).toList();
  }
}
