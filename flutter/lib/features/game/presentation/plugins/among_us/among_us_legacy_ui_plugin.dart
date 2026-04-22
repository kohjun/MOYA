// lib/features/game/presentation/plugins/among_us/among_us_legacy_ui_plugin.dart
//
// AmongUsLegacyUiPlugin — 기존 GameMainScreen을 플러그인으로 래핑.
// generic layer에서 직접 참조되지 않도록 격리한다.
// SessionType.verbal은 이 플러그인 내부에서만 사용한다.

import 'package:flutter/material.dart';

import '../../../../../features/home/data/session_repository.dart';
import '../../game_main_screen.dart';
import '../../game_ui_plugin.dart';

class AmongUsLegacyUiPlugin implements GameUiPlugin {
  const AmongUsLegacyUiPlugin();

  @override
  String get gameType => 'among_us';

  @override
  String get displayName => '어몽어스';

  @override
  int get minPlayers => 4;

  @override
  Widget buildScreen(BuildContext context, String sessionId) {
    return GameMainScreen(
      sessionId: sessionId,
      sessionType: SessionType.verbal,
    );
  }
}
