// lib/features/game/presentation/modules/meeting_module.dart
//
// 회의 소집 + 시체 신고 모듈 (오른쪽 고정)
// 시체신고는 회의소집 바로 왼쪽에 배치됩니다.
// activeModules: 'vote', 'round'

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';
import '../widgets/game_action_buttons.dart';

class MeetingModule extends GameModule {
  @override
  String get moduleId => 'meeting';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) {
    final buttons = <ModuleButton>[];

    // 시체 신고 (회의소집 바로 왼쪽 — 오른쪽 슬롯에 먼저 추가)
    if (ctx.canReport) {
      buttons.add(ModuleButton(
        slot: ActionSlot.right,
        widget: GameActionButton(
          label: '시체 신고',
          color: const Color(0xFFD14343),
          onTap: ctx.onReport,
        ),
      ));
    }

    // 회의 소집 (가장 오른쪽)
    if (ctx.canCallMeeting) {
      buttons.add(ModuleButton(
        slot: ActionSlot.right,
        widget: GameActionButton(
          label: ctx.isMeetingCoolingDown ? '회의 쿨타임' : '회의 소집',
          color: ctx.isMeetingCoolingDown
              ? Colors.grey.shade700
              : const Color(0xFFB45309),
          onTap: ctx.isMeetingCoolingDown ? null : ctx.onCallMeeting,
        ),
      ));
    }

    return buttons;
  }
}
