// lib/features/game/presentation/modes/default_mode_plugin.dart
//
// 기본 위치공유 모드 — 게임 액션 없이 위치만 공유

import '../game_mode_plugin.dart';
import '../game_module.dart';

class DefaultModePlugin extends GameModePlugin {
  @override
  String get modeName => '기본 위치공유';

  @override
  List<GameModule> get modules => const [];
}
