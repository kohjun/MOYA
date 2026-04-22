// lib/features/history/data/history_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 모델
// ─────────────────────────────────────────────────────────────────────────────

class TrackPoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? battery;
  final String status;
  final DateTime recordedAt;

  const TrackPoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.speed,
    this.heading,
    this.battery,
    required this.status,
    required this.recordedAt,
  });

  factory TrackPoint.fromMap(Map<String, dynamic> m) => TrackPoint(
        lat:        (m['lat']      as num).toDouble(),
        lng:        (m['lng']      as num).toDouble(),
        accuracy:   (m['accuracy'] as num?)?.toDouble(),
        speed:      (m['speed']    as num?)?.toDouble(),
        heading:    (m['heading']  as num?)?.toDouble(),
        battery:    m['battery']   as int?,
        status:     m['status']    as String? ?? 'moving',
        recordedAt: DateTime.parse(m['recorded_at'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class HistoryRepository {
  final ApiClient _api = ApiClient();

  /// GET /sessions/:sessionId/track/:userId?from=&to=&limit=
  Future<List<TrackPoint>> getTrackHistory(
    String sessionId,
    String userId, {
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (from != null) params['from'] = from.toUtc().toIso8601String();
    if (to   != null) params['to']   = to.toUtc().toIso8601String();

    final res = await _api.get(
      '/sessions/$sessionId/track/$userId',
      queryParams: params,
    );

    final list = res.data['track'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(TrackPoint.fromMap)
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final historyRepositoryProvider = Provider((ref) => HistoryRepository());
