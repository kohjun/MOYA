import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';

// DuelAccepted — 결투 수락 직후 게임 추첨 트랜지션.
// 디자인 핸드오프 flow-screens.jsx 의 DuelAcceptedScreen 이식.
// - 두 클래스 뱃지 사이에 ok 컬러 체크
// - "받겠다." 세리프 인용
// - 6 칸 추첨 스피너 (council 포함 6 종 모두 활성)
// - 짧은 트랜지션 (~1.5s) 으로 server 가 fw:duel:started 보낼 때까지 자리 차지

// 미니게임 추첨 후보. 단일 source-of-truth(FwDuelClasses.spinnerCandidates) 를
// 참조해 카운트가 다른 화면(request copy 등) 과 drift 되지 않도록 한다.
const _kSpinnerCandidates = FwDuelClasses.spinnerCandidates;

class FwDuelAcceptedOverlay extends StatefulWidget {
  const FwDuelAcceptedOverlay({
    super.key,
    required this.myJob,
    required this.opponentName,
  });

  final String? myJob;
  final String opponentName;

  @override
  State<FwDuelAcceptedOverlay> createState() => _FwDuelAcceptedOverlayState();
}

class _FwDuelAcceptedOverlayState extends State<FwDuelAcceptedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinner;

  @override
  void initState() {
    super.initState();
    // 250ms 마다 다음 슬롯 하이라이트. 트랜지션 동안 무한 반복 (server in_game 진입까지).
    _spinner = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // 6 candidates × 250ms
    )..repeat();
  }

  @override
  void dispose() {
    _spinner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myKlass = FwDuelClasses.fromPlayerJob(widget.myJob);

    return Positioned.fill(
      child: ColoredBox(
        color: FwColors.canvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const FwEyebrow(
                  text: 'ACCEPTED · 수락',
                  color: FwColors.ok,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FwClassBadge(klass: myKlass, size: 56),
                    const SizedBox(width: 18),
                    _OkCheckIcon(),
                    const SizedBox(width: 18),
                    // 상대 클래스 정보가 클라이언트에 없으므로 중립(assassin) 으로 표기.
                    const FwClassBadge(
                      klass: FwDuelClass.assassin,
                      size: 56,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const FwSerifText(
                  text: '"받겠다."',
                  size: 28,
                  weight: FontWeight.w700,
                  color: FwColors.ink900,
                  letterSpacing: -0.3,
                ),
                const SizedBox(height: 6),
                FwMono(
                  text: '${widget.opponentName}이(가) 결투를 수락했습니다',
                  size: 11,
                  color: FwColors.ink500,
                ),
                const SizedBox(height: 22),
                // 추첨 스피너
                _GameLotterySpinner(spinner: _spinner),
                const SizedBox(height: 12),
                const FwMono(
                  text: '곧 시작합니다…',
                  size: 10,
                  color: FwColors.ink300,
                  letterSpacing: 1.2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OkCheckIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _OkCheckPainter(),
      ),
    );
  }
}

class _OkCheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bg = Paint()
      ..color = FwColors.ok.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size.width / 2, bg);

    final stroke = Paint()
      ..color = FwColors.ok
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // M12 20l5 5 11-11 (24x24 viewBox 기준 → scale)
    final scale = size.width / 40;
    final path = Path()
      ..moveTo(12 * scale, 20 * scale)
      ..lineTo(17 * scale, 25 * scale)
      ..lineTo(28 * scale, 14 * scale);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GameLotterySpinner extends StatelessWidget {
  const _GameLotterySpinner({required this.spinner});

  final AnimationController spinner;

  @override
  Widget build(BuildContext context) {
    return FwCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: spinner,
            builder: (_, __) {
              final n = _kSpinnerCandidates.length;
              final activeIndex = (spinner.value * n).floor() % n;
              final activeKlass = _kSpinnerCandidates[activeIndex];
              final activeName = FwDuelClasses.of(activeKlass).en.toUpperCase();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const FwMono(
                    text: 'SELECTING GAME…',
                    size: 10,
                    color: FwColors.ink500,
                    letterSpacing: 1.4,
                  ),
                  FwMono(
                    text: activeName,
                    size: 10,
                    color: FwColors.ink900,
                    weight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: spinner,
            builder: (_, __) {
              final n = _kSpinnerCandidates.length;
              final activeIndex = (spinner.value * n).floor() % n;
              return Row(
                children: [
                  for (int i = 0; i < _kSpinnerCandidates.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _SpinnerSlot(
                        klass: _kSpinnerCandidates[i],
                        active: i == activeIndex,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SpinnerSlot extends StatelessWidget {
  const _SpinnerSlot({required this.klass, required this.active});

  final FwDuelClass klass;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final data = FwDuelClasses.of(klass);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 36,
      decoration: BoxDecoration(
        color: active ? data.soft : FwColors.line2,
        borderRadius: BorderRadius.circular(FwRadii.sm),
        border: Border.all(
          color: active ? data.accent : FwColors.hairline,
          width: active ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Opacity(
        opacity: active ? 1.0 : 0.5,
        child: FwClassEmblem(
          kind: data.icon,
          color: active ? data.accent : FwColors.ink500,
          size: 16,
          stroke: 1.8,
        ),
      ),
    );
  }
}
