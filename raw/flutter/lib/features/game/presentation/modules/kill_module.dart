// lib/features/game/presentation/modules/kill_module.dart
//
// 킬/제거/태그 버튼 모듈 (임포스터 전용, 왼쪽 고정)
// activeModules: 'proximity' (근접 킬) 또는 SessionType.chase

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';
import '../widgets/game_action_buttons.dart';

class KillModule extends GameModule {
  @override
  String get moduleId => 'kill';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.canKill) return const [];
    return [
      ModuleButton(
        slot: ActionSlot.left,
        widget: GameKillButton(
          label: ctx.killCooldown > 0
              ? '${ctx.killLabel} ${ctx.killCooldown}s'
              : ctx.killLabel,
          cooldown: ctx.killCooldown > 0,
          onTap: ctx.onKill,
        ),
      ),
    ];
  }
}
