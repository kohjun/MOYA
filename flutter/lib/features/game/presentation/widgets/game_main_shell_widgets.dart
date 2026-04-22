import 'package:flutter/material.dart';

import '../../data/game_models.dart';
import 'ai_chat_panel.dart';

class GameMainTopHeader extends StatelessWidget {
  const GameMainTopHeader({
    super.key,
    required this.onBack,
    required this.onLeave,
    required this.role,
    required this.progress,
    required this.completed,
    required this.total,
    required this.showProgressBar,
    required this.isConnected,
  });

  final VoidCallback onBack;
  final VoidCallback onLeave;
  final GameRole? role;
  final double progress;
  final int completed;
  final int total;
  final bool showProgressBar;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final roleLabel = role == null ? null : (role!.isImpostor ? '임포스터' : '크루');
    final roleColor = role == null
        ? Colors.white
        : (role!.isImpostor
            ? const Color(0xFFDC2626)
            : const Color(0xFF0EA5E9));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    child: const Text(
                      '정보',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (roleLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: roleColor, width: 1),
                      ),
                      child: Text(
                        roleLabel,
                        style: TextStyle(
                          color: roleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (!isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '연결 끊김',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: onLeave,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: const Text(
                      '나가기',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (showProgressBar) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '미션 $completed / $total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22C55E),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GameMainRightFloatingControls extends StatelessWidget {
  const GameMainRightFloatingControls({
    super.key,
    required this.followMe,
    required this.onFollow,
    required this.onFit,
    required this.onMembers,
    required this.onAiChat,
  });

  final bool followMe;
  final VoidCallback onFollow;
  final VoidCallback onFit;
  final VoidCallback onMembers;
  final VoidCallback? onAiChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GameMainMiniTextButton(
          label: '내 위치',
          background:
              followMe ? const Color(0xFF2196F3) : Colors.black.withValues(alpha: 0.7),
          onTap: onFollow,
        ),
        const SizedBox(height: 8),
        GameMainMiniTextButton(
          label: '전체 보기',
          background: Colors.black.withValues(alpha: 0.7),
          onTap: onFit,
        ),
        const SizedBox(height: 8),
        GameMainMiniTextButton(
          label: '참여자',
          background: Colors.black.withValues(alpha: 0.7),
          onTap: onMembers,
        ),
        if (onAiChat != null) ...[
          const SizedBox(height: 8),
          GameMainMiniTextButton(
            label: 'AI 채팅',
            background: const Color(0xFF7C3AED).withValues(alpha: 0.9),
            onTap: onAiChat!,
          ),
        ],
      ],
    );
  }
}

class GameMainMiniTextButton extends StatelessWidget {
  const GameMainMiniTextButton({
    super.key,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class GameMainInfoChip extends StatelessWidget {
  const GameMainInfoChip({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GameMainVoiceChannelButton extends StatelessWidget {
  const GameMainVoiceChannelButton({
    super.key,
    required this.connected,
    required this.connecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final bg = connected ? const Color(0xFF16A34A) : const Color(0xFF2563EB);
    final label = connecting
        ? '연결 중...'
        : (connected ? '보이스 연결 해제' : '게임 보이스 채널 연결');

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: connecting ? null : (connected ? onDisconnect : onConnect),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connecting) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  connected ? Icons.mic_rounded : Icons.headset_mic_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameMainAiChatBar extends StatelessWidget {
  const GameMainAiChatBar({
    super.key,
    required this.sessionId,
    required this.isGhostMode,
    required this.expanded,
    required this.handleH,
    required this.contentH,
    required this.onToggle,
  });

  final String sessionId;
  final bool isGhostMode;
  final bool expanded;
  final double handleH;
  final double contentH;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final totalH = expanded ? handleH + contentH + bottomSafe : handleH + bottomSafe;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: totalH,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: SizedBox(
              height: handleH,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'AI 채팅',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    expanded ? '닫기' : '열기',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
          if (expanded)
            Expanded(
              child: AIChatPanel(
                sessionId: sessionId,
                isGhostMode: isGhostMode,
                height: contentH,
              ),
            )
          else
            SizedBox(height: bottomSafe),
        ],
      ),
    );
  }
}
