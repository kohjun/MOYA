// lib/features/game/presentation/modules/nfc_mission_module.dart
//
// NFC 태그를 통해 미션을 완료하는 모듈 (중앙)
// activeModules: 'nfc_mission'
//
// TODO: NFC 스캔 화면(NfcScannerScreen) 구현 후 연결
//       현재는 버튼만 제공하며 탭 시 미구현 안내를 표시합니다.

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';
import '../widgets/game_action_buttons.dart';

class NfcMissionModule extends GameModule {
  @override
  String get moduleId => 'nfc_mission';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.isInProgress || ctx.isGhostMode) return const [];
    return [
      ModuleButton(
        slot: ActionSlot.center,
        widget: GameActionButton(
          label: 'NFC',
          color: const Color(0xFF0369A1),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('NFC 미션은 준비 중입니다.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    ];
  }
}
