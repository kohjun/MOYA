// lib/features/game/presentation/game_module.dart
//
// 게임 기능 모듈 추상 인터페이스 + 레이아웃 조합기
//
// 각 GameModule은 독립된 게임 기능 단위입니다.
// ─ buildButtons() : 하단 액션 Row에 기여할 버튼과 배치 위치(ActionSlot)를 반환
// ─ buildStackLayers() : 지도 Stack에 추가할 Positioned 위젯을 반환
//
// GameModePlugin은 modules 리스트만 선언하면
// ModuleComposer가 자동으로 레이아웃을 조립합니다.
//
// 새 기능 추가 = 새 GameModule 파일 하나 작성 후 원하는 모드의 modules에 추가.

import 'package:flutter/material.dart';
import 'game_mode_plugin.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ActionSlot — 버튼이 배치될 위치
// ─────────────────────────────────────────────────────────────────────────────

enum ActionSlot {
  /// 왼쪽 고정 (킬 버튼 등 임포스터 공격 액션)
  left,

  /// 중앙 스크롤 영역 (미션, QR, 사보타지 등 보조 액션)
  center,

  /// 오른쪽 고정 (회의소집, 시체신고 등 공용 액션)
  right,
}

// ─────────────────────────────────────────────────────────────────────────────
// ModuleButton — 모듈이 기여하는 버튼 + 배치 위치
// ─────────────────────────────────────────────────────────────────────────────

class ModuleButton {
  const ModuleButton({required this.widget, required this.slot});
  final Widget widget;
  final ActionSlot slot;
}

// ─────────────────────────────────────────────────────────────────────────────
// GameModule — 기능 모듈 추상 인터페이스
// ─────────────────────────────────────────────────────────────────────────────

abstract class GameModule {
  /// 모듈 식별자 (서버 activeModules 키와 대응)
  String get moduleId;

  /// 하단 액션 Row에 기여할 버튼 목록
  /// 조건이 충족되지 않으면 빈 리스트를 반환하세요.
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx);

  /// 지도 Stack에 추가할 Positioned 레이어 목록
  List<Widget> buildStackLayers(BuildContext context, GamePluginCtx ctx) =>
      const [];
}

// ─────────────────────────────────────────────────────────────────────────────
// ModuleComposer — 모듈 목록을 받아 UI를 조립하는 정적 유틸
// ─────────────────────────────────────────────────────────────────────────────

class ModuleComposer {
  ModuleComposer._();

  /// 여러 모듈의 버튼을 left / center / right 슬롯으로 분류하여
  /// 하나의 Row 위젯으로 조립합니다.
  ///
  /// 레이아웃:
  ///   [LEFT 고정] [CENTER Expanded 스크롤] [RIGHT 고정]
  static Widget buildBottomActions(
    List<GameModule> modules,
    BuildContext context,
    GamePluginCtx ctx,
  ) {
    final left = <Widget>[];
    final center = <Widget>[];
    final right = <Widget>[];

    for (final module in modules) {
      for (final btn in module.buildButtons(context, ctx)) {
        switch (btn.slot) {
          case ActionSlot.left:
            left.add(btn.widget);
          case ActionSlot.center:
            center.add(btn.widget);
          case ActionSlot.right:
            right.add(btn.widget);
        }
      }
    }

    // 아무 버튼도 없으면 빈 공간 반환
    if (left.isEmpty && center.isEmpty && right.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 왼쪽 고정 (킬 등) ────────────────────────────────────
          for (int i = 0; i < left.length; i++) ...[
            left[i],
            if (i < left.length - 1 || center.isNotEmpty || right.isNotEmpty)
              const SizedBox(width: 8),
          ],

          // ── 중앙 스크롤 ──────────────────────────────────────────
          Expanded(
            child: center.isNotEmpty
                ? SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      itemCount: center.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => center[i],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── 오른쪽 고정 (회의소집 등) ────────────────────────────
          for (int i = 0; i < right.length; i++) ...[
            const SizedBox(width: 8),
            right[i],
          ],
        ],
      ),
    );
  }

  /// 여러 모듈의 Stack 레이어를 하나의 리스트로 합칩니다.
  static List<Widget> buildStackLayers(
    List<GameModule> modules,
    BuildContext context,
    GamePluginCtx ctx,
  ) {
    return [
      for (final module in modules)
        ...module.buildStackLayers(context, ctx),
    ];
  }
}
