import 'package:flutter/material.dart';

import '../../../../providers/fantasy_wars_models.dart';
import '../fantasy_wars_design_tokens.dart';
import '../fantasy_wars_hud.dart' show guildColor;

// 종합 게임 결과 화면. 기존 단발 "승리/패배" 한 줄 오버레이 (FwGameOverOverlay)
// 를 대체. 길드별 점수 / 점령지 수 / 마스터 생존 / 멤버 생존 상태와 점령지
// 5 칸 그리드를 한 화면에 모은다.
//
// 데이터는 모두 game:state_update 로 도착한 fwState 와 lobby memberLabels 로
// 충분 — 별도 game:over summary 페이로드 확장은 필요 없다.

class FwGameResultScreen extends StatelessWidget {
  const FwGameResultScreen({
    super.key,
    required this.winCondition,
    required this.myGuildId,
    required this.guilds,
    required this.controlPoints,
    required this.alivePlayerIds,
    required this.eliminatedPlayerIds,
    required this.memberLabels,
    required this.onLeave,
  });

  final Map<String, dynamic> winCondition;
  final String? myGuildId;
  final Map<String, FwGuildInfo> guilds;
  final List<FwControlPoint> controlPoints;
  final List<String> alivePlayerIds;
  final List<String> eliminatedPlayerIds;
  final Map<String, String> memberLabels;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final winner = winCondition['winner'] as String?;
    final reason = winCondition['reason'] as String?;
    final isWin = winner != null && winner == myGuildId;

    final orderedGuildIds = _orderedGuildIds(winner);
    final eliminated = eliminatedPlayerIds.toSet();

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.84),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Banner(isWin: isWin, winner: winner, guilds: guilds),
                    const SizedBox(height: 8),
                    Text(
                      _reasonLabel(reason),
                      textAlign: TextAlign.center,
                      style: FwText.label.copyWith(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _ControlPointStrip(
                      controlPoints: controlPoints,
                      myGuildId: myGuildId,
                    ),
                    const SizedBox(height: 22),
                    for (final guildId in orderedGuildIds) ...[
                      _GuildResultCard(
                        guild: guilds[guildId]!,
                        isWinner: guildId == winner,
                        isMine: guildId == myGuildId,
                        capturedCount: controlPoints
                            .where((cp) => cp.capturedBy == guildId)
                            .length,
                        memberLabels: memberLabels,
                        eliminated: eliminated,
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: onLeave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FwColors.cardSurface,
                          foregroundColor: FwColors.ink900,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FwRadii.md),
                          ),
                        ),
                        child: const Text(
                          '로비로 돌아가기',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 승리 길드 → 내 길드 → 나머지 score 내림차순.
  List<String> _orderedGuildIds(String? winner) {
    final keys = guilds.keys.toList();
    keys.sort((a, b) {
      if (a == winner) return -1;
      if (b == winner) return 1;
      if (a == myGuildId) return -1;
      if (b == myGuildId) return 1;
      final sa = guilds[a]?.score ?? 0;
      final sb = guilds[b]?.score ?? 0;
      return sb.compareTo(sa);
    });
    return keys;
  }

  String _reasonLabel(String? reason) => switch (reason) {
        'control_point_majority' => '거점 다수 점령으로 승리',
        'guild_master_eliminated' => '상대 길드 마스터 제거로 승리',
        'last_standing_by_score' => '동시 탈락 후 점수 판정',
        _ => reason ?? '',
      };
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.isWin,
    required this.winner,
    required this.guilds,
  });

  final bool isWin;
  final String? winner;
  final Map<String, FwGuildInfo> guilds;

  @override
  Widget build(BuildContext context) {
    final headline = isWin ? '승리' : (winner == null ? '무승부' : '패배');
    final color = isWin
        ? const Color(0xFFFBBF24)
        : (winner == null ? Colors.white70 : Colors.white60);
    final winnerName = winner != null
        ? (guilds[winner]?.displayName ?? winner ?? '?')
        : '결과 없음';
    return Column(
      children: [
        Text(
          headline,
          style: TextStyle(
            color: color,
            fontFamily: 'Pretendard',
            fontSize: 48,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 4),
        if (winner != null)
          Text(
            '$winnerName 길드 승리',
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ControlPointStrip extends StatelessWidget {
  const _ControlPointStrip({
    required this.controlPoints,
    required this.myGuildId,
  });

  final List<FwControlPoint> controlPoints;
  final String? myGuildId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(FwRadii.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '점령지',
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final cp in controlPoints)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _CpCell(
                      cp: cp,
                      isMine:
                          cp.capturedBy != null && cp.capturedBy == myGuildId,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CpCell extends StatelessWidget {
  const _CpCell({required this.cp, required this.isMine});

  final FwControlPoint cp;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final color = cp.capturedBy != null
        ? guildColor(cp.capturedBy)
        : Colors.white.withValues(alpha: 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: cp.capturedBy != null ? 0.22 : 0.08),
        borderRadius: BorderRadius.circular(FwRadii.sm),
        border: Border.all(
          color: isMine ? FwColors.teamGold : color.withValues(alpha: 0.6),
          width: isMine ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.shield_rounded, size: 18, color: color),
          const SizedBox(height: 2),
          Text(
            cp.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuildResultCard extends StatelessWidget {
  const _GuildResultCard({
    required this.guild,
    required this.isWinner,
    required this.isMine,
    required this.capturedCount,
    required this.memberLabels,
    required this.eliminated,
  });

  final FwGuildInfo guild;
  final bool isWinner;
  final bool isMine;
  final int capturedCount;
  final Map<String, String> memberLabels;
  final Set<String> eliminated;

  @override
  Widget build(BuildContext context) {
    final color = guildColor(guild.guildId);
    final aliveCount =
        guild.memberIds.where((id) => !eliminated.contains(id)).length;
    final masterAlive = guild.guildMasterId != null &&
        !eliminated.contains(guild.guildMasterId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isWinner ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(FwRadii.lg),
        border: Border.all(
          color: isWinner ? FwColors.teamGold : color.withValues(alpha: 0.55),
          width: isWinner ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(FwRadii.lg),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_rounded, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    guild.displayName,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isWinner)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.emoji_events_rounded,
                        color: FwColors.teamGold, size: 22),
                  ),
                if (isMine)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FwColors.teamGold.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: FwColors.teamGold, width: 1),
                    ),
                    child: const Text(
                      'MY',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: FwColors.teamGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _StatTile(label: '점수', value: '${guild.score}'),
                _StatTile(label: '점령', value: '$capturedCount'),
                _StatTile(
                    label: '생존',
                    value: '$aliveCount / ${guild.memberIds.length}'),
                _StatTile(
                  label: '마스터',
                  value: masterAlive ? '생존' : '탈락',
                  valueColor: masterAlive ? Colors.white : Colors.redAccent,
                ),
              ],
            ),
          ),
          if (guild.memberIds.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0x33FFFFFF)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final memberId in guild.memberIds)
                    _MemberChip(
                      label: memberLabels[memberId] ?? memberId,
                      isMaster: guild.guildMasterId == memberId,
                      isEliminated: eliminated.contains(memberId),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: valueColor ?? Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.label,
    required this.isMaster,
    required this.isEliminated,
  });

  final String label;
  final bool isMaster;
  final bool isEliminated;

  @override
  Widget build(BuildContext context) {
    final textColor = isEliminated ? Colors.white38 : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isEliminated
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isMaster
              ? FwColors.teamGold
              : Colors.white.withValues(alpha: 0.18),
          width: isMaster ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMaster)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child:
                  Icon(Icons.star_rounded, size: 12, color: FwColors.teamGold),
            ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              decoration: isEliminated ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}
