import '../../../../../../core/services/fantasy_wars_proximity_service.dart';
import '../../../../../map/presentation/map_session_models.dart';
import '../../../../providers/fantasy_wars_provider.dart';
import 'fantasy_wars_geo_service.dart';

class FantasyWarsTargetingService {
  const FantasyWarsTargetingService({
    this.geo = const FantasyWarsGeoService(),
  });

  final FantasyWarsGeoService geo;

  FwControlPoint? nearestControlPoint(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final controlPoints = candidateControlPoints(fwState, mapState, myId);
    return controlPoints.isEmpty ? null : controlPoints.first;
  }

  List<FwControlPoint> candidateControlPoints(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final controlPoints = fwState.controlPoints
        .where((controlPoint) =>
            controlPoint.lat != null && controlPoint.lng != null)
        .toList();
    controlPoints.sort((a, b) {
      final aDistance =
          geo.distanceToControlPoint(a, mapState, myId) ?? double.infinity;
      final bDistance =
          geo.distanceToControlPoint(b, mapState, myId) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    return controlPoints;
  }

  List<String> candidateMemberIds({
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    required FwDuelProximityContext? Function(String userId) proximityForUser,
    bool includeSelf = false,
    bool nearbyOnly = false,
  }) {
    final ids = <String>{
      ...mapState.members.keys,
      ...mapState.memberDistances.keys,
    };
    if (includeSelf && myId != null) {
      ids.add(myId);
    }

    final candidates = ids.where((userId) {
      if (userId == myId && !includeSelf) {
        return false;
      }
      if (fwState.eliminatedPlayerIds.contains(userId)) {
        return false;
      }
      if (nearbyOnly && proximityForUser(userId) == null) {
        return false;
      }

      final memberGuildId = geo.guildIdForUser(fwState.guilds, userId);
      if (enemy) {
        return memberGuildId != null &&
            memberGuildId != fwState.myState.guildId;
      }
      if (userId == myId) {
        return true;
      }
      return memberGuildId != null && memberGuildId == fwState.myState.guildId;
    }).toList();

    candidates.sort((a, b) {
      final aDistance =
          geo.distanceToMember(a, mapState, myId) ?? double.infinity;
      final bDistance =
          geo.distanceToMember(b, mapState, myId) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    return candidates;
  }
}
