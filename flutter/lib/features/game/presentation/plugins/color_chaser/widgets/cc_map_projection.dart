// Web Mercator 투영 헬퍼.
// 정적 지도 이미지의 (centerLat, centerLng, zoom, w, h) 정보로
// 임의의 (lat, lng) → 이미지 내 픽셀 좌표 변환.
//
// 네이버 지도도 Web Mercator(EPSG:3857) 사용.

import 'dart:math' as math;
import 'package:flutter/widgets.dart';

class CcMapProjection {
  const CcMapProjection({
    required this.centerLat,
    required this.centerLng,
    required this.zoom,
    required this.size,
  });

  final double centerLat;
  final double centerLng;
  final int zoom;
  final Size size;

  // 픽셀 / 도 (mercator world coord). zoom=0 일 때 256px = 360°.
  double get _worldPixels => 256.0 * math.pow(2, zoom);

  double _projectX(double lng) => (lng + 180) / 360 * _worldPixels;

  double _projectY(double lat) {
    final sinLat = math.sin(lat * math.pi / 180);
    final clamped = sinLat.clamp(-0.9999, 0.9999);
    return (0.5 -
            math.log((1 + clamped) / (1 - clamped)) / (4 * math.pi)) *
        _worldPixels;
  }

  /// (lat, lng) → 이미지 픽셀 좌표 (origin = top-left, x→오른쪽, y→아래).
  Offset toPixel(double lat, double lng) {
    final cx = _projectX(centerLng);
    final cy = _projectY(centerLat);
    final px = _projectX(lng);
    final py = _projectY(lat);
    return Offset(
      size.width / 2 + (px - cx),
      size.height / 2 + (py - cy),
    );
  }

  bool contains(double lat, double lng) {
    final p = toPixel(lat, lng);
    return p.dx >= 0 && p.dx <= size.width && p.dy >= 0 && p.dy <= size.height;
  }
}
