// lib/features/game/presentation/game_shell_screen.dart
//
// GameShellScreen — gameType 기반 UI 플러그인 라우터.
// generic layer는 게임별 state 타입을 직접 참조하지 않는다.
// 플러그인 내부는 각자의 state/provider를 사용한다.

import 'package:flutter/material.dart';

import 'game_ui_plugin.dart';

class GameShellScreen extends StatelessWidget {
  const GameShellScreen({
    super.key,
    required this.sessionId,
    this.gameType,
  });

  final String sessionId;
  final String? gameType;

  @override
  Widget build(BuildContext context) {
    final plugin = GameUiPluginRegistry.resolve(gameType);
    return plugin.buildScreen(context, sessionId);
  }
}
