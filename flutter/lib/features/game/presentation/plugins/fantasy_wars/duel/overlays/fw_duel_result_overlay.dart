import 'package:flutter/material.dart';

import '../../../../../providers/fantasy_wars_provider.dart';
import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';

// Result — 결투 결과 화면.
// 디자인 핸드오프 flow-screens.jsx 의 ResultScreen 이식.
// - canvas bg, 회전된 VICTORY/DEFEAT 스탬프, 2 열 통계 그리드, 단일 CTA(전장으로 돌아가기).
// - 보상/재대결 버튼 없음 (디자인 결정사항).
// - 서버가 게임별 세부 통계를 제공하지 않으므로 통계 그리드는 reason/effects 기반 요약만 표시.

class FwDuelOutcomeOverlay extends StatelessWidget {
  const FwDuelOutcomeOverlay({
    super.key,
    required this.result,
    required this.minigameType,
    required this.myJob,
    required this.myId,
    required this.myName,
    required this.opponentName,
    required this.onBackToBattlefield,
  });

  final FwDuelResult result;
  final String? minigameType;
  final String? myJob;
  final String? myId;
  final String myName;
  final String opponentName;
  final VoidCallback onBackToBattlefield;

  @override
  Widget build(BuildContext context) {
    final isInvalidated = result.reason == 'invalidated';
    final isDraw = result.isDraw;
    final isWin = !isDraw && !isInvalidated && result.winnerId == myId;
    final stampColor = FwDuelClasses.resultAccent(won: isWin);

    final myKlass = FwDuelClasses.fromPlayerJob(myJob);
    // 미니게임 컨셉 클래스 — 결과 카드 액센트.
    final gameKlass = FwDuelClasses.fromMinigameType(minigameType) ?? myKlass;
    final gameData = FwDuelClasses.of(gameKlass);

    final eyebrowText = isInvalidated
        ? 'RESULT · 무효'
        : isDraw
            ? 'RESULT · 무승부'
            : (isWin ? 'RESULT · 승리' : 'RESULT · 패배');
    final eyebrowColor = isInvalidated
        ? FwColors.ink500
        : isDraw
            ? FwColors.ink500
            : (isWin ? FwColors.ok : FwColors.danger);

    final headline = _headlineFor(minigameType, isWin: isWin, isDraw: isDraw);

    return Positioned.fill(
      child: ColoredBox(
        color: FwColors.canvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FwEyebrow(text: eyebrowText, color: eyebrowColor),
                    const FwMono(
                      text: 'BEST OF 1',
                      size: 10,
                      color: FwColors.ink500,
                      letterSpacing: 0.6,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ResultCard(
                  isWin: isWin,
                  isDraw: isDraw,
                  isInvalidated: isInvalidated,
                  stampColor: stampColor,
                  headline: headline,
                  result: result,
                  myKlass: myKlass,
                  gameAccent: gameData.accent,
                  gameSoft: gameData.soft,
                  myName: myName,
                  opponentName: opponentName,
                ),
                const Spacer(),
                _BackButton(onTap: onBackToBattlefield),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.isWin,
    required this.isDraw,
    required this.isInvalidated,
    required this.stampColor,
    required this.headline,
    required this.result,
    required this.myKlass,
    required this.gameAccent,
    required this.gameSoft,
    required this.myName,
    required this.opponentName,
  });

  final bool isWin;
  final bool isDraw;
  final bool isInvalidated;
  final Color stampColor;
  final String headline;
  final FwDuelResult result;
  final FwDuelClass myKlass;
  final Color gameAccent;
  final Color gameSoft;
  final String myName;
  final String opponentName;

  @override
  Widget build(BuildContext context) {
    final stampLabel = isInvalidated
        ? 'INVALID'
        : isDraw
            ? 'DRAW'
            : (isWin ? 'VICTORY' : 'DEFEAT');
    final resultLabelKr = isInvalidated
        ? '무효'
        : isDraw
            ? '무승부'
            : (isWin ? '승리' : '패배');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: FwColors.cardSurface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: FwShadows.card,
            border: Border.all(color: const Color(0x0D1F2630)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FwMono(
                text: resultLabelKr,
                size: 11,
                weight: FontWeight.w700,
                color: stampColor,
                letterSpacing: 1.6,
                uppercase: true,
              ),
              const SizedBox(height: 6),
              Text(
                headline,
                style: FwText.display.copyWith(
                  fontSize: 22,
                  letterSpacing: -0.4,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StatColumn(
                      side: '나 · $myName',
                      klass: myKlass,
                      bg: isWin ? gameSoft : FwColors.line2,
                      rows: _myRows(result, isWin: isWin),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatColumn(
                      side: '상대 · $opponentName',
                      // 상대 클래스 정보 없음 → assassin(mono) placeholder.
                      klass: FwDuelClass.assassin,
                      bg: FwColors.line2,
                      opacity: isWin ? 0.7 : 1.0,
                      rows: _theirRows(result, isWin: isWin),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 회전된 VICTORY/DEFEAT 스탬프 (8deg)
        Positioned(
          top: -16,
          right: -6,
          child: Transform.rotate(
            angle: 8 * 3.1415926535 / 180,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: FwColors.cardSurface,
                borderRadius: BorderRadius.circular(FwRadii.pill),
                border: Border.all(color: stampColor, width: 2.5),
              ),
              child: FwSerifText(
                text: stampLabel,
                size: 20,
                weight: FontWeight.w700,
                color: stampColor,
                letterSpacing: 1.5,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<_StatRow> _myRows(FwDuelResult r, {required bool isWin}) {
    final rows = <_StatRow>[
      _StatRow(label: '결과', value: isWin ? '승리' : (r.isDraw ? '무승부' : '패배')),
      _StatRow(label: '판정', value: _reasonLabel(r.reason)),
    ];
    if (r.shieldAbsorbed) {
      rows.add(const _StatRow(label: '효과', value: '보호막 흡수'));
    }
    if (r.executionTriggered) {
      rows.add(const _StatRow(label: '효과', value: '처형 발동'));
    }
    if (r.warriorHpResult != null) {
      rows.add(_StatRow(label: '전사 목숨', value: '${r.warriorHpResult}'));
    }
    return rows;
  }

  List<_StatRow> _theirRows(FwDuelResult r, {required bool isWin}) {
    return <_StatRow>[
      _StatRow(label: '결과', value: isWin ? '패배' : (r.isDraw ? '무승부' : '승리')),
      _StatRow(label: '판정', value: _reasonLabel(r.reason)),
    ];
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.side,
    required this.klass,
    required this.bg,
    required this.rows,
    this.opacity = 1.0,
  });

  final String side;
  final FwDuelClass klass;
  final Color bg;
  final List<_StatRow> rows;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(FwRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FwClassBadge(klass: klass, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: FwMono(
                    text: side,
                    size: 10,
                    color: FwColors.ink700,
                    weight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FwMono(text: row.label, size: 10, color: FwColors.ink500),
                    Flexible(
                      child: FwMono(
                        text: row.value,
                        size: 11,
                        weight: FontWeight.w600,
                        color: FwColors.ink900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: FwColors.cardSurface,
        borderRadius: BorderRadius.circular(FwRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(FwRadii.md),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FwRadii.md),
              border: Border.all(color: FwColors.hairline),
            ),
            child: const Text(
              '전장으로 돌아가기',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FwColors.ink900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _reasonLabel(String reason) => switch (reason) {
      'minigame' => '미니게임 판정',
      'opponent_timeout' => '상대 시간 초과',
      'both_timed_out' => '양측 시간 초과',
      'invalidated' => '결투 무효',
      'faster_reaction' => '반응 속도 승리',
      'faster_tap' => '연타 승리',
      'better_precision' => '정밀도 승리',
      'higher_hand' => '블랙잭 승리',
      'bullet_hit' => '룰렛 판정',
      'council_majority' => '평의회 다수결',
      'council_draw' => '평의회 무승부',
      _ => reason,
    };

String _headlineFor(
  String? minigameType, {
  required bool isWin,
  required bool isDraw,
}) {
  if (isDraw) return '판정이 갈리지 않았다';
  return switch (minigameType) {
    'precision' =>
      isWin ? '정확한 조준이 표적을 꿰뚫었다' : '조준이 빗나갔다',
    'rapid_tap' => isWin ? '검격으로 압도했다' : '검의 속도에서 밀렸다',
    'speed_blackjack' => isWin ? '룬의 합이 운명을 갈랐다' : '마나가 폭주하여 패배했다',
    'russian_roulette' => isWin ? '운명이 비켜갔다' : '실탄이 발사되었다',
    'reaction_time' => isWin ? '그림자보다 빠르게 베었다' : '반응이 한 박자 늦었다',
    'council_bidding' => isWin ? '평의회의 다수가 손을 들었다' : '의장석이 상대에게 돌아갔다',
    _ => isWin ? '승리했다' : '패배했다',
  };
}
