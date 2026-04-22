// lib/features/game/presentation/game_mode_plugin.dart
//
// 게임 모드 플러그인 추상 인터페이스
//
// GameModePlugin은 modules 리스트만 선언하면
// ModuleComposer가 buildBottomActions / buildStackLayers를 자동 조립합니다.
//
// 새 모드 추가:
//   1. GameModePlugin을 상속하는 클래스 생성
//   2. modeName과 modules 게터를 구현
//   3. createPlugin() switch에 케이스 추가

import 'package:flutter/material.dart';

import '../../../features/home/data/session_repository.dart';
import '../data/game_models.dart';
import '../../map/presentation/map_session_models.dart';
import 'game_module.dart';
import 'modes/verbal_mode_plugin.dart';
import 'modes/chase_mode_plugin.dart';
import 'modes/location_mode_plugin.dart';
import 'modes/default_mode_plugin.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GamePluginCtx — 플러그인·모듈에 전달되는 공유 상태 스냅샷
// ─────────────────────────────────────────────────────────────────────────────

class GamePluginCtx {
  const GamePluginCtx({
    required this.sessionId,
    required this.gameState,
    required this.mapState,
    required this.myUserId,
    required this.isGhostMode,
    required this.isInProgress,
    required this.chatBarH,
    // Kill
    required this.canKill,
    required this.killCooldown,
    required this.killLabel,
    required this.onKill,
    // Meeting
    required this.canCallMeeting,
    required this.isMeetingCoolingDown,
    required this.onCallMeeting,
    // Report (시체 신고)
    required this.canReport,
    required this.onReport,
    // Mission / QR
    required this.canShowMission,
    required this.onShowMission,
    required this.onQrScan,
    // Sabotage
    required this.canSabotage,
    required this.onSabotage,
    // Bounds
    required this.isOutOfBounds,
    required this.boundsAlertPulse,
    // Location missions
    required this.readyLocationMissions,
    required this.onPerformMission,
  });

  final String sessionId;
  final AmongUsGameState gameState;
  final MapSessionState mapState;
  final String? myUserId;
  final bool isGhostMode;
  final bool isInProgress;
  final double chatBarH;

  // ── Kill ──────────────────────────────────────────────
  final bool canKill;
  final int killCooldown;
  final String killLabel;
  final VoidCallback? onKill;

  // ── Meeting ───────────────────────────────────────────
  final bool canCallMeeting;
  final bool isMeetingCoolingDown;
  final VoidCallback onCallMeeting;

  // ── Report ────────────────────────────────────────────
  final bool canReport;
  final VoidCallback onReport;

  // ── Mission / QR ──────────────────────────────────────
  final bool canShowMission;
  final VoidCallback onShowMission;
  final VoidCallback onQrScan;

  // ── Sabotage ──────────────────────────────────────────
  final bool canSabotage;
  final VoidCallback onSabotage;

  // ── Bounds ────────────────────────────────────────────
  final bool isOutOfBounds;
  final bool boundsAlertPulse;

  // ── Location missions ─────────────────────────────────
  final List<Mission> readyLocationMissions;
  final VoidCallback? onPerformMission;
}

// ─────────────────────────────────────────────────────────────────────────────
// GameModePlugin — 모드 플러그인 기반 클래스
//
// modules 게터를 오버라이드하면 buildBottomActions / buildStackLayers가
// ModuleComposer에 의해 자동으로 조립됩니다.
// ─────────────────────────────────────────────────────────────────────────────

abstract class GameModePlugin {
  String get modeName;

  /// 이 모드에서 활성화할 기능 모듈 목록.
  /// 순서가 버튼 배치 순서에 영향을 줍니다.
  List<GameModule> get modules;

  /// 하단 액션 Row — modules 기반으로 ModuleComposer가 조립
  Widget buildBottomActions(BuildContext context, GamePluginCtx ctx) =>
      ModuleComposer.buildBottomActions(modules, context, ctx);

  /// Stack 레이어 목록 — modules 기반으로 ModuleComposer가 조립
  List<Widget> buildStackLayers(BuildContext context, GamePluginCtx ctx) =>
      ModuleComposer.buildStackLayers(modules, context, ctx);

  void dispose() {}
}

// ─────────────────────────────────────────────────────────────────────────────
// 팩토리: 세션 타입에 맞는 플러그인 인스턴스 생성
// ─────────────────────────────────────────────────────────────────────────────

GameModePlugin createPlugin(SessionType type) {
  switch (type) {
    case SessionType.verbal:
      return VerbalModePlugin();
    case SessionType.chase:
      return ChaseModePlugin();
    case SessionType.location:
      return LocationModePlugin();
    case SessionType.defaultType:
      return DefaultModePlugin();
  }
}
