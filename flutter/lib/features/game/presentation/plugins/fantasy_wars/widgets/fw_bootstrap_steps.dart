import 'package:flutter/material.dart';

// 게임 진입 직전 부트스트랩 시퀀스 (BLE 권한 / 위치 권한 / FCM 등) 한 단계의
// 데이터 모델 + 한 줄 타일 위젯.
//
// _bootstrapSteps() / _cleanBootstrapSteps() 메서드가 List<FwBootstrapStep> 을
// 반환하므로 외부 (fantasy_wars_game_screen.dart) 에서 import 하여 타입으로 사용한다.

class FwBootstrapStep {
  const FwBootstrapStep({
    required this.title,
    required this.description,
    required this.ready,
    required this.required,
    required this.icon,
  });

  final String title;
  final String description;
  final bool ready;
  final bool required;
  final IconData icon;
}

// 부트스트랩 시퀀스 v2 의 한 줄 타일.
// 디자인 토큰 미사용 — 진입 화면이 여전히 dark theme 을 가져 hex 직접 사용.
class FwBootstrapStepTile extends StatelessWidget {
  const FwBootstrapStepTile({super.key, required this.step});

  final FwBootstrapStep step;

  @override
  Widget build(BuildContext context) {
    final accentColor = step.ready
        ? const Color(0xFF22C55E)
        : step.required
            ? const Color(0xFF38BDF8)
            : Colors.white54;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            step.ready ? Icons.check_rounded : step.icon,
            color: accentColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (step.required
                              ? const Color(0xFF0EA5E9)
                              : Colors.white70)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: (step.required
                                ? const Color(0xFF0EA5E9)
                                : Colors.white54)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      step.required ? '필수' : '선택',
                      style: TextStyle(
                        color: step.required
                            ? const Color(0xFF7DD3FC)
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                step.description,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
