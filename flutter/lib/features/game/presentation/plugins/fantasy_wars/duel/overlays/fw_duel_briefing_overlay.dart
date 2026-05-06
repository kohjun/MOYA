import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';

// Briefing — 결투 룰 안내 + 3-2-1 카운트다운.
// 디자인 핸드오프 flow-screens.jsx 의 BriefScreen 이식.
// minigameType 으로 클래스/타이틀/룰 라인 정적 lookup.

class FwDuelBriefingOverlay extends StatelessWidget {
  const FwDuelBriefingOverlay({
    super.key,
    required this.minigameType,
    required this.remainingSec,
  });

  final String? minigameType;
  // 카운트다운 1..N. 0 이 되면 호출부가 sub-phase 를 play 로 전환한다.
  final int remainingSec;

  @override
  Widget build(BuildContext context) {
    final meta = _briefingMetaFor(minigameType);
    final klassData = FwDuelClasses.of(meta.klass);

    return Positioned.fill(
      child: ColoredBox(
        color: FwColors.canvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FwEyebrow(
                      text: 'BRIEFING · 룰 안내',
                      color: klassData.accent,
                    ),
                    FwPill(
                      text: '$remainingSec초 후 시작',
                      bg: FwColors.cardSurface,
                      color: FwColors.ink700,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FwClassBadge(klass: meta.klass, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FwMono(
                            text: klassData.en.toUpperCase(),
                            size: 10,
                            color: klassData.accent,
                            weight: FontWeight.w600,
                            letterSpacing: 1.4,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meta.title,
                            style: FwText.display,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FwCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FwEyebrow(text: 'RULES'),
                      const SizedBox(height: 10),
                      for (var i = 0; i < meta.rules.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                child: FwMono(
                                  text: (i + 1).toString().padLeft(2, '0'),
                                  size: 11,
                                  color: klassData.accent,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  meta.rules[i],
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 13,
                                    color: FwColors.ink700,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _CountdownDonut(
                      accent: klassData.accent,
                      remainingSec: remainingSec,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownDonut extends StatelessWidget {
  const _CountdownDonut({required this.accent, required this.remainingSec});

  final Color accent;
  final int remainingSec;

  @override
  Widget build(BuildContext context) {
    final clamped = remainingSec.clamp(0, 3);
    final progress = clamped / 3.0;
    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(180, 180),
            painter: _DonutPainter(accent: accent, progress: progress),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FwSerifText(
                text: '$clamped',
                size: 92,
                weight: FontWeight.w700,
                color: FwColors.ink900,
                letterSpacing: -2,
                height: 1.0,
              ),
              const SizedBox(height: 4),
              const FwMono(
                text: 'READY',
                size: 11,
                color: FwColors.ink500,
                letterSpacing: 1.4,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.accent, required this.progress});

  final Color accent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 84.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = FwColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, track);

    final fg = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.accent != accent;
}

class _BriefingMeta {
  const _BriefingMeta({
    required this.klass,
    required this.title,
    required this.rules,
  });

  final FwDuelClass klass;
  final String title;
  final List<String> rules;
}

_BriefingMeta _briefingMetaFor(String? minigameType) => switch (minigameType) {
      'precision' => const _BriefingMeta(
          klass: FwDuelClass.archer,
          title: '화살 사격',
          rules: [
            '표시된 표적을 정확히 조준하라',
            '명중점이 가운데에 가까울수록 우위',
            '오차가 작은 쪽이 승리',
          ],
        ),
      'rapid_tap' => const _BriefingMeta(
          klass: FwDuelClass.warrior,
          title: '검객 연타',
          rules: [
            '풀스크린 어디든 탭하면 검격',
            '제한 시간 내에 더 많이 휘두른 쪽 승리',
            '8 TPS 이상에서 광폭화 모드 진입',
          ],
        ),
      'speed_blackjack' => const _BriefingMeta(
          klass: FwDuelClass.mage,
          title: '룬 캐스팅',
          rules: [
            '룬 카드 합이 21에 가까울수록 승리',
            '21 초과 시 즉시 패배 (마나 폭주)',
            'Hit 으로 카드 추가, Stand 로 캐스팅 종료',
          ],
        ),
      'russian_roulette' => const _BriefingMeta(
          klass: FwDuelClass.priest,
          title: '러시안 룰렛',
          rules: [
            '6 개의 약실 중 단 1 개에 실탄',
            '두 사람이 번갈아 자신을 향해 방아쇠를 당김',
            '실탄이 발사된 쪽이 즉시 패배',
          ],
        ),
      'reaction_time' => const _BriefingMeta(
          klass: FwDuelClass.assassin,
          title: '선제 일격',
          rules: [
            '"WAIT" 화면에서 신호를 기다림',
            '"STRIKE!" 신호 후 화면을 가장 빨리 탭',
            '신호 전에 누르면 즉시 패배',
          ],
        ),
      'council_bidding' => const _BriefingMeta(
          klass: FwDuelClass.council,
          title: '전쟁 평의회',
          rules: [
            '100 토큰을 3 라운드에 나누어 입찰',
            '한 라운드에 단 한 번 일회성 배율을 사용 가능',
            '두 라운드 먼저 이긴 쪽이 승리 (BO3)',
          ],
        ),
      _ => const _BriefingMeta(
          klass: FwDuelClass.warrior,
          title: '결투',
          rules: [
            '미니게임 결과로 승부를 가른다',
            '제한 시간 내 제출 필요',
            '시간 초과 시 자동 패배 처리',
          ],
        ),
    };
