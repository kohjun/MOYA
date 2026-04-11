import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'map_session_models.dart';

class MapBottomMemberPanel extends StatelessWidget {
  const MapBottomMemberPanel({
    super.key,
    required this.members,
    required this.myPosition,
    required this.onSOS,
    required this.onMemberTap,
    required this.hiddenMembers,
    required this.eliminatedUserIds,
    required this.onHideToggle,
  });

  final List<MemberState> members;
  final Position? myPosition;
  final VoidCallback onSOS;
  final ValueChanged<MemberState> onMemberTap;
  final Set<String> hiddenMembers;
  final Set<String> eliminatedUserIds;
  final ValueChanged<String> onHideToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  '멤버 위치',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: onSOS,
                  icon: const Icon(Icons.warning_amber, size: 18),
                  label: const Text('SOS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '다른 멤버가 없습니다',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            SizedBox(
              height: 78,
              child: members.length >= 5
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final member in members)
                            _MapMemberChip(
                              member: member,
                              myPosition: myPosition,
                              isHidden: hiddenMembers.contains(member.userId),
                              isEliminated:
                                  eliminatedUserIds.contains(member.userId),
                              onTap: () => onMemberTap(member),
                              onLongPress: () => _showMemberSheet(
                                context,
                                member,
                                hiddenMembers.contains(member.userId),
                                onMemberTap,
                                onHideToggle,
                              ),
                            ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final member in members)
                            _MapMemberChip(
                              member: member,
                              myPosition: myPosition,
                              isHidden: hiddenMembers.contains(member.userId),
                              isEliminated:
                                  eliminatedUserIds.contains(member.userId),
                              onTap: () => onMemberTap(member),
                              onLongPress: () => _showMemberSheet(
                                context,
                                member,
                                hiddenMembers.contains(member.userId),
                                onMemberTap,
                                onHideToggle,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  static void _showMemberSheet(
    BuildContext context,
    MemberState member,
    bool isHidden,
    ValueChanged<MemberState> onLocate,
    ValueChanged<String> onHideToggle,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                member.nickname,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('위치로 이동'),
              enabled: member.lat != 0 || member.lng != 0,
              onTap: () {
                Navigator.pop(ctx);
                onLocate(member);
              },
            ),
            ListTile(
              leading: Icon(
                isHidden ? Icons.visibility : Icons.visibility_off,
                color: isHidden ? Colors.blue : null,
              ),
              title: Text(isHidden ? '숨기기 해제' : '이 멤버 숨기기'),
              onTap: () {
                Navigator.pop(ctx);
                onHideToggle(member.userId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MapMemberChip extends StatelessWidget {
  const _MapMemberChip({
    required this.member,
    required this.myPosition,
    required this.onTap,
    required this.onLongPress,
    required this.isHidden,
    required this.isEliminated,
  });

  final MemberState member;
  final Position? myPosition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isHidden;
  final bool isEliminated;

  @override
  Widget build(BuildContext context) {
    final distance = _calcDistance();

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: isHidden ? 0.4 : (isEliminated ? 0.5 : 1.0),
        child: Container(
          width: 72,
          height: 78,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isEliminated ? Colors.grey[100] : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEliminated ? Colors.grey[400]! : Colors.grey[200]!,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: isEliminated
                        ? Colors.grey.withValues(alpha: 0.25)
                        : const Color(0xFF2196F3).withValues(alpha: 0.15),
                    child: Text(
                      member.nickname.isNotEmpty
                          ? member.nickname[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: isEliminated
                            ? Colors.grey[600]
                            : const Color(0xFF2196F3),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (isEliminated)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.dangerous,
                        size: 16,
                        color: Colors.white,
                      ),
                    )
                  else
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: member.status == 'moving'
                              ? Colors.green
                              : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                member.nickname,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isEliminated ? Colors.grey[500] : null,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (isEliminated)
                Text(
                  '탈락',
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                )
              else if (distance != null)
                Text(
                  distance,
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _calcDistance() {
    if (myPosition == null || (member.lat == 0 && member.lng == 0)) {
      return null;
    }
    final meters = Geolocator.distanceBetween(
      myPosition!.latitude,
      myPosition!.longitude,
      member.lat,
      member.lng,
    );
    if (meters < 1000) {
      return '${meters.round()}m';
    }
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
}
