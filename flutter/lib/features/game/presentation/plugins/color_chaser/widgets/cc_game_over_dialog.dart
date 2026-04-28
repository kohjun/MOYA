// 게임 종료 다이얼로그.
// 승자 정보 + 본인 결과 + 전체 스코어보드 (정체 공개).

import 'package:flutter/material.dart';

import '../color_chaser_models.dart';

class CcGameOverDialog extends StatelessWidget {
  const CcGameOverDialog({
    super.key,
    required this.win,
    required this.scoreboard,
    required this.myUserId,
    required this.onLeave,
  });

  final CcWinCondition win;
  final List<CcScoreEntry> scoreboard;
  final String? myUserId;
  final VoidCallback onLeave;

  Color _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.grey;
    return Color(0xFF000000 | value);
  }

  String _reasonLabel() {
    switch (win.reason) {
      case 'last_survivor':
        return '최후의 1인 생존';
      case 'time_up':
        return '시간 종료 — 최다 처치';
      case 'time_up_tied':
        return '시간 종료 — 동률 (무작위 결정)';
      case 'all_dead':
        return '전원 탈락';
      default:
        return win.reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    final winColor = _parseHex(win.winnerColorHex);
    final me = scoreboard.where((e) => e.userId == myUserId).toList();
    final myEntry = me.isEmpty ? null : me.first;
    final iAmWinner =
        myUserId != null && win.winnerUserId == myUserId && myUserId!.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 480),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  iAmWinner ? Icons.emoji_events : Icons.flag,
                  color: iAmWinner ? Colors.amberAccent : Colors.white70,
                ),
                const SizedBox(width: 8),
                Text(
                  iAmWinner ? '승리!' : '게임 종료',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _reasonLabel(),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (win.winnerUserId != null && win.winnerUserId!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: winColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: winColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: winColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '승자',
                            style: TextStyle(
                                color: Colors.white60, fontSize: 11),
                          ),
                          Text(
                            '${win.winnerNickname ?? '?'} · ${win.winnerColorLabel ?? '?'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (win.tagCount != null)
                            Text(
                              '처치 ${win.tagCount}회',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '승자가 없습니다 (전원 탈락)',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            const SizedBox(height: 16),
            if (myEntry != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _parseHex(myEntry.colorHex),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '내 결과: ${myEntry.isAlive ? "생존" : "탈락"} · '
                        '처치 ${myEntry.tagCount}회 · 미션 ${myEntry.missionsCompleted}회',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              '최종 스코어',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: scoreboard.length,
                separatorBuilder: (_, __) => Divider(
                  color: Colors.white.withValues(alpha: 0.06),
                  height: 8,
                ),
                itemBuilder: (_, idx) {
                  final e = scoreboard[idx];
                  final c = _parseHex(e.colorHex);
                  return Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            color: idx == 0
                                ? Colors.amberAccent
                                : Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration:
                            BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.nickname} · ${e.colorLabel}'
                          '${e.isAlive ? "" : " (탈락)"}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            decoration: e.isAlive
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      Text(
                        '${e.tagCount}',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onLeave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('홈으로'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
