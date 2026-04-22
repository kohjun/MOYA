// lib/features/game/presentation/modules/qr_mission_module.dart
//
// QR 코드 스캔으로 미션을 완료하는 모듈 (중앙)
// activeModules: 'mission' (QR 스캔 미션이 포함된 경우)

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';
import '../widgets/game_action_buttons.dart';

class QrMissionModule extends GameModule {
  @override
  String get moduleId => 'qr_mission';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.canShowMission || !ctx.isInProgress || ctx.isGhostMode) {
      return const [];
    }
    return [
      ModuleButton(
        slot: ActionSlot.center,
        widget: GameActionButton(
          label: 'QR',
          color: const Color(0xFF7C3AED),
          onTap: ctx.onQrScan,
        ),
      ),
    ];
  }
}
