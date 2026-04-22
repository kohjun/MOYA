// lib/features/game/presentation/modules/location_mission_module.dart
//
// 위치 기반 미니게임 미션 모듈
// ─ 미션 목록 보기 버튼 (중앙)
// ─ 근처 미션 수행 버튼 팝업 (Stack 레이어)
// activeModules: 'mission'

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';
import '../widgets/game_action_buttons.dart';

class LocationMissionModule extends GameModule {
  @override
  String get moduleId => 'location_mission';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.canShowMission || !ctx.isInProgress || ctx.isGhostMode) {
      return const [];
    }
    return [
      ModuleButton(
        slot: ActionSlot.center,
        widget: GameActionButton(
          label: '미션',
          color: const Color(0xFF0F766E),
          onTap: ctx.onShowMission,
        ),
      ),
    ];
  }

  @override
  List<Widget> buildStackLayers(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.isInProgress ||
        ctx.readyLocationMissions.isEmpty ||
        ctx.isGhostMode) {
      return const [];
    }

    final mission = ctx.readyLocationMissions.first;
    return [
      Positioned(
        bottom: ctx.chatBarH + 80,
        left: 32,
        right: 32,
        child: Center(
          child: GamePillButton(
            label: mission.isSabotaged
                ? '통신 장애 수리'
                : '${mission.title} 수행',
            color: mission.isSabotaged
                ? const Color(0xFFB45309)
                : const Color(0xFF16A34A),
            onTap: ctx.onPerformMission ?? () {},
          ),
        ),
      ),
    ];
  }
}
