// 정적 지도 + CustomPaint 마커 오버레이.
//
// - 본인 위치: 본인 색 큰 원 (정체 보호: 다른 플레이어는 표시하지 않음)
// - 활성 거점: cyan 별 모양
// - playable_area 폴리곤 (옵션): 옅은 cyan 외곽선
//
// 정적 지도 이미지는 백엔드 프록시 (/maps/static) 를 통해 받는다.
// PlatformView 가 아니므로 frame drop 부담이 없다.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../../../core/network/api_client.dart';
import '../color_chaser_models.dart';
import 'cc_map_projection.dart';

class CcStaticMapView extends StatelessWidget {
  const CcStaticMapView({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.zoom,
    required this.width,
    required this.height,
    this.myLat,
    this.myLng,
    this.myColorHex,
    this.activeCp,
    this.playableArea = const [],
  });

  final double centerLat;
  final double centerLng;
  final int zoom;
  final double width;
  final double height;
  final double? myLat;
  final double? myLng;
  final String? myColorHex;
  final CcControlPoint? activeCp;
  final List<CcGeoPoint> playableArea;

  @override
  Widget build(BuildContext context) {
    // 디바이스 픽셀 비율을 반영해 이미지 해상도 요청.
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 3.0);
    final imgW = (width * dpr).round();
    final imgH = (height * dpr).round();
    final url =
        '$kApiBaseUrl/maps/static?lat=$centerLat&lng=$centerLng&zoom=$zoom&w=$imgW&h=$imgH';

    final size = Size(width, height);
    final projection = CcMapProjection(
      centerLat: centerLat,
      centerLng: centerLng,
      zoom: zoom,
      size: size,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade900,
                alignment: Alignment.center,
                child: const Text(
                  '지도를 불러올 수 없습니다',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.grey.shade900,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
            CustomPaint(
              painter: _CcMapOverlayPainter(
                projection: projection,
                myLat: myLat,
                myLng: myLng,
                myColor: _parseHex(myColorHex),
                activeCp: activeCp,
                playableArea: playableArea,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.white;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.white;
    return Color(0xFF000000 | value);
  }
}

class _CcMapOverlayPainter extends CustomPainter {
  _CcMapOverlayPainter({
    required this.projection,
    required this.myLat,
    required this.myLng,
    required this.myColor,
    required this.activeCp,
    required this.playableArea,
  });

  final CcMapProjection projection;
  final double? myLat;
  final double? myLng;
  final Color myColor;
  final CcControlPoint? activeCp;
  final List<CcGeoPoint> playableArea;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. playable_area 폴리곤
    if (playableArea.length >= 3) {
      final path = Path();
      bool first = true;
      for (final p in playableArea) {
        final px = projection.toPixel(p.lat, p.lng);
        if (first) {
          path.moveTo(px.dx, px.dy);
          first = false;
        } else {
          path.lineTo(px.dx, px.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.cyan.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 2. 활성 거점 (cyan pulse + 별)
    final cp = activeCp;
    if (cp != null && cp.location != null) {
      final p = projection.toPixel(cp.location!.lat, cp.location!.lng);
      // pulse halo
      canvas.drawCircle(
        p,
        18,
        Paint()..color = Colors.cyanAccent.withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        p,
        10,
        Paint()..color = Colors.cyanAccent,
      );
      // 작은 흰 가운데
      canvas.drawCircle(p, 4, Paint()..color = Colors.white);
    }

    // 3. 본인 위치 (본인 색 + 외곽 흰색)
    if (myLat != null && myLng != null) {
      final p = projection.toPixel(myLat!, myLng!);
      canvas.drawCircle(
        p,
        12,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        p,
        9,
        Paint()..color = myColor,
      );
      // 방향 인디케이터 (위쪽 작은 삼각형)
      final dir = Path()
        ..moveTo(p.dx, p.dy - 16)
        ..lineTo(p.dx - 4, p.dy - 8)
        ..lineTo(p.dx + 4, p.dy - 8)
        ..close();
      canvas.drawPath(dir, Paint()..color = myColor);
    }
  }

  @override
  bool shouldRepaint(covariant _CcMapOverlayPainter old) {
    return old.myLat != myLat ||
        old.myLng != myLng ||
        old.myColor != myColor ||
        old.activeCp != activeCp ||
        old.playableArea != playableArea;
  }
}

// 거리/방위에 따라 적절한 zoom level 추천.
// 게임 룸이 200m 안쪽이면 zoom 17, 500m 까지 zoom 16, 1km 까지 zoom 15.
int recommendedZoomForRadius(double radiusMeters) {
  if (radiusMeters <= 200) return 17;
  if (radiusMeters <= 500) return 16;
  if (radiusMeters <= 1000) return 15;
  return 14;
}

// playable_area 의 centroid 계산.
({double lat, double lng})? polygonCentroid(List<CcGeoPoint> polygon) {
  if (polygon.isEmpty) return null;
  double lat = 0;
  double lng = 0;
  for (final p in polygon) {
    lat += p.lat;
    lng += p.lng;
  }
  return (lat: lat / polygon.length, lng: lng / polygon.length);
}

// playable_area 의 최대 반경 추정 (centroid → 가장 먼 꼭짓점).
double polygonBoundingRadiusMeters(
  List<CcGeoPoint> polygon,
  double centerLat,
  double centerLng,
) {
  double maxDist = 0;
  for (final p in polygon) {
    final d = _haversine(centerLat, centerLng, p.lat, p.lng);
    if (d > maxDist) maxDist = d;
  }
  return maxDist;
}

double _haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
