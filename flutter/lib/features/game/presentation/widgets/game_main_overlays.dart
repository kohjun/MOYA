import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../session_info_screen.dart';

/// SOS 알림 배너. 상단 safe area 바로 아래에 위치한다.
class GameMainSosBanner extends StatelessWidget {
  const GameMainSosBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 72,
      left: 16,
      right: 16,
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color: Colors.red,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            'SOS 알림을 받았습니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// 사망 후 유령 모드일 때 표시되는 반투명 오버레이.
class GameMainGhostOverlay extends StatelessWidget {
  const GameMainGhostOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          color: Colors.black.withValues(alpha: 0.28),
          alignment: Alignment.center,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '사망 - 유령으로 관전 중',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 게임 종료 시 노출되는 전체화면 오버레이.
class GameMainGameOverOverlay extends StatelessWidget {
  const GameMainGameOverOverlay({
    super.key,
    required this.winnerId,
    required this.winnerName,
    required this.myUserId,
  });

  final String? winnerId;
  final String winnerName;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final isMyWin = winnerId != null && winnerId == myUserId;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMyWin ? '승리' : '게임 종료',
                style: TextStyle(
                  color: isMyWin ? const Color(0xFFFFD700) : Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                winnerName,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 24),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  final router = GoRouter.of(context);
                  if (router.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.home);
                  }
                },
                child: const Text('나가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 뒤로가기 버튼으로 열리는 세션 정보 오버레이.
class GameMainSessionInfoOverlay extends StatelessWidget {
  const GameMainSessionInfoOverlay({
    super.key,
    required this.sessionId,
    required this.gameType,
    required this.onClose,
  });

  final String sessionId;
  final String gameType;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    onPressed: onClose,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('닫기'),
                  ),
                ),
              ),
              Expanded(
                child: SessionInfoContent(
                  sessionId: sessionId,
                  gameType: gameType,
                  onClose: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 호스트 전용 "게임 시작" 플로팅 버튼.
class GameMainHostStartButton extends StatelessWidget {
  const GameMainHostStartButton({
    super.key,
    required this.bottomOffset,
    required this.onStart,
  });

  final double bottomOffset;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: bottomOffset,
      child: Material(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onStart,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Text(
              '게임 시작',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
