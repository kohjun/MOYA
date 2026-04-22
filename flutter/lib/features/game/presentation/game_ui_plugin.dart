// lib/features/game/presentation/game_ui_plugin.dart
//
// Game UI Plugin — transport-agnostic game UI 추상 인터페이스.
// 각 게임 타입은 GameUiPlugin을 구현하고 GameUiPluginRegistry에 등록한다.
// GameShellScreen은 gameType으로 레지스트리를 조회해 올바른 화면을 반환한다.
// generic layer는 AmongUsGameState 같은 게임별 타입을 직접 참조하지 않는다.

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GameUiPlugin — 게임 UI 플러그인 인터페이스
// ─────────────────────────────────────────────────────────────────────────────

abstract class GameUiPlugin {
  /// 백엔드 gameType 식별자 (e.g. 'among_us', 'fantasy_wars')
  String get gameType;

  /// 사람이 읽을 수 있는 표시 이름
  String get displayName;

  /// 이 게임의 최소 참가 인원 (로비 시작 조건 검증용)
  int get minPlayers;

  /// 게임 화면 위젯을 반환한다. Shell이 이를 직접 렌더링한다.
  Widget buildScreen(BuildContext context, String sessionId);
}

// ─────────────────────────────────────────────────────────────────────────────
// GameUiPluginRegistry — gameType → GameUiPlugin 조회 레지스트리
// ─────────────────────────────────────────────────────────────────────────────

class GameUiPluginRegistry {
  static final _plugins = <String, GameUiPlugin>{};
  static const _aliases = <String, String>{
    'fantasy_wars': 'fantasy_wars_artifact',
  };

  /// 플러그인 등록 (앱 초기화 시 호출)
  static void register(GameUiPlugin plugin) {
    _plugins[plugin.gameType] = plugin;
  }

  /// gameType으로 플러그인 조회. 미등록이면 null.
  static GameUiPlugin? get(String gameType) {
    final resolved = _aliases[gameType] ?? gameType;
    return _plugins[resolved];
  }

  /// gameType으로 조회. 없으면 'among_us' 폴백 → 그것도 없으면 첫 번째.
  static GameUiPlugin resolve(String? gameType) {
    final resolved = _aliases[gameType] ?? gameType;
    return _plugins[resolved ?? 'among_us'] ??
        _plugins['among_us'] ??
        _plugins.values.first;
  }

  /// 등록된 플러그인의 최소 인원 수 반환. 미등록이면 기본값 4.
  static int minPlayersFor(String? gameType) {
    return get(gameType ?? 'among_us')?.minPlayers ?? 4;
  }

  /// 등록된 게임 타입 목록
  static List<String> get registeredTypes => _plugins.keys.toList();
}
