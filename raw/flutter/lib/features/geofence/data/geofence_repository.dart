// lib/features/geofence/data/geofence_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 모델
// ─────────────────────────────────────────────────────────────────────────────

class Geofence {
  final String id;
  final String sessionId;
  final String createdBy;
  final String name;
  final double lat;
  final double lng;
  final double radiusM;
  final bool notifyEnter;
  final bool notifyExit;
  final DateTime createdAt;

  const Geofence({
    required this.id,
    required this.sessionId,
    required this.createdBy,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.notifyEnter,
    required this.notifyExit,
    required this.createdAt,
  });

  factory Geofence.fromMap(Map<String, dynamic> m) => Geofence(
        id:          m['id']          as String? ?? '',
        sessionId:   m['session_id']  as String? ?? '',
        createdBy:   m['created_by']  as String? ?? '',
        name:        m['name']        as String? ?? '',
        lat:         (m['lat']        as num?)?.toDouble() ?? 0.0,
        lng:         (m['lng']        as num?)?.toDouble() ?? 0.0,
        radiusM:     (m['radius_m']   as num?)?.toDouble() ?? 100.0,
        notifyEnter: m['notify_enter'] as bool? ?? true,
        notifyExit:  m['notify_exit']  as bool? ?? true,
        createdAt:   DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class GeofenceRepository {
  final ApiClient _api = ApiClient();

  Future<List<Geofence>> getGeofences(String sessionId) async {
    final res = await _api.get('/sessions/$sessionId/geofences');
    final list = res.data['geofences'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Geofence.fromMap)
        .toList();
  }

  Future<Geofence> createGeofence(
    String sessionId, {
    required String name,
    required double centerLat,
    required double centerLng,
    required double radiusM,
    bool notifyEnter = true,
    bool notifyExit  = true,
  }) async {
    final res = await _api.post(
      '/sessions/$sessionId/geofences',
      data: {
        'name':         name,
        'centerLat':    centerLat,
        'centerLng':    centerLng,
        'radiusM':      radiusM,
        'notifyEnter':  notifyEnter,
        'notifyExit':   notifyExit,
      },
    );
    return Geofence.fromMap(res.data['geofence'] as Map<String, dynamic>);
  }

  Future<void> deleteGeofence(String sessionId, String geofenceId) async {
    await _api.delete('/sessions/$sessionId/geofences/$geofenceId');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final geofenceRepositoryProvider = Provider((ref) => GeofenceRepository());
