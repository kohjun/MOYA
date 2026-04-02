// lib/features/geofence/presentation/geofence_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/geofence_repository.dart';
import '../../auth/data/auth_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GeofenceScreen
// ─────────────────────────────────────────────────────────────────────────────
class GeofenceScreen extends ConsumerStatefulWidget {
  const GeofenceScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends ConsumerState<GeofenceScreen> {
  GoogleMapController? _mapCtrl;
  List<Geofence> _geofences = [];
  bool _loading = false;

  // ── 추가 모드 ──────────────────────────────────────────────────────────────
  bool _addMode = false;
  LatLng _mapCenter = const LatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    _loadGeofences();
  }

  // ── 로드 ──────────────────────────────────────────────────────────────────
  Future<void> _loadGeofences() async {
    setState(() => _loading = true);
    try {
      final list = await ref
          .read(geofenceRepositoryProvider)
          .getGeofences(widget.sessionId);
      if (!mounted) return;
      setState(() { _geofences = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showError('지오펜스 로드 실패: $e');
    }
  }

  // ── 추가 모드 토글 ────────────────────────────────────────────────────────
  void _toggleAddMode() {
    setState(() => _addMode = !_addMode);
  }

  // ── 추가 모드 확정: 현재 지도 중심 위치로 다이얼로그 열기 ───────────────────
  void _confirmAddLocation() {
    _showAddDialog(_mapCenter);
  }

  // ── 지도 탭으로도 추가 가능 (추가 모드 여부 무관) ─────────────────────────
  void _onMapTap(LatLng pos) {
    _showAddDialog(pos);
  }

  // ── 지도 카메라 이동 시 중심 좌표 갱신 ──────────────────────────────────
  void _onCameraMove(CameraPosition pos) {
    _mapCenter = pos.target;
  }

  // ── 추가 다이얼로그 ────────────────────────────────────────────────────────
  void _showAddDialog(LatLng pos) {
    // 추가 모드를 잠시 숨기되 해제하지는 않음 (다이얼로그 닫으면 모드 유지)
    final nameCtrl   = TextEditingController();
    final radiusCtrl = TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지오펜스 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 위치 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Color(0xFF2196F3)),
                  const SizedBox(width: 6),
                  Text(
                    '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '예: 학교, 집, 공원',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: radiusCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '반경 (m)',
                suffixText: 'm',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.radio_button_checked),
                helperText: '10 ~ 50,000m',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          // "저장 후 계속 추가" 버튼
          OutlinedButton(
            onPressed: () async {
              final name   = nameCtrl.text.trim();
              final radius = double.tryParse(radiusCtrl.text) ?? 100;
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _createGeofence(name, pos, radius);
              // 추가 모드 유지 → 바로 다음 지오펜스 추가 가능
              if (mounted) setState(() => _addMode = true);
            },
            child: const Text('저장 후 계속'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name   = nameCtrl.text.trim();
              final radius = double.tryParse(radiusCtrl.text) ?? 100;
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _createGeofence(name, pos, radius);
              if (mounted) setState(() => _addMode = false);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _createGeofence(String name, LatLng pos, double radius) async {
    try {
      await ref.read(geofenceRepositoryProvider).createGeofence(
            widget.sessionId,
            name:      name,
            centerLat: pos.latitude,
            centerLng: pos.longitude,
            radiusM:   radius,
          );
      await _loadGeofences();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" 지오펜스가 추가되었습니다'),
            action: SnackBarAction(
              label: '하나 더 추가',
              onPressed: () => setState(() => _addMode = true),
            ),
          ),
        );
      }
    } catch (e) {
      _showError('추가 실패: $e');
    }
  }

  Future<void> _deleteGeofence(Geofence fence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지오펜스 삭제'),
        content: Text('"${fence.name}"을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(geofenceRepositoryProvider)
          .deleteGeofence(widget.sessionId, fence.id);
      await _loadGeofences();
    } catch (e) {
      _showError('삭제 실패: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authProvider).valueOrNull?.id;
    final count = _geofences.length;

    final circles = <Circle>{
      for (final f in _geofences)
        Circle(
          circleId:    CircleId(f.id),
          center:      LatLng(f.lat, f.lng),
          radius:      f.radiusM,
          fillColor:   const Color(0xFF2196F3).withValues(alpha: 0.15),
          strokeColor: const Color(0xFF2196F3),
          strokeWidth: 2,
        ),
    };

    final markers = <Marker>{
      for (final f in _geofences)
        Marker(
          markerId:    MarkerId('fence_${f.id}'),
          position:    LatLng(f.lat, f.lng),
          infoWindow:  InfoWindow(
            title:   f.name,
            snippet: '반경 ${f.radiusM.round()}m',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('지오펜스'),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count개',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGeofences,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 추가 모드 안내 배너 ─────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _addMode ? 44 : 36,
            color: _addMode
                ? const Color(0xFF2196F3).withValues(alpha: 0.12)
                : Colors.grey[50],
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  _addMode ? Icons.touch_app : Icons.info_outline,
                  size: 16,
                  color: _addMode
                      ? const Color(0xFF2196F3)
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _addMode
                      ? '지도를 이동하거나 탭하여 위치를 선택하세요'
                      : '+ 버튼을 눌러 지오펜스를 추가하세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: _addMode
                        ? const Color(0xFF2196F3)
                        : Colors.grey,
                  ),
                ),
                if (_addMode) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _addMode = false),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 30),
                    ),
                    child: const Text('취소',
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                ],
              ],
            ),
          ),

          // ── 지도 ────────────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(37.5665, 126.9780),
                    zoom: 14.0,
                  ),
                  onMapCreated: (ctrl) => _mapCtrl = ctrl,
                  onTap: _onMapTap,
                  onCameraMove: _onCameraMove,
                  circles: circles,
                  markers: markers,
                  zoomControlsEnabled: false,
                  buildingsEnabled: false,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),

                // ── 추가 모드 십자선 ────────────────────────────────────
                if (_addMode) ...[
                  // 세로선
                  Container(
                    width: 1.5,
                    height: 40,
                    color: Colors.red.withValues(alpha: 0.8),
                  ),
                  // 가로선
                  Container(
                    width: 40,
                    height: 1.5,
                    color: Colors.red.withValues(alpha: 0.8),
                  ),
                  // 중심 원
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  // 하단 확정 버튼
                  Positioned(
                    bottom: 16,
                    child: ElevatedButton.icon(
                      onPressed: _confirmAddLocation,
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('이 위치에 추가'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],

                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),

          // ── 지오펜스 목록 ───────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: _geofences.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.radio_button_unchecked,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text(
                          '등록된 지오펜스가 없습니다',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '+ 버튼을 눌러 추가하세요',
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _geofences.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final f = _geofences[i];
                      final canDelete = f.createdBy == myId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3)
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Color(0xFF2196F3),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        title: Text(f.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        subtitle: Text(
                          '반경 ${f.radiusM.round()}m · ${f.lat.toStringAsFixed(4)}, ${f.lng.toStringAsFixed(4)}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                        trailing: canDelete
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                onPressed: () => _deleteGeofence(f),
                              )
                            : null,
                        onTap: () => _mapCtrl?.animateCamera(
                          CameraUpdate.newLatLngZoom(
                            LatLng(f.lat, f.lng),
                            _zoomForRadius(f.radiusM),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      // ── FAB: 추가 모드 토글 ──────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleAddMode,
        icon: Icon(_addMode ? Icons.close : Icons.add_location_alt),
        label: Text(_addMode ? '추가 취소' : '지오펜스 추가'),
        backgroundColor:
            _addMode ? Colors.red : const Color(0xFF2196F3),
        foregroundColor: Colors.white,
      ),
    );
  }

  double _zoomForRadius(double radiusM) {
    const worldPx = 256.0;
    const earthCircumM = 40075016.686;
    return math.log(earthCircumM / worldPx / (radiusM * 2)) / math.log(2) + 1;
  }
}
