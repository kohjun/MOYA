import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../home/data/session_repository.dart';

enum _LayoutStep {
  area,
  controlPoints,
  spawns,
}

class PlayableAreaPainterScreen extends ConsumerStatefulWidget {
  const PlayableAreaPainterScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<PlayableAreaPainterScreen> createState() =>
      _PlayableAreaPainterScreenState();
}

class _PlayableAreaPainterScreenState
    extends ConsumerState<PlayableAreaPainterScreen> {
  static const _defaultControlPointCount = 5;
  static const _spawnRadiusMeters = 18.0;

  NaverMapController? _mapController;
  Session? _session;
  bool _isLoading = true;
  bool _isSaving = false;
  NLatLng _initialPosition = const NLatLng(37.5665, 126.9780);

  final List<NLatLng> _areaVertices = [];
  final List<NLatLng> _controlPoints = [];
  final Map<String, NLatLng> _spawnCenters = {};

  _LayoutStep _step = _LayoutStep.area;
  String? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadCurrentPosition(),
      _loadSession(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
      unawaited(_refreshOverlays());
    }
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _initialPosition = NLatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // Keep default center.
    }
  }

  Future<void> _loadSession() async {
    final session =
        await ref.read(sessionRepositoryProvider).getSession(widget.sessionId);

    final rawArea = session.playableArea ?? const [];
    final area = rawArea
        .map((point) => NLatLng(point['lat']!, point['lng']!))
        .toList();

    if (area.length >= 2 && area.first == area.last) {
      area.removeLast();
    }

    _session = session;
    _areaVertices
      ..clear()
      ..addAll(area);
    _controlPoints
      ..clear()
      ..addAll(
        session.fantasyWarsControlPoints
            .map((point) => NLatLng(point['lat']!, point['lng']!)),
      );
    _spawnCenters
      ..clear()
      ..addEntries(session.fantasyWarsSpawnZones.map((zone) {
        return MapEntry(zone.teamId, _polygonCenter(zone.polygonPoints));
      }));

    final firstTeam = _teams.isNotEmpty ? _teams.first.teamId : null;
    _selectedTeamId = firstTeam;
  }

  List<FantasyWarsTeamConfig> get _teams {
    final sessionTeams = _session?.fantasyWarsTeams ?? const [];
    if (sessionTeams.isNotEmpty) {
      return sessionTeams;
    }

    return const [
      FantasyWarsTeamConfig(
        teamId: 'guild_alpha',
        displayName: '붉은 팀',
        color: '#DC2626',
      ),
      FantasyWarsTeamConfig(
        teamId: 'guild_beta',
        displayName: '푸른 팀',
        color: '#2563EB',
      ),
      FantasyWarsTeamConfig(
        teamId: 'guild_gamma',
        displayName: '초록 팀',
        color: '#16A34A',
      ),
    ];
  }

  bool get _isFantasyWars =>
      (_session?.gameType ?? 'among_us') == 'fantasy_wars_artifact';

  int get _controlPointCount =>
      (_session?.gameConfig['controlPointCount'] as num?)?.toInt() ??
      _defaultControlPointCount;

  Future<void> _refreshOverlays() async {
    final controller = _mapController;
    if (controller == null || !mounted) return;

    await controller.clearOverlays();

    await _drawAreaOverlays(controller);
    await _drawControlPoints(controller);
    await _drawSpawnZones(controller);
  }

  Future<void> _drawAreaOverlays(NaverMapController controller) async {
    if (_areaVertices.isEmpty) return;

    for (var index = 0; index < _areaVertices.length; index += 1) {
      final currentContext = context;
      if (!currentContext.mounted) return;
      final icon = await NOverlayImage.fromWidget(
        widget: _NumberDot(
          label: '${index + 1}',
          color: const Color(0xFF1D4ED8),
        ),
        size: const Size(30, 30),
        context: currentContext,
      );
      await controller.addOverlay(
        NMarker(
          id: 'area_vertex_$index',
          position: _areaVertices[index],
          icon: icon,
        ),
      );
    }

    if (_areaVertices.length >= 3) {
      final coords = List<NLatLng>.from(_areaVertices);
      coords.add(_areaVertices.first);
      await controller.addOverlay(
        NPolygonOverlay(
          id: 'play_area',
          coords: coords,
          color: const Color(0xFF1D4ED8).withValues(alpha: 0.12),
          outlineColor: const Color(0xFF1D4ED8),
          outlineWidth: 3,
        ),
      );
    } else if (_areaVertices.length >= 2) {
      await controller.addOverlay(
        NPolylineOverlay(
          id: 'play_area_line',
          coords: _areaVertices,
          color: const Color(0xFF1D4ED8),
          width: 3,
        ),
      );
    }
  }

  Future<void> _drawControlPoints(NaverMapController controller) async {
    for (var index = 0; index < _controlPoints.length; index += 1) {
      final currentContext = context;
      if (!currentContext.mounted) return;
      final icon = await NOverlayImage.fromWidget(
        widget: _NumberDot(
          label: 'CP${index + 1}',
          color: const Color(0xFFF59E0B),
        ),
        size: const Size(42, 42),
        context: currentContext,
      );
      await controller.addOverlay(
        NMarker(
          id: 'control_point_$index',
          position: _controlPoints[index],
          icon: icon,
        ),
      );
    }
  }

  Future<void> _drawSpawnZones(NaverMapController controller) async {
    for (final team in _teams) {
      final center = _spawnCenters[team.teamId];
      if (center == null) continue;

      final color = _hexToColor(team.color);
      await controller.addOverlay(
        NCircleOverlay(
          id: 'spawn_${team.teamId}',
          center: center,
          radius: _spawnRadiusMeters,
          color: color.withValues(alpha: 0.12),
          outlineColor: color,
          outlineWidth: 3,
        ),
      );

      final currentContext = context;
      if (!currentContext.mounted) return;
      final icon = await NOverlayImage.fromWidget(
        widget: _SpawnBadge(
          label: team.displayName,
          color: color,
          selected: _selectedTeamId == team.teamId,
        ),
        size: const Size(96, 44),
        context: currentContext,
      );

      await controller.addOverlay(
        NMarker(
          id: 'spawn_marker_${team.teamId}',
          position: center,
          icon: icon,
        ),
      );
    }
  }

  void _onMapTapped(NPoint point, NLatLng latLng) {
    if (_isSaving || _isLoading) return;

    setState(() {
      switch (_step) {
        case _LayoutStep.area:
          _areaVertices.add(latLng);
          break;
        case _LayoutStep.controlPoints:
          if (_controlPoints.length < _controlPointCount) {
            _controlPoints.add(latLng);
          }
          break;
        case _LayoutStep.spawns:
          final targetTeamId =
              _selectedTeamId ?? (_teams.isNotEmpty ? _teams.first.teamId : null);
          if (targetTeamId == null) return;
          _spawnCenters[targetTeamId] = latLng;
          _selectedTeamId = _nextUnplacedTeamId() ?? targetTeamId;
          break;
      }
    });

    unawaited(_refreshOverlays());
  }

  void _undo() {
    if (_isSaving) return;

    setState(() {
      switch (_step) {
        case _LayoutStep.area:
          if (_areaVertices.isNotEmpty) {
            _areaVertices.removeLast();
          }
          break;
        case _LayoutStep.controlPoints:
          if (_controlPoints.isNotEmpty) {
            _controlPoints.removeLast();
          }
          break;
        case _LayoutStep.spawns:
          final teamId = _selectedTeamId;
          if (teamId != null) {
            _spawnCenters.remove(teamId);
          }
          break;
      }
    });

    unawaited(_refreshOverlays());
  }

  void _clearCurrentStep() {
    if (_isSaving) return;

    setState(() {
      switch (_step) {
        case _LayoutStep.area:
          _areaVertices.clear();
          break;
        case _LayoutStep.controlPoints:
          _controlPoints.clear();
          break;
        case _LayoutStep.spawns:
          _spawnCenters.clear();
          _selectedTeamId = _teams.isNotEmpty ? _teams.first.teamId : null;
          break;
      }
    });

    unawaited(_refreshOverlays());
  }

  Future<void> _moveToCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final target = NLatLng(pos.latitude, pos.longitude);
      await _mapController?.updateCamera(
        NCameraUpdate.fromCameraPosition(
          NCameraPosition(target: target, zoom: 17),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져오지 못했습니다.')),
      );
    }
  }

  Future<void> _save() async {
    if (_areaVertices.length < 3) {
      _showMessage('플레이 구역 꼭짓점을 최소 3개 이상 찍어주세요.');
      return;
    }

    if (_isFantasyWars && _controlPoints.length != _controlPointCount) {
      _showMessage('점령지 $_controlPointCount개를 배치해주세요.');
      return;
    }

    if (_isFantasyWars && _spawnCenters.length != _teams.length) {
      _showMessage('모든 팀의 시작 지점을 배치해주세요.');
      return;
    }

    setState(() => _isSaving = true);
    final navigator = Navigator.of(context);

    try {
      if (_isFantasyWars) {
        final session = await ref.read(sessionRepositoryProvider).setFantasyWarsLayout(
              widget.sessionId,
              playableArea: _areaVertices
                  .map((point) => {
                        'lat': point.latitude,
                        'lng': point.longitude,
                      })
                  .toList(),
              controlPoints: _controlPoints
                  .map((point) => {
                        'lat': point.latitude,
                        'lng': point.longitude,
                      })
                  .toList(),
              spawnZones: _teams.map((team) {
                final center = _spawnCenters[team.teamId]!;
                return {
                  'teamId': team.teamId,
                  'polygonPoints': _buildSpawnPolygon(center),
                };
              }).toList(),
            );

        if (!mounted) return;
        navigator.pop(session);
        return;
      }

      final saved = await ref.read(sessionRepositoryProvider).setPlayableArea(
            widget.sessionId,
            _areaVertices
                .map((point) => {
                      'lat': point.latitude,
                      'lng': point.longitude,
                    })
                .toList(),
          );
      if (!mounted) return;
      navigator.pop(saved);
    } catch (e) {
      _showMessage('저장 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  List<Map<String, double>> _buildSpawnPolygon(NLatLng center) {
    final points = <Map<String, double>>[];
    for (var index = 0; index < 6; index += 1) {
      final angle = (math.pi * 2 * index) / 6;
      final latOffset =
          (_spawnRadiusMeters / 111320.0) * math.sin(angle);
      final lngOffset =
          (_spawnRadiusMeters /
                  (111320.0 * math.cos(center.latitude * math.pi / 180))) *
              math.cos(angle);

      points.add({
        'lat': center.latitude + latOffset,
        'lng': center.longitude + lngOffset,
      });
    }
    return points;
  }

  NLatLng _polygonCenter(List<Map<String, double>> polygon) {
    if (polygon.isEmpty) {
      return _initialPosition;
    }

    final lat = polygon.fold<double>(0, (sum, point) => sum + point['lat']!) /
        polygon.length;
    final lng = polygon.fold<double>(0, (sum, point) => sum + point['lng']!) /
        polygon.length;
    return NLatLng(lat, lng);
  }

  String? _nextUnplacedTeamId() {
    for (final team in _teams) {
      if (!_spawnCenters.containsKey(team.teamId)) {
        return team.teamId;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 7) {
      buffer.write('ff');
    }
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final teamButtons = _teams
        .map(
          (team) => ChoiceChip(
            label: Text(team.displayName),
            selected: _selectedTeamId == team.teamId,
            selectedColor: _hexToColor(team.color).withValues(alpha: 0.18),
            onSelected: _step == _LayoutStep.spawns
                ? (_) => setState(() => _selectedTeamId = team.teamId)
                : null,
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFantasyWars ? '전장 설정' : '플레이 구역 설정',
        ),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _undo,
            icon: const Icon(Icons.undo),
            tooltip: '실행 취소',
          ),
          IconButton(
            onPressed: _isSaving ? null : _clearCurrentStep,
            icon: const Icon(Icons.delete_outline),
            tooltip: '현재 단계 지우기',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                NaverMap(
                  options: NaverMapViewOptions(
                    initialCameraPosition: NCameraPosition(
                      target: _initialPosition,
                      zoom: 17,
                    ),
                  ),
                  onMapReady: (controller) {
                    _mapController = controller;
                    unawaited(_refreshOverlays());
                  },
                  onMapTapped: _onMapTapped,
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<_LayoutStep>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: _LayoutStep.area,
                                label: Text('구역'),
                              ),
                              ButtonSegment(
                                value: _LayoutStep.controlPoints,
                                label: Text('점령지'),
                              ),
                              ButtonSegment(
                                value: _LayoutStep.spawns,
                                label: Text('팀 시작 지점'),
                              ),
                            ],
                            selected: {_step},
                            onSelectionChanged: (selection) {
                              setState(() => _step = selection.first);
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(_stepDescription()),
                          const SizedBox(height: 8),
                          Text(
                            _statusLine(),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_step == _LayoutStep.controlPoints) ...[
                            const SizedBox(height: 8),
                            Text(
                              '배치됨 ${_controlPoints.length} / $_controlPointCount',
                            ),
                          ],
                          if (_step == _LayoutStep.spawns) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: teamButtons,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 96,
                  child: FloatingActionButton.small(
                    heroTag: 'layout_my_location',
                    onPressed: _moveToCurrentPosition,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving
                          ? '저장 중...'
                          : (_isFantasyWars ? '전장 저장' : '설정 저장'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _stepDescription() {
    switch (_step) {
      case _LayoutStep.area:
        return '지도를 눌러 전체 플레이 전장 경계를 그려주세요.';
      case _LayoutStep.controlPoints:
        return '플레이 구역 안에 점령지 5개를 배치해주세요.';
      case _LayoutStep.spawns:
        return '길드를 선택한 뒤 지도를 눌러 시작 및 리스폰 지점을 배치해주세요.';
    }
  }

  String _statusLine() {
    switch (_step) {
      case _LayoutStep.area:
        return '구역 꼭짓점: ${_areaVertices.length}';
      case _LayoutStep.controlPoints:
        return '점령지: ${_controlPoints.length} / $_controlPointCount';
      case _LayoutStep.spawns:
        return '길드 시작 지점: ${_spawnCenters.length} / ${_teams.length}';
    }
  }
}

class _NumberDot extends StatelessWidget {
  const _NumberDot({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _SpawnBadge extends StatelessWidget {
  const _SpawnBadge({
    required this.label,
    required this.color,
    required this.selected,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? color : color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: selected ? 2 : 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
