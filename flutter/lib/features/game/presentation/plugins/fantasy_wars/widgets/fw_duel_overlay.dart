import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../providers/fantasy_wars_provider.dart';
import '../duel/overlays/fw_duel_accepted_overlay.dart';
import '../duel/overlays/fw_duel_request_overlay.dart';
import '../duel/overlays/fw_duel_result_overlay.dart';
import '../fantasy_wars_design_tokens.dart';

enum FwDuelPhase {
  none,
  pendingSent,
  pendingReceived,
  accepted,
  inGame,
  result,
}

// ─── Layer 8: 결투 오버레이 (4-페이즈 통합) ─────────────────────────────
class FwDuelOverlay extends StatefulWidget {
  const FwDuelOverlay({
    super.key,
    required this.phase,
    required this.opponentLabel,
    required this.duelResult,
    required this.minigameType,
    required this.myId,
    required this.myJob,
    required this.myName,
    required this.onCancel,
    required this.onAccept,
    required this.onReject,
    required this.onCloseResult,
    required this.miniGame,
  });

  final FwDuelPhase phase;
  final String? opponentLabel;
  final FwDuelResult? duelResult;
  final String? minigameType;
  final String? myId;
  final String? myJob;
  final String myName;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCloseResult;
  final Widget? miniGame;

  @override
  State<FwDuelOverlay> createState() => _FwDuelOverlayState();
}

class _FwDuelOverlayState extends State<FwDuelOverlay> {
  Timer? _autoRejectTimer;
  Timer? _sentElapsedTimer;
  int _autoRejectRemain = 10;
  int _sentElapsed = 0;

  @override
  void initState() {
    super.initState();
    _restartTimers();
  }

  @override
  void didUpdateWidget(covariant FwDuelOverlay old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) {
      _restartTimers();
    }
  }

  void _restartTimers() {
    _autoRejectTimer?.cancel();
    _sentElapsedTimer?.cancel();
    if (widget.phase == FwDuelPhase.pendingReceived) {
      _autoRejectRemain = 10;
      // 진입 햅틱: 결투 신청 도착을 손끝으로도 인지하게 한다.
      HapticFeedback.lightImpact();
      _autoRejectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _autoRejectRemain--);
        // 잔여 3초 임계: 자동 거절 임박을 한 번 더 알린다 (중강도 1회).
        if (_autoRejectRemain == 3) {
          HapticFeedback.mediumImpact();
        }
        if (_autoRejectRemain <= 0) {
          t.cancel();
          widget.onReject();
        }
      });
    }
    if (widget.phase == FwDuelPhase.pendingSent) {
      _sentElapsed = 0;
      _sentElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _sentElapsed++);
      });
    }
    // result phase 는 사용자가 결과(승/패, 사유, HP/방어막/처형/사망 효과) 를 충분히
    // 읽을 수 있도록 자동 닫지 않는다. 결과 화면 안의 "전장으로" CTA 만 종료 경로로
    // 둔다. (3초 자동 dismiss 는 high-pressure 흐름에서 정보 누락의 원인이었음.)
  }

  @override
  void dispose() {
    _autoRejectTimer?.cancel();
    _sentElapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 진입 플로우 페이즈(편지+봉랍/추첨 스피너) 는 자체 canvasWarm 풀스크린 배경.
    // inGame/result 는 기존 검은 dimmer 유지 (미니게임/결과 모달).
    switch (widget.phase) {
      case FwDuelPhase.pendingSent:
        return FwDuelRequestOverlay(
          mode: FwDuelRequestMode.sent,
          myJob: widget.myJob,
          myName: widget.myName,
          opponentName: widget.opponentLabel ?? '상대',
          secondsRemaining: _sentElapsed,
          onCancel: widget.onCancel,
        );
      case FwDuelPhase.pendingReceived:
        return FwDuelRequestOverlay(
          mode: FwDuelRequestMode.received,
          myJob: widget.myJob,
          myName: widget.myName,
          opponentName: widget.opponentLabel ?? '상대',
          secondsRemaining: _autoRejectRemain,
          onAccept: widget.onAccept,
          onReject: widget.onReject,
        );
      case FwDuelPhase.accepted:
        return FwDuelAcceptedOverlay(
          myJob: widget.myJob,
          opponentName: widget.opponentLabel ?? '상대',
        );
      case FwDuelPhase.result:
        final r = widget.duelResult ?? FwDuelResult.invalidated();
        return FwDuelOutcomeOverlay(
          result: r,
          minigameType: widget.minigameType,
          myJob: widget.myJob,
          myId: widget.myId,
          myName: widget.myName,
          opponentName: widget.opponentLabel ?? '상대',
          onBackToBattlefield: widget.onCloseResult,
        );
      case FwDuelPhase.inGame:
      case FwDuelPhase.none:
        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.78),
            child: switch (widget.phase) {
              FwDuelPhase.inGame => _buildInGame(),
              _ => const SizedBox.shrink(),
            },
          ),
        );
    }
  }

  Widget _buildInGame() {
    return widget.miniGame ??
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '결투 진행 중',
                style: GoogleFonts.notoSansKr(
                  color: FwColors.goldStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                    color: FwColors.goldStrong, strokeWidth: 3),
              ),
            ],
          ),
        );
  }
}
