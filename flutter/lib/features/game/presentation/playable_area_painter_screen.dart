// lib/features/game/presentation/playable_area_painter_screen.dart
//
// 호스트가 NaverMap 위에서 터치로 폴리곤(플레이 가능 영역)을 그리고
// 서버에 저장하는 화면입니다.
//
// 사용법 (로비 화면에서 호출):
//   await Navigator.push(context, MaterialPageRoute(
//     builder: (_) => PlayableAreaPainterScreen(sessionId: widget.sessionId),
//   ));

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../home/data/session_repository.dart';

class PlayableAreaPainterScreen extends ConsumerStatefulWidget {
  const PlayableAreaPainterScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<PlayableAreaPainterScreen> createState() =>
      _PlayableAreaPainterScreenState();
}

class _PlayableAreaPainterScreenState
    extends ConsumerState<PlayableAreaPainterScreen> {
  NaverMapController? _mapController;
  final List<NLatLng> _vertices = [];
  bool _isSaving = false;

  // 지도 초기 위치: 현재 GPS 위치 → 실패 시 서울 시청
  NLatLng _initialPosition = const NLatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _initialPosition = NLatLng(pos.latitude, pos.longitude);
      });
      _mapController?.updateCamera(
        NCameraUpdate.fromCameraPosition(
          NCameraPosition(target: _initialPosition, zoom: 17),
        ),
      );
    } catch (_) {
      // GPS 실패 → 기본 위치 유지
    }
  }

  // ── 폴리곤 오버레이 갱신 ───────────────────────────────────────────────────

  Future<void> _refreshOverlays() async {
    final ctrl = _mapController;
    if (ctrl == null) return;
    if (!mounted) return;

    // 기존 오버레이 전체 제거
    await ctrl.clearOverlays();

    if (_vertices.isEmpty) return;

    // 꼭짓점 마커 (NOverlayImage.fromWidget은 Future를 반환하므로 await 필요)
    for (int i = 0; i < _vertices.length; i++) {
      if (!mounted) return;
      final icon = await NOverlayImage.fromWidget(
        widget: _VertexDot(index: i + 1),
        size: const Size(28, 28),
        context: context,
      );
      if (!mounted) return;
      final marker = NMarker(
        id: 'v_$i',
        position: _vertices[i],
        icon: icon,
      );
      await ctrl.addOverlay(marker);
    }

    // 폴리곤이 3개 이상이면 채워진 폴리곤 표시
    if (_vertices.length >= 3) {
      final polygon = NPolygonOverlay(
        id: 'play_area',
        coords: _vertices,
        color: Colors.blue.withValues(alpha: 0.15),
        outlineColor: Colors.blue,
        outlineWidth: 2,
      );
      await ctrl.addOverlay(polygon);
    } else if (_vertices.length >= 2) {
      // 꼭짓점이 2개면 선만 표시
      final polyline = NPolylineOverlay(
        id: 'play_line',
        coords: _vertices,
        color: Colors.blue,
        width: 2,
      );
      await ctrl.addOverlay(polyline);
    }
  }

  // ── 지도 탭 핸들러 ─────────────────────────────────────────────────────────

  void _onMapTapped(NPoint point, NLatLng latLng) {
    if (_isSaving) return;
    setState(() => _vertices.add(latLng));
    _refreshOverlays();
  }

  // ── 마지막 꼭짓점 제거 ─────────────────────────────────────────────────────

  void _undoLastVertex() {
    if (_vertices.isEmpty || _isSaving) return;
    setState(() => _vertices.removeLast());
    _refreshOverlays();
  }

  // ── 전체 초기화 ────────────────────────────────────────────────────────────

  void _clearAll() {
    if (_isSaving) return;
    setState(() => _vertices.clear());
    _mapController?.clearOverlays();
  }

  // ── 내 위치로 이동 ─────────────────────────────────────────────────────────

  Future<void> _moveToCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _mapController?.updateCamera(
        NCameraUpdate.fromCameraPosition(
          NCameraPosition(
            target: NLatLng(pos.latitude, pos.longitude),
            zoom: 17,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')),
      );
    }
  }

  // ── 서버 저장 ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_vertices.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('플레이 영역은 최소 3개의 꼭짓점이 필요합니다.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final points = _vertices
          .map((v) => {'lat': v.latitude, 'lng': v.longitude})
          .toList();

      await ref
          .read(sessionRepositoryProvider)
          .setPlayableArea(widget.sessionId, points);

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('플레이 영역이 저장되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop(points); // 저장된 좌표를 호출자에게 반환
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── 빌드 ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text(
          '플레이 영역 설정',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: '마지막 꼭짓점 취소',
            icon: const Icon(Icons.undo_rounded),
            onPressed: _vertices.isEmpty ? null : _undoLastVertex,
          ),
          IconButton(
            tooltip: '전체 초기화',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _vertices.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── 네이버 지도 ────────────────────────────────────────────────────
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _initialPosition,
                zoom: 17,
              ),
              mapType: NMapType.basic,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) {
              _mapController = controller;
              _refreshOverlays();
            },
            onMapTapped: _onMapTapped,
          ),

          // ── 안내 배너 (꼭짓점 0개일 때만 표시) ──────────────────────────
          if (_vertices.isEmpty)
            Positioned(
              top: 16,
              left: 24,
              right: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '지도를 터치해 플레이 구역의 꼭짓점을 찍으세요.\n'
                  '최소 3개 이상을 찍어야 저장할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),

          // ── 꼭짓점 카운터 ──────────────────────────────────────────────
          if (_vertices.isNotEmpty)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '꼭짓점 ${_vertices.length}개',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // ── 내 위치 버튼 ───────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 104,
            child: FloatingActionButton.small(
              heroTag: 'my_location',
              onPressed: _moveToCurrentPosition,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              tooltip: '내 위치로 이동',
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // ── 저장 버튼 ──────────────────────────────────────────────────
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _vertices.length >= 3
                    ? const Color(0xFF4F46E5)
                    : Colors.grey.shade700,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: (_vertices.length >= 3 && !_isSaving) ? _save : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white),
              label: Text(
                _isSaving ? '저장 중…' : '이 영역으로 게임 시작',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 꼭짓점 번호 표시 위젯 ─────────────────────────────────────────────────────

class _VertexDot extends StatelessWidget {
  const _VertexDot({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: Text(
          '$index',
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
