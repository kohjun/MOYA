import 'package:flutter/material.dart';

import '../../../../providers/fantasy_wars_provider.dart';
import 'fw_choice_badge.dart';

class HostEventSection extends StatefulWidget {
  const HostEventSection({
    super.key,
    required this.title,
    required this.events,
    this.onEventTap,
    this.onEventInspectTap,
  });

  final String title;
  final List<FwRecentEvent> events;
  final ValueChanged<FwRecentEvent>? onEventTap;
  final ValueChanged<FwRecentEvent>? onEventInspectTap;

  @override
  State<HostEventSection> createState() => _HostEventSectionState();
}

class _HostEventSectionState extends State<HostEventSection> {
  String _selectedKind = 'all';
  String _searchQuery = '';
  String? _pinnedEventKey;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant HostEventSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availableKinds = _availableKinds();
    if (!availableKinds.contains(_selectedKind)) {
      _selectedKind = 'all';
    }
    if (_pinnedEventKey != null &&
        !widget.events.any((event) => _eventKey(event) == _pinnedEventKey)) {
      _pinnedEventKey = null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableKinds = _availableKinds();
    final pinnedEvent = _pinnedEvent();
    final visibleEvents = _filteredEvents(
      excludeEventKey: pinnedEvent == null ? null : _eventKey(pinnedEvent),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _HostEventSearchBar(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            onClear: _searchQuery.isEmpty
                ? null
                : () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
          ),
          const SizedBox(height: 12),
          if (availableKinds.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in availableKinds)
                  ChoiceChip(
                    label: Text(_kindFilterLabel(kind)),
                    selected: _selectedKind == kind,
                    onSelected: (_) {
                      setState(() {
                        _selectedKind = kind;
                      });
                    },
                    labelStyle: TextStyle(
                      color: _selectedKind == kind
                          ? _kindColor(kind)
                          : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    selectedColor: _kindColor(kind).withValues(alpha: 0.18),
                    side: BorderSide(
                      color: _selectedKind == kind
                          ? _kindColor(kind).withValues(alpha: 0.8)
                          : Colors.white12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (pinnedEvent != null) ...[
            Row(
              children: [
                const Text(
                  '고정됨',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _pinnedEventKey = null;
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _kindColor(pinnedEvent.kind),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '고정 해제',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _HostEventRow(
              event: pinnedEvent,
              color: _kindColor(pinnedEvent.kind),
              badgeLabel: _kindBadgeLabel(pinnedEvent.kind),
              onTap: pinnedEvent.hasFocusTarget && widget.onEventTap != null
                  ? () => widget.onEventTap!(pinnedEvent)
                  : null,
              onInspectTap:
                  pinnedEvent.hasFocusTarget && widget.onEventInspectTap != null
                      ? () => widget.onEventInspectTap!(pinnedEvent)
                      : null,
              onPinToggle: () => _togglePinned(pinnedEvent),
              isPinned: true,
            ),
            const SizedBox(height: 12),
          ],
          if (visibleEvents.isEmpty)
            const Text(
              '필터 조건에 맞는 이벤트가 없습니다',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            )
          else
            for (var index = 0; index < visibleEvents.length; index++) ...[
              _HostEventRow(
                event: visibleEvents[index],
                color: _kindColor(visibleEvents[index].kind),
                badgeLabel: _kindBadgeLabel(visibleEvents[index].kind),
                onTap: visibleEvents[index].hasFocusTarget &&
                        widget.onEventTap != null
                    ? () => widget.onEventTap!(visibleEvents[index])
                    : null,
                onInspectTap: visibleEvents[index].hasFocusTarget &&
                        widget.onEventInspectTap != null
                    ? () => widget.onEventInspectTap!(visibleEvents[index])
                    : null,
                onPinToggle: () => _togglePinned(visibleEvents[index]),
                isPinned: _eventKey(visibleEvents[index]) == _pinnedEventKey,
              ),
              if (index != visibleEvents.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  List<String> _availableKinds() {
    final orderedKinds = <String>['all'];
    for (final event in widget.events) {
      if (!orderedKinds.contains(event.kind)) {
        orderedKinds.add(event.kind);
      }
    }
    return orderedKinds;
  }

  List<FwRecentEvent> _filteredEvents({
    String? excludeEventKey,
  }) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filtered = widget.events.where((event) {
      if (_selectedKind != 'all' && event.kind != _selectedKind) {
        return false;
      }
      if (excludeEventKey != null && _eventKey(event) == excludeEventKey) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final haystack = '${event.kind} ${event.message}'.toLowerCase();
      return haystack.contains(normalizedQuery);
    });
    return filtered.take(10).toList(growable: false);
  }

  FwRecentEvent? _pinnedEvent() {
    final pinnedEventKey = _pinnedEventKey;
    if (pinnedEventKey == null) {
      return null;
    }
    for (final event in widget.events) {
      if (_eventKey(event) == pinnedEventKey) {
        return event;
      }
    }
    return null;
  }

  void _togglePinned(FwRecentEvent event) {
    final key = _eventKey(event);
    setState(() {
      _pinnedEventKey = _pinnedEventKey == key ? null : key;
    });
  }

  String _eventKey(FwRecentEvent event) {
    return [
      event.recordedAt,
      event.kind,
      event.message,
      event.primaryUserId ?? '',
      event.secondaryUserId ?? '',
      event.controlPointId ?? '',
    ].join('|');
  }

  String _kindFilterLabel(String kind) => switch (kind) {
        'all' => '전체',
        'duel' => '결투',
        'capture' => '점령',
        'skill' => '스킬',
        'combat' => '전투',
        'revive' => '부활',
        'match' => '매치',
        _ => kind,
      };

  String _kindBadgeLabel(String kind) => switch (kind) {
        'duel' => '결투',
        'capture' => '점령',
        'skill' => '스킬',
        'combat' => '전투',
        'revive' => '부활',
        'match' => '매치',
        _ => kind.toUpperCase(),
      };

  Color _kindColor(String kind) => switch (kind) {
        'duel' => const Color(0xFFF97316),
        'capture' => const Color(0xFF14B8A6),
        'skill' => const Color(0xFF818CF8),
        'combat' => const Color(0xFFEF4444),
        'revive' => const Color(0xFF22C55E),
        'match' => const Color(0xFFFACC15),
        _ => Colors.white70,
      };
}

class _HostEventSearchBar extends StatelessWidget {
  const _HostEventSearchBar({
    required this.controller,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.18),
        hintText: '이벤트 검색',
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: Colors.white54,
        ),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white54,
                ),
                splashRadius: 18,
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF5EEAD4)),
        ),
      ),
    );
  }
}

class _HostEventRow extends StatelessWidget {
  const _HostEventRow({
    required this.event,
    required this.color,
    required this.badgeLabel,
    this.onTap,
    this.onInspectTap,
    this.onPinToggle,
    this.isPinned = false,
  });

  final FwRecentEvent event;
  final Color color;
  final String badgeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onInspectTap;
  final VoidCallback? onPinToggle;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final ageMs = DateTime.now().millisecondsSinceEpoch - event.recordedAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FwChoiceBadge(
                    label: badgeLabel,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      event.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ],
                  if (onInspectTap != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: onInspectTap,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      splashRadius: 18,
                      icon: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: color.withValues(alpha: 0.95),
                      ),
                      tooltip: '상세 보기',
                    ),
                  ],
                  if (onPinToggle != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: onPinToggle,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      splashRadius: 18,
                      icon: Icon(
                        isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 16,
                        color:
                            isPinned ? const Color(0xFFFDE68A) : Colors.white54,
                      ),
                      tooltip: isPinned ? '고정 해제' : '고정',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${_formatAge(ageMs)} 전',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                  if (onTap != null) ...[
                    const Spacer(),
                    Text(
                      isPinned ? '고정됨' : '탭하여 포커스',
                      style: TextStyle(
                        color: isPinned
                            ? const Color(0xFFFDE68A)
                            : color.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAge(int ageMs) {
    if (ageMs <= 0) {
      return '0.0s';
    }
    if (ageMs >= 60000) {
      final minutes = ageMs ~/ 60000;
      final seconds = ((ageMs % 60000) / 1000).round();
      return '${minutes}m ${seconds}s';
    }
    if (ageMs >= 10000) {
      return '${(ageMs / 1000).round()}s';
    }
    return '${(ageMs / 1000).toStringAsFixed(1)}s';
  }
}

class HostDebugSection extends StatelessWidget {
  const HostDebugSection({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < lines.length; index++) ...[
            Text(
              lines[index],
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            if (index != lines.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
