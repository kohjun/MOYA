import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/services/socket_service.dart';
import '../../../../providers/fantasy_wars_provider.dart';
import 'games/council_bidding_game.dart';
import 'games/duel_game_shared.dart';
import 'games/precision_game.dart';
import 'games/rapid_tap_game.dart';
import 'games/reaction_time_game.dart';
import 'games/russian_roulette_game.dart';
import 'games/speed_blackjack_game.dart';
import 'overlays/fw_duel_briefing_overlay.dart';
import 'overlays/fw_duel_vs_intro_overlay.dart';

enum _PrePlayPhase { vsIntro, briefing, play }

class FwDuelScreen extends ConsumerStatefulWidget {
  const FwDuelScreen({
    super.key,
    required this.sessionId,
    required this.duel,
    required this.myJob,
    required this.myName,
    required this.opponentName,
    required this.myId,
    required this.opponentId,
  });

  final String sessionId;
  final FwDuelState duel;
  final String? myJob;
  final String myName;
  final String opponentName;
  // 턴 기반 미니게임(RR 등) 에서 currentTurn 비교용. 프로토콜 수준에서 actor identifier
  // 를 server-side userId 와 일치시키기 위해 화면이 직접 들고 다닌다.
  final String myId;
  final String? opponentId;

  @override
  ConsumerState<FwDuelScreen> createState() => _FwDuelScreenState();
}

class _FwDuelScreenState extends ConsumerState<FwDuelScreen> {
  static const Duration _vsIntroDuration = Duration(seconds: 5);
  static const int _briefingTotalSec = 10;

  _PrePlayPhase _phase = _PrePlayPhase.vsIntro;
  Timer? _vsTimer;
  Timer? _briefTimer;
  int _briefRemain = _briefingTotalSec;
  bool _playStartedNotified = false;

  @override
  void initState() {
    super.initState();
    // 이미 제출 중이면 (재진입 등) pre-play 시퀀스 건너뛰고 바로 play.
    if (widget.duel.submitted) {
      _phase = _PrePlayPhase.play;
      _notifyPlayStartedOnce();
      return;
    }
    _vsTimer = Timer(_vsIntroDuration, _enterBriefing);
  }

  // VS intro + briefing 이 끝나 실제 미니게임 화면이 보이기 시작할 때 서버에 알린다.
  // 서버는 이 신호를 받고서야 본 게임 타이머(GAME_TIMEOUT_MS) 를 가동한다. 두 클라가
  // 모두 emit 해도 서버 쪽이 idempotent 하게 처리하므로 클라는 한 번만 보내면 된다.
  void _notifyPlayStartedOnce() {
    if (_playStartedNotified) return;
    final duelId = widget.duel.duelId;
    if (duelId == null || duelId.isEmpty) return;
    _playStartedNotified = true;
    unawaited(SocketService().sendDuelPlayStarted(duelId));
  }

  @override
  void dispose() {
    _vsTimer?.cancel();
    _briefTimer?.cancel();
    super.dispose();
  }

  void _enterBriefing() {
    if (!mounted) return;
    setState(() {
      _phase = _PrePlayPhase.briefing;
      _briefRemain = _briefingTotalSec;
    });
    _briefTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _briefRemain--);
      if (_briefRemain <= 0) {
        t.cancel();
        if (mounted) {
          setState(() => _phase = _PrePlayPhase.play);
          _notifyPlayStartedOnce();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_phase) {
      case _PrePlayPhase.vsIntro:
        body = FwDuelVsIntroOverlay(
          myJob: widget.myJob,
          myName: widget.myName,
          opponentName: widget.opponentName,
        );
        break;
      case _PrePlayPhase.briefing:
        body = FwDuelBriefingOverlay(
          minigameType: widget.duel.minigameType,
          remainingSec: _briefRemain,
        );
        break;
      case _PrePlayPhase.play:
        body = _buildPlay();
        break;
    }
    // FwDuelOverlay 가 inGame phase 에서 우리를 `Positioned.fill(ColoredBox(child: this))`
    // 안에 넣는다. 그 결과 우리의 vsIntro/briefing/play 가 반환하는 root `Positioned.fill`
    // 의 render parent 가 ColoredBox 가 되어 ParentDataWidget 오류가 발생한다.
    // 자체 Stack 으로 감싸 부모 종류와 무관하게 자식 Positioned 가 항상 Stack 직속이
    // 되도록 한다. fit: expand 로 부모의 제약을 그대로 전달.
    return Stack(
      fit: StackFit.expand,
      children: [body],
    );
  }

  Widget _buildPlay() {
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    final duel = widget.duel;
    final params = duel.minigameParams ?? const <String, dynamic>{};

    void submit(Map<String, dynamic> result) => notifier.submitMinigame(result);

    late final Widget game;
    switch (duel.minigameType) {
      case 'reaction_time':
        game = ReactionTimeGame(
          onSubmit: submit,
          signalDelayMs: (params['signalDelayMs'] as num?)?.toInt() ?? 1000,
        );
        break;
      case 'rapid_tap':
        game = RapidTapGame(
          onSubmit: submit,
          durationSec: (params['durationSec'] as num?)?.toInt() ?? 5,
        );
        break;
      case 'precision':
        game = PrecisionGame(
          onSubmit: submit,
          targets: _parseTargets(params['targets']),
        );
        break;
      case 'russian_roulette':
        // 턴 기반 동기화 — submit() 가 아닌 sendDuelAction({chamber,target}) 로 진행.
        // 서버 broadcast (fw:duel:state) 가 제공하는 state.currentTurn 을 myId 와 비교.
        game = RussianRouletteGame(
          sessionId: widget.sessionId,
          myId: widget.myId,
          opponentId: widget.opponentId,
        );
        break;
      case 'speed_blackjack':
        game = SpeedBlackjackGame(
          onSubmit: submit,
          initialHand: _parseIntList(params['hand'], const [10, 7]),
          drawPile: _parseIntList(params['drawPile'], const []),
          timeoutSec: (params['timeoutSec'] as num?)?.toInt() ?? 15,
        );
        break;
      case 'council_bidding':
        game = CouncilBiddingGame(
          onSubmit: submit,
          myJob: widget.myJob,
          myMultiplier: (params['myMultiplier'] as num?)?.toDouble() ?? 1.0,
          totalRounds: (params['rounds'] as num?)?.toInt() ?? 3,
          tokenPool: (params['tokenPool'] as num?)?.toInt() ?? 100,
          multiplierLadder: _parseDoubleList(
            params['multiplierLadder'],
            const [1.0, 1.2, 1.4, 1.6, 1.8, 2.0],
          ),
        );
        break;
      default:
        game = _UnknownMinigame(
          type: duel.minigameType ?? '?',
          onSubmit: submit,
        );
        break;
    }

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(child: game),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sports_mma,
                        color: Colors.purpleAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '대결 ${_minigameLabel(duel.minigameType)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (!duel.submitted)
                        GestureDetector(
                          onTap: notifier.cancelDuel,
                          child: const Text(
                            '포기',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (duel.submitted)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          '결과 대기 중...',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<int> _parseIntList(Object? raw, List<int> fallback) {
    return (raw as List?)
            ?.map((value) => (value as num).toInt())
            .toList(growable: false) ??
        fallback;
  }

  static List<double> _parseDoubleList(Object? raw, List<double> fallback) {
    return (raw as List?)
            ?.map((value) => (value as num).toDouble())
            .toList(growable: false) ??
        fallback;
  }

  static List<Offset> _parseTargets(Object? raw) {
    final parsed = (raw as List?)
            ?.whereType<Map>()
            .map(
              (target) => Offset(
                (((target['x'] as num?)?.toDouble() ?? 0.5).clamp(0.05, 0.95))
                    .toDouble(),
                (((target['y'] as num?)?.toDouble() ?? 0.5).clamp(0.08, 0.92))
                    .toDouble(),
              ),
            )
            .toList(growable: false) ??
        const <Offset>[];

    if (parsed.isNotEmpty) {
      return parsed;
    }

    return const [
      Offset(0.25, 0.28),
      Offset(0.72, 0.46),
      Offset(0.42, 0.72),
    ];
  }

  static String _minigameLabel(String? type) => switch (type) {
        'reaction_time' => '반응 속도',
        'rapid_tap' => '연타',
        'precision' => '정밀 타격',
        'russian_roulette' => '러시안 룰렛',
        'speed_blackjack' => '스피드 블랙잭',
        'council_bidding' => '평의회',
        _ => type ?? '?',
      };
}

class _UnknownMinigame extends StatelessWidget {
  const _UnknownMinigame({
    required this.type,
    required this.onSubmit,
  });

  final String type;
  final DuelSubmitCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F0A2A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '알 수 없는 미니게임: $type',
              style: const TextStyle(color: Colors.redAccent, fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => onSubmit({'reactionMs': 9999}),
              child: const Text('기권 처리'),
            ),
          ],
        ),
      ),
    );
  }
}
