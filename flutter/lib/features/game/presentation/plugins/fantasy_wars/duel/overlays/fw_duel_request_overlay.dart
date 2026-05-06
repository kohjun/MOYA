import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';

// DuelRequest — 결투 신청 편지 디자인.
// 디자인 핸드오프 flow-screens.jsx 의 DuelRequestScreen 을 Flutter 로 이식.
// - sent  모드: 신청자 측. "응답 대기 중…" + 취소 버튼.
// - received 모드: 수신자 측. "결투 신청을 받았다" + 거절/수락 버튼.
// 두 모드는 같은 편지 카드 디자인을 공유한다.
//
// 풀스크린 인터셉트 (canvasWarm 배경) — FwDuelOverlay 의 외곽
// 검은 dimmer 대신 자체 배경을 그린다.

enum FwDuelRequestMode { sent, received }

class FwDuelRequestOverlay extends StatelessWidget {
  const FwDuelRequestOverlay({
    super.key,
    required this.mode,
    required this.myJob,
    required this.myName,
    required this.opponentName,
    required this.secondsRemaining,
    this.onCancel,
    this.onAccept,
    this.onReject,
  });

  final FwDuelRequestMode mode;
  final String? myJob;
  final String myName;
  final String opponentName;
  final int secondsRemaining;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final myKlass = FwDuelClasses.fromPlayerJob(myJob);

    return Positioned.fill(
      child: ColoredBox(
        color: FwColors.canvasWarm,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FwEyebrow(
                  text: mode == FwDuelRequestMode.sent
                      ? 'DUEL REQUEST · 결투 신청'
                      : 'CHALLENGE RECEIVED · 결투 도전',
                  color: FwColors.danger,
                ),
                const SizedBox(height: 4),
                Text(
                  mode == FwDuelRequestMode.sent
                      ? '상대의 응답을 기다리는 중…'
                      : '결투 신청이 도착했습니다',
                  style: FwText.display,
                ),
                const SizedBox(height: 18),
                _LetterCard(
                  myKlass: myKlass,
                  myName: myName,
                  opponentName: opponentName,
                ),
                const Spacer(),
                if (mode == FwDuelRequestMode.sent) ...[
                  const _BouncingDots(),
                  const SizedBox(height: 10),
                  FwMono(
                    text:
                        '응답 대기 · ${secondsRemaining.toString().padLeft(2, '0')}초',
                    size: 11,
                    color: FwColors.ink500,
                    letterSpacing: 0.4,
                  ),
                  const SizedBox(height: 18),
                  _OutlineButton(
                    label: '신청 취소',
                    onTap: onCancel,
                  ),
                ] else ...[
                  // 잔여 3초 이하에서 글자 크기 ↑ + opacity pulse 로 임박감을 시각화.
                  // 햅틱은 FwDuelOverlay 의 _restartTimers 카운트다운에서 동기 트리거.
                  _UrgentCountdown(
                    secondsRemaining: secondsRemaining,
                    urgent: secondsRemaining <= 3,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SolidButton(
                          label: '거절',
                          color: FwColors.danger,
                          onTap: onReject,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _SolidButton(
                          label: '결투 수락',
                          color: FwColors.ok,
                          onTap: onAccept,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LetterCard extends StatelessWidget {
  const _LetterCard({
    required this.myKlass,
    required this.myName,
    required this.opponentName,
  });

  final FwDuelClass myKlass;
  final String myName;
  final String opponentName;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FwCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FROM ↔ TO 헤더
              Row(
                children: [
                  FwClassBadge(klass: myKlass, size: 32),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FwMono(
                        text: 'FROM',
                        size: 9.5,
                        color: FwColors.ink500,
                        letterSpacing: 1.2,
                      ),
                      Text(
                        myName,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: FwColors.ink900,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        height: 1,
                        color: FwColors.hairline,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const FwMono(
                        text: 'TO',
                        size: 9.5,
                        color: FwColors.ink500,
                        letterSpacing: 1.2,
                      ),
                      Text(
                        opponentName,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: FwColors.ink900,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 이탤릭 세리프 대사
              const FwSerifText(
                text: '"정정당당, 단판 승부.\n그대의 검을 받아주길."',
                size: 17,
                weight: FontWeight.w600,
                italic: true,
                color: FwColors.ink700,
                height: 1.5,
                letterSpacing: -0.2,
              ),
              const SizedBox(height: 14),
              // 방식 표시
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: FwColors.line2,
                  borderRadius: BorderRadius.circular(FwRadii.sm),
                ),
                // 카운트는 FwDuelClasses.minigamePoolSize 에서 derive — 추첨 스피너의
                // 후보 수와 항상 일치하도록 단일 source-of-truth 참조.
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const FwMono(
                      text: '방식',
                      size: 10,
                      color: FwColors.ink500,
                    ),
                    FwMono(
                      text: 'RANDOM · ${FwDuelClasses.minigamePoolSize} GAMES',
                      size: 10,
                      color: FwColors.ink900,
                      weight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 봉랍 씰 (-10 top, 18 right, 36×36 원, danger 컬러, sword emblem, -8deg)
        Positioned(
          top: -10,
          right: 18,
          child: Transform.rotate(
            angle: -8 * 3.1415926535 / 180,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: FwColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: FwColors.danger.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const FwClassEmblem(
                kind: FwClassEmblemKind.sword,
                color: Colors.white,
                size: 18,
                stroke: 2.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 1.2s 마다 3 dot 가 순차 bounce. translateY 0 → -6, opacity .3 → 1.
class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // 0 → 0.18s 간격으로 시프트.
            final delay = i * 0.15;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            // 0..0.4 구간에서 -6px / opacity 1, 그 외 0px / opacity 0.3
            final lifted = t < 0.4 ? (t / 0.4) : 1 - ((t - 0.4) / 0.6);
            final dy = -6 * lifted.clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * lifted.clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                offset: Offset(0, dy.toDouble()),
                child: Opacity(
                  opacity: opacity.toDouble(),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: FwColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// 자동 거절 카운트다운 텍스트. urgent (≤3초) 일 때 크기/letterSpacing 을 키우고
// 600ms reverse pulse opacity 로 점멸 감을 준다. 평상시엔 정적 FwMono 와 동일.
class _UrgentCountdown extends StatefulWidget {
  const _UrgentCountdown({
    required this.secondsRemaining,
    required this.urgent,
  });

  final int secondsRemaining;
  final bool urgent;

  @override
  State<_UrgentCountdown> createState() => _UrgentCountdownState();
}

class _UrgentCountdownState extends State<_UrgentCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _UrgentCountdown old) {
    super.didUpdateWidget(old);
    if (old.urgent != widget.urgent) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.urgent) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final urgent = widget.urgent;
        final opacity = urgent ? (1.0 - 0.55 * _pulse.value) : 1.0;
        return Opacity(
          opacity: opacity,
          child: FwMono(
            text: '${widget.secondsRemaining}초 후 자동 거절',
            size: urgent ? 14 : 11,
            color: FwColors.danger,
            weight: FontWeight.w700,
            letterSpacing: urgent ? 0.6 : 0.4,
          ),
        );
      },
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: FwColors.cardSurface,
        borderRadius: BorderRadius.circular(FwRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(FwRadii.md),
          onTap: onTap,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FwRadii.md),
              border: Border.all(color: FwColors.hairline),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: FwColors.ink700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SolidButton extends StatelessWidget {
  const _SolidButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(FwRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(FwRadii.md),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
