// lib/features/game/presentation/game_ui_plugin.dart
//
// Game UI Plugin — transport-agnostic game UI 추상 인터페이스.
// 각 게임 타입은 GameUiPlugin을 구현하고 GameUiPluginRegistry에 등록한다.
// GameShellScreen은 gameType으로 레지스트리를 조회해 올바른 화면을 반환한다.

import 'package:flutter/material.dart';

abstract class GameUiPlugin {
  /// 백엔드 gameType 식별자 (e.g. 'fantasy_wars_artifact')
  String get gameType;

  /// 사람이 읽을 수 있는 표시 이름
  String get displayName;

  /// 이 게임의 최소 참가 인원 (로비 시작 조건 검증용)
  int get minPlayers;

  /// 게임 화면 위젯을 반환한다. Shell이 이를 직접 렌더링한다.
  Widget buildScreen(BuildContext context, String sessionId);
}

class GameUiPluginRegistry {
  static final _plugins = <String, GameUiPlugin>{};
  static const _aliases = <String, String>{
    'fantasy_wars': 'fantasy_wars_artifact',
  };

  static void register(GameUiPlugin plugin) {
    _plugins[plugin.gameType] = plugin;
  }

  static GameUiPlugin? get(String gameType) {
    final resolved = _aliases[gameType] ?? gameType;
    return _plugins[resolved];
  }

  static GameUiPlugin resolve(String? gameType) {
    final resolved = _aliases[gameType] ?? gameType;
    return _plugins[resolved ?? 'fantasy_wars_artifact'] ??
        _plugins['fantasy_wars_artifact'] ??
        _plugins.values.first;
  }

  static int minPlayersFor(String? gameType) {
    return get(gameType ?? 'fantasy_wars_artifact')?.minPlayers ?? 9;
  }

  static List<String> get registeredTypes => _plugins.keys.toList();
}
