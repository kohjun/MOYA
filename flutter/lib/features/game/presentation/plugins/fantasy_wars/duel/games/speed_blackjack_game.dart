import 'dart:async';

import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';
import 'duel_game_shared.dart';

class SpeedBlackjackGame extends StatefulWidget {
  const SpeedBlackjackGame({
    super.key,
    required this.onSubmit,
    required this.initialHand,
    required this.drawPile,
    this.timeoutSec = 15,
  });

  final DuelSubmitCallback onSubmit;
  final List<int> initialHand;
  final List<int> drawPile;
  final int timeoutSec;

  @override
  State<SpeedBlackjackGame> createState() => _SpeedBlackjackGameState();
}

class _SpeedBlackjackGameState extends State<SpeedBlackjackGame>
    with SingleTickerProviderStateMixin {
  late List<int> _hand;
  late int _remainingSec;
  int _hitCount = 0;
  bool _submitted = false;
  bool _showNewCard = false;

  Timer? _timer;
  late final AnimationController _bustAnimationController;
  late final Animation<double> _bustAnimation;

  int get _score {
    var total = _hand.fold<int>(0, (sum, card) => sum + card);
    var aces = _hand.where((card) => card == 11).length;
    while (total > 21 && aces > 0) {
      total -= 10;
      aces -= 1;
    }
    return total;
  }

  bool get _isBust => _score > 21;

  @override
  void initState() {
    super.initState();
    _hand = List<int>.from(widget.initialHand);
    _remainingSec = widget.timeoutSec;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (_remainingSec <= 1) {
        _stand();
        return;
      }
      setState(() {
        _remainingSec -= 1;
      });
    });
    _bustAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _bustAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(_bustAnimationController);
  }

  void _hit() {
    if (_submitted || _hitCount >= widget.drawPile.length) {
      _stand();
      return;
    }

    setState(() {
      _hand.add(widget.drawPile[_hitCount]);
      _hitCount += 1;
      _showNewCard = true;
    });

    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() {
          _showNewCard = false;
        });
      }
    });

    if (_isBust) {
      _bustAnimationController.forward(from: 0);
      Future<void>.delayed(const Duration(milliseconds: 400), _stand);
    }
  }

  void _stand() {
    if (_submitted) {
      return;
    }

    _submitted = true;
    _timer?.cancel();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        widget.onSubmit({'hitCount': _hitCount});
      }
    });
    setState(() {});
  }

  String _cardLabel(int value) => value == 11 ? 'A' : '$value';

  @override
  void dispose() {
    _timer?.cancel();
    _bustAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = FwDuelClasses.of(FwDuelClass.mage).accent;
    final soft = FwDuelClasses.of(FwDuelClass.mage).soft;
    return AnimatedBuilder(
      animation: _bustAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(_bustAnimation.value, 0),
        child: child,
      ),
      child: ColoredBox(
        color: const Color(0xFFECEEF5),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FwPill(
                      text: 'MAGE',
                      bg: FwColors.cardSurface,
                      color: FwColors.ink700,
                      prefix: FwClassEmblem(
                        kind: FwClassEmblemKind.rune,
                        color: accent,
                        size: 12,
                        stroke: 2,
                      ),
                    ),
                    Row(
                      children: [
                        FwMono(
                          text: '${_remainingSec}s',
                          size: 11,
                          color: _remainingSec <= 5
                              ? FwColors.danger
                              : FwColors.ink500,
                          weight: _remainingSec <= 5
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Deck circle + DECK label + 합산.
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: FwColors.cardSurface,
                    borderRadius: BorderRadius.circular(FwRadii.md),
                    border: Border.all(color: FwColors.hairline),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: soft,
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: FwClassEmblem(
                          kind: FwClassEmblemKind.rune,
                          color: accent,
                          size: 36,
                          stroke: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const FwMono(
                        text: 'DECK · RUNE',
                        size: 10,
                        color: FwColors.ink500,
                        letterSpacing: 1.2,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              const FwMono(
                                text: '나',
                                size: 9.5,
                                color: FwColors.ink500,
                              ),
                              Text(
                                '$_score',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: const [
                                    'RobotoMono',
                                    'Menlo',
                                    'Consolas',
                                  ],
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: _isBust
                                      ? FwColors.danger
                                      : FwColors.ink900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          Container(width: 1, height: 36, color: FwColors.hairline),
                          const SizedBox(width: 24),
                          const Column(
                            children: [
                              FwMono(
                                text: '상대',
                                size: 9.5,
                                color: FwColors.ink500,
                              ),
                              Text(
                                '??',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: [
                                    'RobotoMono',
                                    'Menlo',
                                    'Consolas',
                                  ],
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: FwColors.ink500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        for (int index = 0; index < _hand.length; index += 1)
                          _RuneCard(
                            value: _cardLabel(_hand[index]),
                            accent: accent,
                            highlighted:
                                index == _hand.length - 1 && _showNewCard,
                          ),
                      ],
                    ),
                  ),
                ),
                if (_isBust)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: FwMono(
                      text: 'BUST · 마나 폭주',
                      size: 12,
                      color: FwColors.danger,
                      weight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                if (!_submitted)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _hit,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accent,
                              side: BorderSide(color: accent),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(FwRadii.md),
                              ),
                            ),
                            child: const Text(
                              '마나 추가 (Hit)',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _stand,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(FwRadii.md),
                              ),
                            ),
                            child: const Text(
                              '캐스팅 완료',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  const FwMono(
                    text: '결과를 전송하는 중',
                    size: 12,
                    color: FwColors.ink500,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuneCard extends StatelessWidget {
  const _RuneCard({
    required this.value,
    required this.accent,
    required this.highlighted,
  });

  final String value;
  final Color accent;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 64,
      decoration: BoxDecoration(
        color: FwColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: highlighted
                ? accent.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: highlighted ? 12 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 4,
            child: FwMono(
              text: '♦',
              size: 8,
              color: accent,
            ),
          ),
          Center(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'serif',
                fontFamilyFallback: const ['Pretendard', 'Noto Serif KR'],
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
