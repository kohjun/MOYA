// lib/features/game/presentation/widgets/mission_list_sheet.dart
//
// GameProvider의 미션 목록을 보여주는 바텀 시트

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/game_models.dart';
import '../../providers/game_provider.dart';
import '../minigames/minigame_wrapper_screen.dart';

class MissionListSheet extends ConsumerWidget {
  const MissionListSheet({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions = ref.watch(gameProvider(sessionId)).myMissions;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1535),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '내 미션',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (missions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '배정된 미션이 없습니다.',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: missions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final mission = missions[index];
                return _MissionTile(
                  sessionId: sessionId,
                  mission: mission,
                  onAction: () => _handleAction(context, ref, mission),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, Mission mission) async {
    final notifier = ref.read(gameProvider(sessionId).notifier);

    // ── locked: 시작 버튼 ──────────────────────────────────────────────
    // 사용자가 '시작'을 눌러야 이 시점부터 코인/동물이 맵에 표시되거나
    // 미니게임 화면이 열린다. auto-spawn 금지.
    if (mission.status == MissionStatus.locked) {
      final started = notifier.startMission(mission.id);
      if (started == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('플레이 영역이 설정되지 않아 시작할 수 없습니다.'),
          duration: Duration(seconds: 2),
        ));
        return;
      }

      switch (mission.type) {
        case MissionType.minigame:
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MinigameWrapperScreen(
              sessionId: sessionId,
              mission: started,
            ),
          ));
          break;
        case MissionType.coinCollect:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('코인이 맵에 표시됐습니다. 10m 이내로 이동해 수집하세요.'),
            duration: Duration(seconds: 2),
          ));
          break;
        case MissionType.captureAnimal:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('동물이 맵에 등장했습니다. 5m 이내로 다가가 포획하세요.'),
            duration: Duration(seconds: 2),
          ));
          break;
      }
      return;
    }

    // ── started: 맵에서 대상으로 이동해야 함 ──────────────────────────
    if (mission.status == MissionStatus.started) {
      switch (mission.type) {
        case MissionType.minigame:
          // 미니게임은 시작 시 바로 화면을 열었으므로 이 경로는 재진입용.
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MinigameWrapperScreen(
              sessionId: sessionId,
              mission: mission,
            ),
          ));
          break;
        case MissionType.coinCollect:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('코인 근처(10m)로 이동하세요.'),
            duration: Duration(seconds: 1),
          ));
          break;
        case MissionType.captureAnimal:
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('동물 근처(5m)로 이동하세요.'),
            duration: Duration(seconds: 1),
          ));
          break;
      }
      return;
    }

    // ── ready: 수행 ────────────────────────────────────────────────────
    if (mission.status == MissionStatus.ready) {
      switch (mission.type) {
        case MissionType.minigame:
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MinigameWrapperScreen(
              sessionId: sessionId,
              mission: mission,
            ),
          ));
          break;
        case MissionType.coinCollect:
          final result = await notifier.collectNearestCoinFor(mission.id);
          if (!context.mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          if (result == null) {
            messenger.showSnackBar(const SnackBar(
              content: Text('범위를 벗어났습니다. 코인 10m 이내로 이동하세요.'),
              duration: Duration(seconds: 1),
            ));
          } else if (result == true) {
            messenger.showSnackBar(const SnackBar(
              content: Text('모든 코인을 수집했습니다! 미션 완료'),
              backgroundColor: Color(0xFF22C55E),
              duration: Duration(milliseconds: 1200),
            ));
          } else {
            messenger.showSnackBar(const SnackBar(
              content: Text('코인을 수집했습니다.'),
              duration: Duration(seconds: 1),
            ));
          }
          break;
        case MissionType.captureAnimal:
          final ok = await notifier.captureAnimalFor(mission.id);
          if (!context.mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          if (ok) {
            messenger.showSnackBar(const SnackBar(
              content: Text('동물을 포획했습니다! 미션 완료'),
              backgroundColor: Color(0xFF22C55E),
              duration: Duration(milliseconds: 1200),
            ));
          } else {
            messenger.showSnackBar(const SnackBar(
              content: Text('범위를 벗어났습니다. 동물 5m 이내로 이동하세요.'),
              duration: Duration(seconds: 1),
            ));
          }
          break;
      }
    }
  }
}

class _MissionTile extends ConsumerWidget {
  const _MissionTile({
    required this.sessionId,
    required this.mission,
    required this.onAction,
  });

  final String sessionId;
  final Mission mission;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeLabel = mission.type.label;

    // 코인 미션은 진행 중일 때 남은 개수(수집/총)를 라벨에 표시한다.
    String? progressLabel;
    if (mission.type == MissionType.coinCollect &&
        mission.status != MissionStatus.locked &&
        mission.status != MissionStatus.completed) {
      final coins =
          ref.watch(gameProvider(sessionId)).missionCoins[mission.id];
      const total = 3;
      final collected =
          (coins?.where((coin) => coin.collected).length ?? 0).clamp(0, total);
      progressLabel = '$collected/$total 수집';
    }

    // 상태별 CTA 라벨 + 배경색.
    final (ctaLabel, ctaBg, ctaFg) = switch (mission.status) {
      MissionStatus.locked =>
        ('시작', const Color(0xFF2563EB), Colors.white),
      MissionStatus.started => switch (mission.type) {
          MissionType.minigame => ('열기', const Color(0xFF7C3AED), Colors.white),
          MissionType.coinCollect ||
          MissionType.captureAnimal =>
            ('진행 중', Colors.white12, Colors.white70),
        },
      MissionStatus.ready => switch (mission.type) {
          MissionType.minigame => ('열기', const Color(0xFF7C3AED), Colors.white),
          MissionType.coinCollect => ('수집', const Color(0xFF22C55E), Colors.white),
          MissionType.captureAnimal => ('포획', const Color(0xFF22C55E), Colors.white),
        },
      MissionStatus.completed =>
        ('완료', Colors.white12, const Color(0xFF60A5FA)),
    };

    final isInteractive = mission.status != MissionStatus.completed;
    final highlightBorder = mission.status == MissionStatus.ready
        ? const Color(0xFF22C55E).withValues(alpha: 0.5)
        : (mission.status == MissionStatus.locked
            ? const Color(0xFF2563EB).withValues(alpha: 0.4)
            : Colors.transparent);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlightBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mission.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  mission.description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (progressLabel != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      progressLabel,
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: ctaBg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: isInteractive ? onAction : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Text(
                  ctaLabel,
                  style: TextStyle(
                    color: ctaFg,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
