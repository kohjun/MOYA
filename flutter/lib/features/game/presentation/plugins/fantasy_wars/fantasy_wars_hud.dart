import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../providers/fantasy_wars_provider.dart';
import 'fantasy_wars_design_tokens.dart';

Color guildColor(String? guildId) => FwColors.teamFromGuildId(guildId);

class FwTopHud extends StatelessWidget {
  const FwTopHud({
    super.key,
    required this.myState,
    required this.guilds,
    required this.aliveCount,
  });

  final FwMyState myState;
  final Map<String, FwGuildInfo> guilds;
  final int aliveCount;

  @override
  Widget build(BuildContext context) {
    final guild = guilds[myState.guildId];
    final teamColor = guildColor(myState.guildId);
    final topInset = MediaQuery.of(context).padding.top;
    final hpRatio = (myState.hp / 100).clamp(0.0, 1.0);
    final guildName = guild?.displayName ?? myState.guildId ?? '-';
    final guildIdLabel = myState.guildId ?? '';

    return Positioned(
      top: topInset + 8,
      left: FwSpace.x8,
      right: 64,
      // 상단 HUD 는 hp/스코어/길드명 등 비교적 자주 갱신되지만 지도 영역과
      // 독립적으로 그려져야 한다. 부모 Stack 의 다른 layer 에 paint 가 번지지
      // 않도록 raster cache 분리.
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: FwColors.cardSurface,
            borderRadius: BorderRadius.circular(FwRadii.lg),
            boxShadow: FwShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _AvatarTile(teamColor: teamColor, job: myState.job),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                guildName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FwText.display.copyWith(fontSize: 17),
                              ),
                            ),
                            if (guildIdLabel.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '($guildIdLabel)',
                                style: FwText.caption,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _jobLabel(myState.job),
                          style: FwText.label.copyWith(
                            color: FwColors.ink500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _HpBar(ratio: hpRatio, hp: myState.hp),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'HP ${myState.hp}/100',
                              style: FwText.mono,
                            ),
                            const Spacer(),
                            Text(
                              '생존 $aliveCount명',
                              style: FwText.caption.copyWith(
                                color: FwColors.ink500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _BadgeRow(myState: myState),
            ],
          ),
        ),
      ),
    );
  }

  String _jobLabel(String? job) => switch (job) {
        'warrior' => '전사',
        'priest' => '사제',
        'mage' => '마법사',
        'ranger' => '레인저',
        'rogue' => '도적',
        _ => job ?? '?',
      };
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({required this.teamColor, required this.job});

  final Color teamColor;
  final String? job;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: teamColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: teamColor, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(
            _jobIcon(job),
            color: teamColor,
            size: 26,
          ),
        ),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: FwColors.cardSurface,
              shape: BoxShape.circle,
              boxShadow: FwShadows.card,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.star_rounded,
                size: 14, color: FwColors.teamGold),
          ),
        ),
      ],
    );
  }

  IconData _jobIcon(String? j) => switch (j) {
        'warrior' => Icons.shield,
        'priest' => Icons.healing,
        'mage' => Icons.auto_awesome,
        'ranger' => Icons.visibility,
        'rogue' => Icons.local_fire_department,
        _ => Icons.person,
      };
}

class _HpBar extends StatelessWidget {
  const _HpBar({required this.ratio, required this.hp});

  final double ratio;
  final int hp;

  @override
  Widget build(BuildContext context) {
    final fillColor = hp > 40 ? FwColors.accentHealth : FwColors.danger;
    return ClipRRect(
      borderRadius: BorderRadius.circular(FwRadii.pill),
      child: Stack(
        children: [
          Container(
            height: 8,
            color: const Color(0xFFEFEFEF),
          ),
          FractionallySizedBox(
            widthFactor: ratio,
            child: Container(
              height: 8,
              color: fillColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.myState});

  final FwMyState myState;

  @override
  Widget build(BuildContext context) {
    final badges = <_BadgeData>[
      _BadgeData(
        active: myState.isGuildMaster,
        label: '길드 마스터',
        color: FwColors.teamGold,
      ),
      if (myState.job == 'warrior')
        _BadgeData(
          active: myState.remainingLives > 0,
          label: '목숨 ${myState.remainingLives}',
          color: FwColors.danger,
        )
      else
        const _BadgeData(
          active: false,
          label: '목숨 1',
          color: FwColors.ink300,
        ),
      _BadgeData(
        active: myState.shieldCount > 0,
        label: '보호막 ${myState.shieldCount}',
        color: FwColors.accentInfo,
      ),
      _BadgeData(
        active: myState.isBuffActive,
        label: '버프 활성',
        color: FwColors.accentHealth,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final b in badges) _BadgeChip(data: b)],
    );
  }
}

class _BadgeData {
  const _BadgeData({
    required this.active,
    required this.label,
    required this.color,
  });
  final bool active;
  final String label;
  final Color color;
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.data});

  final _BadgeData data;

  @override
  Widget build(BuildContext context) {
    final dim = !data.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            dim ? const Color(0xFFF6F7F9) : data.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FwRadii.sm),
        border: Border.all(
          color: dim ? FwColors.hairline : data.color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dim ? FwColors.ink300 : data.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            data.label,
            style: FwText.caption.copyWith(
              color: dim ? FwColors.ink500 : FwColors.ink900,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// 직업 스킬 버튼.
// 쿨타임 중 = 어두운 배경 + 아래에서 위로 컬러 fill (잔여시간에 비례) + 중앙에 큰 잔여 초.
// 쿨타임 끝 = 100% fill (직업 컬러) + glow + 아이콘 + 라벨, 탭 가능.
class FwSkillButton extends StatefulWidget {
  const FwSkillButton({
    super.key,
    required this.job,
    required this.onPressed,
    required this.skillUsedAt,
    required this.bottomOffset,
  });

  final String? job;
  final VoidCallback? onPressed;
  final Map<String, int> skillUsedAt;
  final double bottomOffset;

  @override
  State<FwSkillButton> createState() => _FwSkillButtonState();
}

class _FwSkillButtonState extends State<FwSkillButton>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  // 쿨타임 시작/길이 추적 — 진행도(progress) 계산에 필요.
  // skillUsedAt[skill] 값(=종료 timestamp) 이 새로 갱신되면 그때의 잔여를
  // duration 으로 캡처한다.
  int _trackedEndsAt = 0;
  int _durationMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    _syncCooldown();
  }

  @override
  void didUpdateWidget(covariant FwSkillButton old) {
    super.didUpdateWidget(old);
    _syncCooldown();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _syncCooldown() {
    final skill = _skillForJob(widget.job);
    if (skill == null) {
      _ticker?.stop();
      return;
    }
    final endsAt = widget.skillUsedAt[skill] ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (endsAt > now && endsAt != _trackedEndsAt) {
      _trackedEndsAt = endsAt;
      _durationMs = endsAt - now;
    } else if (endsAt <= now) {
      _trackedEndsAt = 0;
      _durationMs = 0;
    }
    if (endsAt > now) {
      if (!(_ticker?.isActive ?? false)) _ticker?.start();
    } else {
      _ticker?.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skill = _skillForJob(widget.job);
    final compact = MediaQuery.of(context).size.width < 390;
    final size = compact ? 60.0 : 64.0;

    // 전사 등 직접 발동 스킬이 없는 직업은 비활성 placeholder 로 항상 표시.
    // 빈 자리로 두면 "스킬 버튼이 사라졌다" 로 오해 받음.
    if (skill == null) {
      return Positioned(
        right: compact ? 12 : 16,
        bottom: widget.bottomOffset + (compact ? 8 : 16),
        child: Tooltip(
          message: _passiveJobTooltip(widget.job),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: Opacity(
              opacity: 0.55,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1F2937),
                  border: Border.all(
                    color: const Color(0xFF6B7280),
                    width: 1.6,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: const Color(0xFFD1D5DB),
                      size: compact ? 22 : 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '패시브',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFD1D5DB),
                        fontSize: compact ? 9.5 : 10,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final endsAt = widget.skillUsedAt[skill] ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainMs = endsAt - now;
    final onCooldown = remainMs > 0;
    final remainSec = onCooldown ? (remainMs / 1000).ceil() : 0;

    // 진행도: 0(방금 사용) → 1(쿨타임 끝). fill 의 heightFactor 로 사용.
    final progress = onCooldown && _durationMs > 0
        ? (1.0 - remainMs / _durationMs).clamp(0.0, 1.0)
        : 1.0;

    final color = _skillColor(skill);

    return Positioned(
      right: compact ? 12 : 16,
      bottom: widget.bottomOffset + (compact ? 8 : 16),
      // 스킬 버튼은 쿨타임 동안 ticker 가 매초 진행도를 그려 frequent
      // repaint 가 일어난다. 부모 Stack 의 다른 layer 와 raster 를 분리해
      // 지도 PlatformView 가 같이 무효화되지 않도록 함.
      child: RepaintBoundary(
        child: Tooltip(
          message: _skillTooltip(skill),
          child: GestureDetector(
            onTap: onCooldown ? null : widget.onPressed,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 쿨타임 중: 어두운 배경에서 fill 이 컬러로 채워짐.
                // Ready: 직업 컬러 가득 + glow.
                color: onCooldown
                    ? const Color(0xFF1F2937) // gray-800
                    : color,
                border: Border.all(
                  color: color,
                  width: onCooldown ? 1.6 : 2.6,
                ),
                boxShadow: onCooldown
                    ? const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 18,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                        const BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 아래→위 vertical fill (쿨타임 중에만 노출).
                    if (onCooldown)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: progress,
                          widthFactor: 1.0,
                          child:
                              Container(color: color.withValues(alpha: 0.55)),
                        ),
                      ),
                    // 중앙 컨텐츠
                    if (onCooldown)
                      Text(
                        '$remainSec',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 22 : 24,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      )
                    else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _skillIcon(skill),
                            color: Colors.white,
                            size: compact ? 22 : 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _skillShortLabel(skill),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 9.5 : 10,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                        ],
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

  String? _skillForJob(String? job) => switch (job) {
        'priest' => 'shield',
        'mage' => 'blockade',
        'ranger' => 'reveal',
        'rogue' => 'execution',
        _ => null,
      };

  String _skillShortLabel(String skill) => switch (skill) {
        'shield' => '보호막',
        'blockade' => '봉쇄',
        'reveal' => '추적',
        'execution' => '처형',
        _ => skill,
      };

  String _skillTooltip(String skill) => switch (skill) {
        'shield' => '사제: 아군에게 보호막을 부여합니다.',
        'blockade' => '마법사: 점령지를 잠시 봉쇄합니다.',
        'reveal' => '레인저: 적 위치를 추적합니다.',
        'execution' => '도적: 다음 결투 승리 시 처형을 준비합니다.',
        _ => skill,
      };

  // 직접 발동 스킬이 없는 직업 (전사 등) 의 안내.
  String _passiveJobTooltip(String? job) => switch (job) {
        'warrior' => '전사는 직접 발동 스킬이 없습니다 (방어 패시브).',
        _ => '이 직업은 직접 발동 스킬이 없습니다.',
      };

  IconData _skillIcon(String skill) => switch (skill) {
        'shield' => Icons.shield_rounded,
        'blockade' => Icons.block_rounded,
        'reveal' => Icons.radar_rounded,
        'execution' => Icons.flash_on_rounded,
        _ => Icons.auto_fix_high_rounded,
      };

  // 직업별 강조 컬러 — 일관된 디자인 토큰.
  Color _skillColor(String skill) => switch (skill) {
        'shield' => const Color(0xFF06B6D4), // cyan-500 (priest)
        'blockade' => const Color(0xFF8B5CF6), // violet-500 (mage)
        'reveal' => const Color(0xFF10B981), // emerald-500 (ranger)
        'execution' => const Color(0xFFEF4444), // red-500 (rogue)
        _ => const Color(0xFF0F766E),
      };
}

// FwGameOverOverlay 는 widgets/fw_game_result_screen.dart 의 FwGameResultScreen
// 으로 대체되었다. 호출처(fantasy_wars_game_screen.dart) 에서 더 이상 참조하지 않음.
