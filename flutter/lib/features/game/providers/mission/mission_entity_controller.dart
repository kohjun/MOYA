import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;

import '../../data/game_models.dart';
import 'mission_geo_utils.dart';

/// 맵 기반 미션의 월드 엔티티(코인, 동물)를 소유하고 관리한다.
/// - 스폰: 미션당 1회만 수행되도록 idempotent하게 동작.
/// - 이동: `captureAnimal` 엔티티를 주기적으로 랜덤 이동시킨다.
///
/// Provider 외부에 상태를 저장하지 않는다. 현재 상태는 [readState]로 읽고,
/// 변경은 [writeState]로 Provider에 반영한다. 동물이 움직이면
/// [onEntitiesMoved]가 호출되어 Provider가 proximity를 재평가할 수 있다.
class MissionEntityController {
  MissionEntityController({
    required this.readState,
    required this.writeState,
    required this.onEntitiesMoved,
    required this.coinCount,
    required this.coinMinSeparation,
    required this.animalMinStep,
    required this.animalMaxStep,
    required this.animalTickInterval,
  });

  final AmongUsGameState Function() readState;
  final void Function(AmongUsGameState next) writeState;
  final void Function() onEntitiesMoved;

  final int coinCount;
  final double coinMinSeparation;
  final double animalMinStep;
  final double animalMaxStep;
  final Duration animalTickInterval;

  Timer? _animalTimer;

  /// 단일 미션의 월드 엔티티를 폴리곤 내부에 스폰한다.
  /// - 폴리곤이 null이면 no-op (false 반환).
  /// - 이미 스폰된 미션이면 no-op.
  /// - minigame 타입은 엔티티가 없어 no-op.
  /// 반환값: 실제 스폰 수행 여부.
  bool spawnFor(Mission mission, List<mt.LatLng>? polygon) {
    if (polygon == null) return false;
    if (mission.status == MissionStatus.completed) return false;

    final state = readState();

    switch (mission.type) {
      case MissionType.coinCollect:
        final existing = state.missionCoins[mission.id];
        if (existing != null && existing.isNotEmpty) return false;
        final pts = MissionGeoUtils.randomPointsInPolygon(
          polygon,
          count: coinCount,
          minSep: coinMinSeparation,
        );
        if (pts.isEmpty) return false;
        final coins = Map<String, List<CoinPoint>>.from(state.missionCoins)
          ..[mission.id] = pts
              .map((p) => CoinPoint(lat: p.latitude, lng: p.longitude))
              .toList();
        writeState(state.copyWith(missionCoins: coins));
        return true;

      case MissionType.captureAnimal:
        if (state.missionAnimals.containsKey(mission.id)) return false;
        final p = MissionGeoUtils.randomPointInPolygon(polygon);
        final animals = Map<String, AnimalPoint>.from(state.missionAnimals)
          ..[mission.id] = AnimalPoint(
            lat: p.latitude,
            lng: p.longitude,
            headingDeg: math.Random().nextDouble() * 360,
          );
        writeState(state.copyWith(missionAnimals: animals));
        startAnimalMovement();
        return true;

      case MissionType.minigame:
        return false;
    }
  }

  /// 동물 이동 타이머 시작. 이미 돌고 있거나 동물이 없으면 no-op.
  void startAnimalMovement() {
    if (_animalTimer != null) return;
    if (readState().missionAnimals.isEmpty) return;
    _animalTimer = Timer.periodic(animalTickInterval, (_) => _tick());
  }

  /// 특정 미션의 동물을 상태에서 제거한다.
  /// 남은 동물이 없으면 타이머를 정리한다.
  void removeAnimal(String missionId) {
    final state = readState();
    if (!state.missionAnimals.containsKey(missionId)) return;
    final map = Map<String, AnimalPoint>.from(state.missionAnimals)
      ..remove(missionId);
    writeState(state.copyWith(missionAnimals: map));
    if (map.isEmpty) {
      _animalTimer?.cancel();
      _animalTimer = null;
    }
  }

  /// 현재 플레이 영역 폴리곤 기준으로 동물을 1틱 이동시킨다.
  void _tick() {
    final state = readState();
    final polygon = MissionGeoUtils.buildPolygon(state.playableArea);
    if (polygon == null) return;
    if (state.missionAnimals.isEmpty) {
      _animalTimer?.cancel();
      _animalTimer = null;
      return;
    }

    final rng = math.Random();
    final updated = <String, AnimalPoint>{};
    var changed = false;

    state.missionAnimals.forEach((missionId, animal) {
      final mission = state.myMissions.firstWhere(
        (m) => m.id == missionId,
        orElse: () => const Mission(
          id: '',
          title: '',
          description: '',
          type: MissionType.captureAnimal,
          minigameId: '',
          status: MissionStatus.completed,
        ),
      );
      // 완료된/삭제된 미션의 동물은 제거.
      if (mission.id.isEmpty || mission.status == MissionStatus.completed) {
        changed = true;
        return;
      }

      final distance = animalMinStep +
          rng.nextDouble() * (animalMaxStep - animalMinStep);
      final from = mt.LatLng(animal.lat, animal.lng);

      mt.LatLng? candidate;
      var heading = animal.headingDeg;

      for (var attempt = 0; attempt < 3; attempt++) {
        final next = mt.SphericalUtil.computeOffset(from, distance, heading);
        if (mt.PolygonUtil.containsLocation(next, polygon, false)) {
          candidate = next;
          break;
        }
        heading = attempt == 0 ? (heading + 180) % 360 : rng.nextDouble() * 360;
      }

      if (candidate != null) {
        updated[missionId] = AnimalPoint(
          lat: candidate.latitude,
          lng: candidate.longitude,
          headingDeg: heading,
        );
      } else {
        updated[missionId] =
            animal.copyWith(headingDeg: rng.nextDouble() * 360);
      }
      changed = true;
    });

    if (!changed) return;
    writeState(state.copyWith(missionAnimals: updated));

    // 동물이 움직였으니 proximity 재평가를 Provider에 맡긴다.
    try {
      onEntitiesMoved();
    } catch (e) {
      debugPrint('[MissionEntityController] onEntitiesMoved error: $e');
    }

    if (updated.isEmpty) {
      _animalTimer?.cancel();
      _animalTimer = null;
    }
  }

  void dispose() {
    _animalTimer?.cancel();
    _animalTimer = null;
  }
}
