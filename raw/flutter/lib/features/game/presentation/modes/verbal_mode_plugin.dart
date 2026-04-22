// lib/features/game/presentation/modes/verbal_mode_plugin.dart
//
// 언어추론 모드 (vote + round + team)
// 포함 모듈: 킬, 사보타지, 회의/시체신고, 구역이탈, QR미션, 위치미션
//
// 새 기능 추가 시 modules 리스트에 GameModule 인스턴스를 추가하세요.

import 'package:flutter/material.dart';
import '../game_mode_plugin.dart';
import '../game_module.dart';
import '../modules/kill_module.dart';
import '../modules/sabotage_module.dart';
import '../modules/meeting_module.dart';
import '../modules/bounds_module.dart';
import '../modules/qr_mission_module.dart';
import '../modules/location_mission_module.dart';
import '../widgets/game_action_buttons.dart';

class VerbalModePlugin extends GameModePlugin {
  @override
  String get modeName => '언어추론';

  /// 모듈 선언 순서 = 버튼 배치 순서
  /// left: [킬] / center: [사보타지, 미션, QR] / right: [시체신고, 회의소집]
  @override
  List<GameModule> get modules => [
        KillModule(),            // left: 킬/제거
        SabotageModule(),        // center: 사보타지
        LocationMissionModule(), // center: 미션 목록 + 수행 팝업
        QrMissionModule(),       // center: QR 스캔
        MeetingModule(),         // right: 시체신고 + 회의소집
        BoundsModule(),          // overlay: 구역이탈 경고
      ];

  // ── 추가 Stack 레이어 (모듈 외 모드 고유 UI) ─────────────────────────────
  @override
  List<Widget> buildStackLayers(BuildContext context, GamePluginCtx ctx) {
    final layers = <Widget>[
      // 모듈 공통 레이어
      ...super.buildStackLayers(context, ctx),
    ];

    // 라운드 번호 칩 (언어추론 전용)
    final round = ctx.mapState.gameState.roundNumber;
    if (ctx.isInProgress && round != null) {
      layers.add(
        Positioned(
          top: MediaQuery.of(context).padding.top + 112,
          left: 16,
          child: GameInfoChip(
            label: '라운드 $round',
            accent: Colors.orangeAccent,
          ),
        ),
      );
    }

    return layers;
  }
}
