import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';
import 'duel_game_shared.dart';

// ─── 6. CouncilBiddingGame ───────────────────────────────────────────────────
// 전쟁 평의회 — 100 토큰을 3 라운드에 분할 입찰. 한 라운드에 단 한 번 일회성
// 배율 사용 가능 (myMultiplier, 1.0–2.0× 0.2 단위). BO3 (2 승 선취) 으로 승부.
//
// 서버 프로토콜: single-shot.
//   - server: pickMinigame → generateMinigameParams(council_bidding) → buildPublicMinigameParams 가
//     해당 player 의 myMultiplier 만 노출.
//   - client: 3 라운드 입찰을 로컬 버퍼링 후, 마지막 봉인에서 단일 onSubmit({rounds:[...]}).
//   - server: judgeMinigame 이 BO3 (2 승 시 조기 종료) + 100 초과시 비례 스케일링.

enum _CouncilPhase { chestClosed, chestOpened, bidding }

class CouncilBiddingGame extends StatefulWidget {
  const CouncilBiddingGame({
    super.key,
    required this.onSubmit,
    required this.myMultiplier,
    required this.myJob,
    this.totalRounds = 3,
    this.tokenPool = 100,
    this.multiplierLadder = const [1.0, 1.2, 1.4, 1.6, 1.8, 2.0],
  });

  final DuelSubmitCallback onSubmit;
  final double myMultiplier;
  final String? myJob;
  final int totalRounds;
  final int tokenPool;
  final List<double> multiplierLadder;

  @override
  State<CouncilBiddingGame> createState() => _CouncilBiddingGameState();
}

class _CouncilBiddingGameState extends State<CouncilBiddingGame>
    with SingleTickerProviderStateMixin {
  _CouncilPhase _phase = _CouncilPhase.chestClosed;
  int _currentRoundIndex = 0;
  int _bid = 0;
  bool _applyMultiplier = false;
  bool _multiplierConsumed = false;
  bool _submitted = false;
  final List<Map<String, dynamic>> _committed = [];

  late final AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  int get _tokensRemaining {
    var spent = 0;
    for (final round in _committed) {
      spent += round['bid'] as int;
    }
    return widget.tokenPool - spent;
  }

  String get _multiplierText {
    final m = widget.myMultiplier;
    return m == m.truncateToDouble()
        ? '${m.toStringAsFixed(1)}×'
        : '${m.toStringAsFixed(1)}×';
  }

  void _openChest() {
    if (_phase != _CouncilPhase.chestClosed) return;
    setState(() => _phase = _CouncilPhase.chestOpened);
    _revealController.forward(from: 0);
  }

  void _startBidding() {
    setState(() {
      _phase = _CouncilPhase.bidding;
      _currentRoundIndex = 0;
      _bid = 0;
      _applyMultiplier = false;
    });
  }

  void _setBid(int value) {
    setState(() => _bid = value.clamp(0, _tokensRemaining));
  }

  void _toggleMultiplier() {
    if (_multiplierConsumed) return;
    setState(() => _applyMultiplier = !_applyMultiplier);
  }

  void _confirmRound() {
    if (_submitted) return;
    final wasMultiplier = _applyMultiplier;
    _committed.add({'bid': _bid, 'applyMultiplier': wasMultiplier});

    if (_currentRoundIndex + 1 >= widget.totalRounds) {
      _submitted = true;
      widget.onSubmit({'rounds': List<Map<String, dynamic>>.from(_committed)});
      return;
    }

    setState(() {
      if (wasMultiplier) _multiplierConsumed = true;
      _currentRoundIndex++;
      _bid = 0;
      _applyMultiplier = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FwColors.canvasWarm,
      child: SafeArea(
        child: switch (_phase) {
          _CouncilPhase.chestClosed ||
          _CouncilPhase.chestOpened =>
            _buildItemPhase(),
          _CouncilPhase.bidding => _buildBidding(),
        },
      ),
    );
  }

  Widget _buildItemPhase() {
    final councilData = FwDuelClasses.of(FwDuelClass.council);
    final opened = _phase == _CouncilPhase.chestOpened;
    final ladder = widget.multiplierLadder;
    final myIdx = ladder.indexWhere(
      (m) => (m - widget.myMultiplier).abs() < 0.05,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FwPill(
                bg: FwColors.cardSurface,
                color: councilData.accent,
                prefix: FwClassEmblem(
                  kind: FwClassEmblemKind.banner,
                  size: 12,
                  color: councilData.accent,
                  stroke: 2,
                ),
                text: 'COUNCIL · 보급',
              ),
              FwMono(
                text: 'PHASE 0 / ${widget.totalRounds + 1}',
                size: 11,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                FwEyebrow(
                  text: 'SUPPLY DROP · 보급 상자',
                  color: councilData.accent,
                ),
                const SizedBox(height: 6),
                Text(
                  opened
                      ? '획득 · $_multiplierText 배율'
                      : '상자를 열어 일회성 배율을 획득',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: FwColors.ink900,
                  ),
                ),
                const SizedBox(height: 4),
                const FwMono(
                  text: '세 라운드 중 한 곳에 단 한 번만 사용 가능',
                  size: 10,
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: _revealController,
                builder: (_, __) => opened
                    ? _OpenedMultiplierCard(
                        accent: councilData.accent,
                        multiplierText: _multiplierText,
                        progress: _revealController.value,
                      )
                    : const _ClosedChest(),
              ),
            ),
          ),
          // multiplier ladder
          Wrap(
            spacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < ladder.length; i++)
                _LadderChip(
                  text: '${ladder[i].toStringAsFixed(1)}×',
                  highlighted: opened && i == myIdx,
                  accent: councilData.accent,
                ),
            ],
          ),
          const SizedBox(height: 6),
          const FwMono(
            text: '균등 추첨 · 0.2× 단위 6 단계',
            size: 10,
            textAlign: TextAlign.center,
            letterSpacing: 1.2,
          ),
          const SizedBox(height: 14),
          _CouncilCtaButton(
            label: opened ? '평의회를 시작한다 ›' : '상자를 연다',
            color: opened ? councilData.accent : FwColors.teamGold,
            onTap: opened ? _startBidding : _openChest,
          ),
        ],
      ),
    );
  }

  Widget _buildBidding() {
    final councilData = FwDuelClasses.of(FwDuelClass.council);
    final myKlass = FwDuelClasses.fromPlayerJob(widget.myJob);
    final remaining = _tokensRemaining;
    final round = _currentRoundIndex + 1;
    final effective = (_bid * (_applyMultiplier ? widget.myMultiplier : 1.0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // round bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FwPill(
                bg: FwColors.cardSurface,
                color: councilData.accent,
                prefix: FwClassEmblem(
                  kind: FwClassEmblemKind.banner,
                  size: 12,
                  color: councilData.accent,
                  stroke: 2,
                ),
                text: 'COUNCIL',
              ),
              Row(
                children: [
                  for (var i = 0; i < widget.totalRounds; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _RoundDot(
                        active: i <= _currentRoundIndex,
                        current: i == _currentRoundIndex,
                        accent: councilData.accent,
                      ),
                    ),
                  const SizedBox(width: 6),
                  FwMono(
                    text: 'R $round/${widget.totalRounds}',
                    size: 11,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // resources
          Row(
            children: [
              Expanded(
                child: _ResourceCard(
                  klass: myKlass,
                  label: '나',
                  tokens: remaining,
                  pool: widget.tokenPool,
                  multiplierBadge: _multiplierConsumed
                      ? '$_multiplierText 사용됨'
                      : '$_multiplierText 보유',
                  multiplierAvailable: !_multiplierConsumed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResourceCard(
                  klass: FwDuelClass.assassin,
                  label: '상대',
                  tokens: null,
                  pool: widget.tokenPool,
                  multiplierBadge: '?× 보유',
                  multiplierAvailable: false,
                  unknown: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FwCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FwEyebrow(
                        text: 'YOUR BID · 라운드 $round 투입',
                      ),
                      _MultiplierToggle(
                        text: '$_multiplierText 적용',
                        on: _applyMultiplier,
                        consumed: _multiplierConsumed,
                        onTap: _toggleMultiplier,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '$_bid',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const [
                              'RobotoMono',
                              'Menlo',
                              'Consolas',
                            ],
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            color: councilData.accent,
                            letterSpacing: -1,
                            height: 1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (_applyMultiplier && _bid > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FwMono(
                                text: '× ${widget.myMultiplier.toStringAsFixed(1)} = ',
                                size: 13,
                                color: FwColors.teamGold,
                                weight: FontWeight.w700,
                              ),
                              FwMono(
                                text: effective.toStringAsFixed(1),
                                size: 13,
                                color: FwColors.ink900,
                                weight: FontWeight.w700,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 2),
                        FwMono(
                          text: _applyMultiplier
                              ? '잔여 ${remaining - _bid} (배율은 잔여를 소모하지 않음)'
                              : '잔여 ${remaining - _bid}',
                          size: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BidSlider(
                    value: _bid,
                    max: remaining,
                    accent: councilData.accent,
                    onChanged: _setBid,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const FwMono(text: '0', size: 9.5),
                      FwMono(text: '$remaining (잔여)', size: 9.5),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _QuickChip(
                        label: '10',
                        onTap: () => _setBid(10),
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '25',
                        onTap: () => _setBid(25),
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: '50%',
                        onTap: () => _setBid((remaining * 0.5).floor()),
                      ),
                      const SizedBox(width: 6),
                      _QuickChip(
                        label: 'ALL-IN',
                        onTap: () => _setBid(remaining),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _CouncilCtaButton(
            label: '봉인하여 제출',
            color: FwColors.ink900,
            onTap: _confirmRound,
          ),
        ],
      ),
    );
  }
}

class _ClosedChest extends StatelessWidget {
  const _ClosedChest();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: 160,
        height: 140,
        child: CustomPaint(
          painter: _ClosedChestPainter(),
        ),
      ),
    );
  }
}

class _ClosedChestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 160×140 with fill=teamGold + stroke=ink900.
    final body = Paint()
      ..color = FwColors.teamGold
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = FwColors.ink900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // box
    const box = Rect.fromLTWH(20, 60, 120, 68);
    final boxRR = RRect.fromRectAndRadius(box, const Radius.circular(4));
    canvas.drawRRect(boxRR, body);
    canvas.drawRRect(boxRR, border);

    // lid (curved top)
    final lid = Path()
      ..moveTo(20, 60)
      ..quadraticBezierTo(80, 12, 140, 60)
      ..close();
    canvas.drawPath(lid, body);
    canvas.drawPath(lid, border);

    // lock
    const lock = Rect.fromLTWH(68, 76, 24, 34);
    canvas.drawRect(lock, Paint()..color = FwColors.ink900);
    canvas.drawCircle(
      const Offset(80, 93),
      4,
      Paint()..color = FwColors.teamGold,
    );

    // mid line
    canvas.drawLine(
      const Offset(20, 78),
      const Offset(140, 78),
      Paint()
        ..color = FwColors.ink900.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ClosedChestPainter oldDelegate) => false;
}

class _OpenedMultiplierCard extends StatelessWidget {
  const _OpenedMultiplierCard({
    required this.accent,
    required this.multiplierText,
    required this.progress,
  });

  final Color accent;
  final String multiplierText;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scale = 0.7 + 0.3 * progress.clamp(0.0, 1.0);
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            FwColors.teamGold.withValues(alpha: 0.2),
            FwColors.teamGold.withValues(alpha: 0),
          ],
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.27),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FwMono(
                text: 'MULTIPLIER',
                size: 10,
                color: Colors.white.withValues(alpha: 0.85),
                letterSpacing: 1.4,
              ),
              const SizedBox(height: 4),
              Text(
                multiplierText,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontFamilyFallback: ['Pretendard', 'Noto Serif KR'],
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              FwMono(
                text: 'ONE-USE BUFF',
                size: 9,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 1.2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LadderChip extends StatelessWidget {
  const _LadderChip({
    required this.text,
    required this.highlighted,
    required this.accent,
  });

  final String text;
  final bool highlighted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? accent : FwColors.cardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlighted ? accent : FwColors.hairline,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['RobotoMono', 'Menlo', 'Consolas'],
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: highlighted ? Colors.white : FwColors.ink500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RoundDot extends StatelessWidget {
  const _RoundDot({
    required this.active,
    required this.current,
    required this.accent,
  });

  final bool active;
  final bool current;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: current
            ? accent
            : (active ? accent.withValues(alpha: 0.4) : FwColors.line2),
        border: Border.all(color: current ? accent : FwColors.hairline),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.klass,
    required this.label,
    required this.tokens,
    required this.pool,
    required this.multiplierBadge,
    required this.multiplierAvailable,
    this.unknown = false,
  });

  final FwDuelClass klass;
  final String label;
  final int? tokens;
  final int pool;
  final String multiplierBadge;
  final bool multiplierAvailable;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final pct = tokens != null ? (tokens! / pool).clamp(0.0, 1.0) : 1.0;

    return FwCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FwClassBadge(klass: klass, size: 24),
              const SizedBox(width: 8),
              FwMono(text: label, size: 10),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                tokens?.toString() ?? '?',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['RobotoMono', 'Menlo', 'Consolas'],
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: FwColors.ink900,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              FwMono(text: '/$pool', size: 11),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: FwColors.line2,
              borderRadius: BorderRadius.circular(2),
            ),
            clipBehavior: Clip.antiAlias,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: ColoredBox(
                color: unknown ? FwColors.ink300 : FwColors.teamGold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: multiplierAvailable
                  ? FwColors.teamGold.withValues(alpha: 0.13)
                  : FwColors.line2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: multiplierAvailable
                    ? FwColors.teamGold
                    : FwColors.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  multiplierAvailable ? '✦' : '?',
                  style: TextStyle(
                    fontSize: 10,
                    color: multiplierAvailable
                        ? FwColors.teamGold
                        : FwColors.ink500,
                  ),
                ),
                const SizedBox(width: 4),
                FwMono(
                  text: multiplierBadge,
                  size: 10,
                  color: multiplierAvailable
                      ? FwColors.teamGold
                      : FwColors.ink500,
                  weight: FontWeight.w700,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiplierToggle extends StatelessWidget {
  const _MultiplierToggle({
    required this.text,
    required this.on,
    required this.consumed,
    required this.onTap,
  });

  final String text;
  final bool on;
  final bool consumed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = consumed;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: disabled
              ? FwColors.line2
              : (on ? FwColors.teamGold : FwColors.cardSurface),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: disabled
                ? FwColors.hairline
                : (on ? FwColors.teamGold : FwColors.teamGold.withValues(alpha: 0.55)),
          ),
          boxShadow: on && !disabled
              ? [
                  BoxShadow(
                    color: FwColors.teamGold.withValues(alpha: 0.33),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '✦',
              style: TextStyle(
                fontSize: 10,
                color: disabled
                    ? FwColors.ink500
                    : (on ? Colors.white : FwColors.teamGold),
              ),
            ),
            const SizedBox(width: 4),
            FwMono(
              text: text,
              size: 10,
              color: disabled
                  ? FwColors.ink500
                  : (on ? Colors.white : FwColors.teamGold),
              weight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ],
        ),
      ),
    );
  }
}

class _BidSlider extends StatelessWidget {
  const _BidSlider({
    required this.value,
    required this.max,
    required this.accent,
    required this.onChanged,
  });

  final int value;
  final int max;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxValid = max <= 0 ? 1 : max;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        activeTrackColor: accent,
        inactiveTrackColor: FwColors.line2,
        thumbColor: FwColors.cardSurface,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 11,
          elevation: 2,
        ),
        overlayColor: accent.withValues(alpha: 0.12),
      ),
      child: Slider(
        value: value.toDouble().clamp(0.0, maxValid.toDouble()),
        min: 0,
        max: maxValid.toDouble(),
        divisions: max <= 0 ? 1 : max,
        onChanged: max <= 0 ? null : (v) => onChanged(v.round()),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FwColors.line2,
            borderRadius: BorderRadius.circular(FwRadii.pill),
          ),
          child: FwMono(
            text: label,
            size: 11,
            color: FwColors.ink700,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CouncilCtaButton extends StatelessWidget {
  const _CouncilCtaButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
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
                fontSize: 15,
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
