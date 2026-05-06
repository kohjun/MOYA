import 'package:flutter/material.dart';

import '../../fantasy_wars_design_tokens.dart';
import '../fw_duel_atoms.dart';
import '../fw_duel_class_catalog.dart';

// VS Intro — 결투 시작 0.6s 트랜지션.
// 디자인 핸드오프 flow-screens.jsx 의 VsScreen 이식.
// - bg ink900 (어두운 무대) + 좌상/우하 액센트 컬러 18%/22% 대각 분할
// - 상단 Challenger / 중앙 거대 serif "VS" / 하단 Opponent (거울 배치)
// - 푸터: MATCH ID / BEST OF 1
//
// 클라이언트가 상대 job 을 모르므로 opponent 측은 assassin(mono) 으로 placeholder.

class FwDuelVsIntroOverlay extends StatelessWidget {
  const FwDuelVsIntroOverlay({
    super.key,
    required this.myJob,
    required this.myName,
    required this.opponentName,
    this.matchId,
  });

  final String? myJob;
  final String myName;
  final String opponentName;
  final String? matchId;

  @override
  Widget build(BuildContext context) {
    final myKlass = FwDuelClasses.fromPlayerJob(myJob);
    final myData = FwDuelClasses.of(myKlass);
    const oppKlass = FwDuelClass.assassin;
    final oppData = FwDuelClasses.of(oppKlass);

    return Positioned.fill(
      child: ColoredBox(
        color: FwColors.ink900,
        child: Stack(
          children: [
            // 좌상단 대각 분할 (challenger accent 18%)
            Positioned(
              top: 0,
              left: 0,
              child: IgnorePointer(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.7,
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(
                        0,
                        -MediaQuery.of(context).size.height * 0.1,
                        0,
                        1,
                      )
                      ..rotateZ(-0.14), // ~ -8deg
                    child: ColoredBox(
                      color: myData.accent.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
            ),
            // 우하단 대각 분할 (opponent accent 22%)
            Positioned(
              bottom: 0,
              right: 0,
              child: IgnorePointer(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.7,
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(
                        0,
                        MediaQuery.of(context).size.height * 0.1,
                        0,
                        1,
                      )
                      ..rotateZ(-0.14),
                    child: ColoredBox(
                      color: oppData.accent == FwColors.ink900
                          ? Colors.white.withValues(alpha: 0.06)
                          : oppData.accent.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ),
            // Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PlayerRow(
                      data: myData,
                      label: 'CHALLENGER',
                      name: myName,
                      reverse: false,
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 좌우 dashed/얇은 라인
                          Positioned(
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          const FwSerifText(
                            text: 'VS',
                            size: 110,
                            weight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -2,
                            height: 1.0,
                          ),
                        ],
                      ),
                    ),
                    _PlayerRow(
                      data: oppData,
                      label: 'OPPONENT',
                      name: opponentName,
                      reverse: true,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FwMono(
                          text: 'MATCH ${matchId ?? '----'}',
                          size: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 0.6,
                        ),
                        FwMono(
                          text: 'BEST OF 1',
                          size: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 0.6,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.data,
    required this.label,
    required this.name,
    required this.reverse,
  });

  final FwDuelClassData data;
  final String label;
  final String name;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final emblem = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: data.accent == FwColors.ink900
            ? Colors.white.withValues(alpha: 0.10)
            : data.accent,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: data.accent.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: FwClassEmblem(
        kind: data.icon,
        color: Colors.white,
        size: 44,
        stroke: 2.2,
      ),
    );

    final accentLabel = data.accent == FwColors.ink900
        ? Colors.white.withValues(alpha: 0.7)
        : data.accent;

    final textBlock = Column(
      crossAxisAlignment:
          reverse ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        FwMono(
          text: label,
          size: 10,
          weight: FontWeight.w600,
          color: accentLabel,
          letterSpacing: 1.6,
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.3,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        FwMono(
          text: '${data.name} · ${data.en.toUpperCase()}',
          size: 11,
          color: Colors.white.withValues(alpha: 0.6),
        ),
      ],
    );

    final children = reverse
        ? [textBlock, const SizedBox(width: 14), emblem]
        : [emblem, const SizedBox(width: 14), textBlock];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            reverse ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: children,
      ),
    );
  }
}
