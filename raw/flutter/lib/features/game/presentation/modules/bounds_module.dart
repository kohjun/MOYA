// lib/features/game/presentation/modules/bounds_module.dart
//
// 구역 이탈 경고 오버레이 모듈
// 플레이 영역(playableArea)이 설정된 세션에서 사용합니다.
// 버튼 기여 없음 — Stack 오버레이만 제공합니다.

import 'package:flutter/material.dart';
import '../game_module.dart';
import '../game_mode_plugin.dart';

class BoundsModule extends GameModule {
  @override
  String get moduleId => 'bounds';

  @override
  List<ModuleButton> buildButtons(BuildContext context, GamePluginCtx ctx) =>
      const [];

  @override
  List<Widget> buildStackLayers(BuildContext context, GamePluginCtx ctx) {
    if (!ctx.isOutOfBounds) return const [];

    return [
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            color: Colors.red
                .withValues(alpha: ctx.boundsAlertPulse ? 0.40 : 0.22),
            child: Center(
              child: AnimatedScale(
                scale: ctx.boundsAlertPulse ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOut,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.red.shade300.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '플레이 구역을 벗어났습니다',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '구역으로 돌아가주세요',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
