// lib/features/game/presentation/modules/sabotage_module.dart
//
// 사보타지 버튼 모듈 (임포스터 전용, 중앙)
// activeModules: 'mission' (미션이 있는 모드에서 임포스터가 방해)

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';
import '../widgets/game_action_buttons.dart';

class SabotageModule extends GameModule {
  @override
  String get moduleId => 'sabotage';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.canSabotage) return const [];
    return [
      ModuleButton(
        slot: ActionSlot.center,
        widget: GameActionButton(
          label: '사보타지',
          color: const Color(0xFF991B1B),
          onTap: ctx.onSabotage,
        ),
      ),
    ];
  }
}
