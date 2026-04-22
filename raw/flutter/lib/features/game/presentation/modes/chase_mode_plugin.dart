// lib/features/game/presentation/modes/chase_mode_plugin.dart
//
// 공간 추격 모드 (proximity + tag + team)
// 포함 모듈: 킬/태그 버튼, 태거 칩

import 'package:flutter/material.dart';
import '../game_mode_plugin.dart';
import '../game_module.dart';
import '../modules/kill_module.dart';
import '../widgets/game_action_buttons.dart';

class ChaseModePlugin extends GameModePlugin {
  @override
  String get modeName => '공간 추격';

  @override
  List<GameModule> get modules => [
        KillModule(), // left: 킬/태그
      ];

  // 태거 칩은 모듈 외 모드 고유 UI
  @override
  List<Widget> buildStackLayers(BuildContext context, GamePluginCtx ctx) {
    final layers = <Widget>[...super.buildStackLayers(context, ctx)];
    final taggerId = ctx.mapState.gameState.taggerId;

    if (ctx.isInProgress && taggerId != null) {
      final isMe = taggerId == ctx.myUserId;
      layers.add(
        Positioned(
          top: MediaQuery.of(context).padding.top + 112,
          left: 16,
          child: GameInfoChip(
            label: isMe ? '술래' : '추격 중',
            accent: isMe ? Colors.redAccent : Colors.white,
          ),
        ),
      );
    }

    return layers;
  }
}
