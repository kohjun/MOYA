import 'package:flutter/material.dart';

import '../../game_ui_plugin.dart';
import 'color_chaser_game_screen.dart';

class ColorChaserUiPlugin implements GameUiPlugin {
  const ColorChaserUiPlugin();

  @override
  String get gameType => 'color_chaser';

  @override
  String get displayName => '무지개 꼬리잡기: 컬러 체이서';

  @override
  int get minPlayers => 4;

  @override
  Widget buildScreen(BuildContext context, String sessionId) {
    return ColorChaserGameScreen(sessionId: sessionId);
  }
}
