// lib/features/game/presentation/modes/location_mode_plugin.dart
//
// 위치 탐색 모드 (mission + item)
// 포함 모듈: 사보타지, 미션 목록, QR 스캔, 구역이탈 경고

import '../game_mode_plugin.dart';
import '../game_module.dart';
import '../modules/sabotage_module.dart';
import '../modules/location_mission_module.dart';
import '../modules/qr_mission_module.dart';
import '../modules/bounds_module.dart';

class LocationModePlugin extends GameModePlugin {
  @override
  String get modeName => '위치 탐색';

  @override
  List<GameModule> get modules => [
        SabotageModule(),        // center: 사보타지 (임포스터)
        LocationMissionModule(), // center: 미션 목록 + 수행 팝업
        QrMissionModule(),       // center: QR 스캔
        BoundsModule(),          // overlay: 구역이탈 경고
      ];
}
