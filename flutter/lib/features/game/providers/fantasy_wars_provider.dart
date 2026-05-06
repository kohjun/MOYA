import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/socket_service.dart';
import '../../auth/data/auth_repository.dart';
import '../presentation/plugins/fantasy_wars/notification_catalog.dart';
import '../presentation/plugins/fantasy_wars/services/fw_notification_service.dart';
import 'fantasy_wars_models.dart';
import 'fantasy_wars_parsers.dart';
import 'fantasy_wars_socket_client.dart';

export 'fantasy_wars_models.dart';
export 'fantasy_wars_socket_client.dart';

final fantasyWarsSocketClientProvider = Provider<FantasyWarsSocketClient>(
  (ref) => SocketServiceFantasyWarsClient(SocketService()),
);

final fantasyWarsCurrentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authProvider).valueOrNull?.id,
);

// 알림 dispatch — 운영 시 fwNotificationServiceProvider 의 notify 를 그대로 위임.
// 테스트는 notify 인자를 생략해 no-op 으로 둘 수 있다 (기존 fake 호환).
typedef FwNotifyDispatch = void Function(
  FwNotifyKind kind,
  Map<String, dynamic> params,
);

final fantasyWarsProvider = StateNotifierProvider.family<FantasyWarsNotifier,
    FantasyWarsGameState, String>(
  (ref, sessionId) {
    final notifyService = ref.read(fwNotificationServiceProvider);
    return FantasyWarsNotifier(
      sessionId: sessionId,
      socket: ref.read(fantasyWarsSocketClientProvider),
      getCurrentUserId: () => ref.read(fantasyWarsCurrentUserIdProvider),
      notify: (kind, params) {
        // notify 는 비동기 사운드 재생을 trigger 하지만 호출처는 await 하지 않는다.
        notifyService.notify(kind, params: params);
      },
    );
  },
);

class FantasyWarsNotifier extends StateNotifier<FantasyWarsGameState> {
  FantasyWarsNotifier({
    required String sessionId,
    required FantasyWarsSocketClient socket,
    required String? Function() getCurrentUserId,
    FwNotifyDispatch? notify,
  })  : _sessionId = sessionId,
        _socket = socket,
        _getCurrentUserId = getCurrentUserId,
        _notifyDispatch = notify,
        super(const FantasyWarsGameState()) {
    _subscribeAll();
    if (_socket.isConnected) {
      _requestStateNow();
    }
  }

  final String _sessionId;
  final FantasyWarsSocketClient _socket;
  final String? Function() _getCurrentUserId;
  final FwNotifyDispatch? _notifyDispatch;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _stateRefreshTimer;

  String? get _myUserId => _getCurrentUserId();

  void _notify(FwNotifyKind kind, [Map<String, dynamic> params = const {}]) {
    final dispatch = _notifyDispatch;
    if (dispatch == null) return;
    try {
      dispatch(kind, params);
    } catch (_) {
      // 알림 실패가 게임 흐름을 막지 않는다.
    }
  }

  StreamSubscription<T> _listen<T>(
    Stream<T> stream,
    void Function(T data) onData,
  ) {
    return stream.listen((data) {
      if (!mounted) return;
      onData(data);
    });
  }

  void _pushRecentEvent(
    String message, {
    String kind = 'system',
    int? recordedAt,
    String? primaryUserId,
    String? secondaryUserId,
    String? controlPointId,
  }) {
    final next = [
      FwRecentEvent(
        kind: kind,
        message: message,
        recordedAt: recordedAt ?? DateTime.now().millisecondsSinceEpoch,
        primaryUserId: primaryUserId,
        secondaryUserId: secondaryUserId,
        controlPointId: controlPointId,
      ),
      ...state.recentEvents,
    ];
    state = state.copyWith(
      recentEvents: next.take(12).toList(growable: false),
    );
  }

  String _guildLabel(String? guildId) {
    if (guildId == null || guildId.isEmpty) {
      return 'unknown guild';
    }
    return state.guilds[guildId]?.displayName ?? guildId;
  }

  String _controlPointLabel(String? controlPointId) {
    if (controlPointId == null || controlPointId.isEmpty) {
      return 'unknown point';
    }
    for (final controlPoint in state.controlPoints) {
      if (controlPoint.id == controlPointId) {
        return controlPoint.displayName;
      }
    }
    return controlPointId;
  }

  String _playerLabel(String? userId) {
    if (userId == null || userId.isEmpty) {
      return 'unknown player';
    }
    return userId == _myUserId ? 'you' : userId;
  }

  String _skillLabel(String? type) => switch (type) {
        'blockade' => 'Blockade',
        'shield' => 'Shield',
        'reveal' => 'Reveal',
        'execution' => 'Execution',
        _ => type ?? 'Skill',
      };

  void _subscribeAll() {
    _subs.add(_listen(_socket.onConnectionChange, (connected) {
      if (connected) {
        _requestStateNow();
      }
    }));

    _subs.add(_listen(
      _socket.onGameStateUpdate,
      (data) => _handleStateUpdate(Map<String, dynamic>.from(data as Map)),
    ));

    _subs.add(_listen(_socket.onGameEvent(SocketService.gameStarted), (data) {
      _handleStateUpdate({...data, 'status': 'in_progress'});
      _pushRecentEvent('Match started', kind: 'match');
    }));

    _subs.add(_listen(_socket.onGameEvent(SocketService.gameOver), (data) {
      state = state.copyWith(
        status: 'finished',
        winCondition: Map<String, dynamic>.from(data),
      );
      final winner = data['winner'] as String?;
      final reason = data['reason'] as String?;
      _pushRecentEvent(
        'Game over | winner ${winner == null ? 'unknown' : _guildLabel(winner)}${reason == null ? '' : ' | $reason'}',
        kind: 'match',
      );
      // 게임 종료 알림: 우리 길드 승리 / 다른 길드 승리
      final myGuildId = state.myState.guildId;
      if (winner != null && myGuildId != null) {
        if (winner == myGuildId) {
          _notify(FwNotifyKind.gameWon, const {});
        } else {
          _notify(FwNotifyKind.gameLost, const {});
        }
      }
    }));

    _subs.add(_listen(_socket.onGameEvent(SocketService.fwDuelLog), (data) {
      final message = data['message'] as String?;
      if (message == null || message.isEmpty) {
        return;
      }
      final winnerId = data['winnerId'] as String?;
      final loserId = data['loserId'] as String?;
      final challengerId = data['challengerId'] as String?;
      final targetId = data['targetId'] as String?;
      _pushRecentEvent(
        message,
        kind: data['kind'] as String? ?? 'duel',
        recordedAt: (data['recordedAt'] as num?)?.toInt(),
        primaryUserId: winnerId ?? challengerId ?? targetId,
        secondaryUserId: loserId ??
            (targetId != winnerId ? targetId : null) ??
            (challengerId != winnerId ? challengerId : null),
      );
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:capture_progress'), (data) {
      _mutateControlPoint(data['controlPointId'] as String?, (cp) {
        return cp.copyWith(
          capturingGuild: data['guildId'] as String?,
          readyCount: (data['readyCount'] as num?)?.toInt() ?? cp.readyCount,
          requiredCount:
              (data['requiredCount'] as num?)?.toInt() ?? cp.requiredCount,
        );
      });
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:capture_started'), (data) {
      final controlPointLabel =
          _controlPointLabel(data['controlPointId'] as String?);
      final guildLabel = _guildLabel(data['guildId'] as String?);
      // 적 길드가 점령을 시작 → 경고 알림 (dedupe 8s 로 한 점령 시도 동안 1회만)
      final myGuildId = state.myState.guildId;
      if (myGuildId != null &&
          data['guildId'] != null &&
          data['guildId'] != myGuildId) {
        _notify(FwNotifyKind.cpBeingCapturedByEnemy, {
          'cpName': controlPointLabel,
          'guildName': guildLabel,
        });
      }
      _mutateControlPoint(data['controlPointId'] as String?, (cp) {
        return cp.copyWith(
          capturingGuild: data['guildId'] as String?,
          captureStartedAt: (data['startedAt'] as num?)?.toInt(),
          captureDurationSec: (data['durationSec'] as num?)?.toInt(),
          captureProgress: 0,
          readyCount: 0,
          requiredCount: 0,
        );
      });
      _pushRecentEvent(
        'Capture started | $controlPointLabel | $guildLabel',
        kind: 'capture',
        controlPointId: data['controlPointId'] as String?,
      );
      if (data['guildId'] == state.myState.guildId) {
        _scheduleStateRefresh();
      }
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:capture_complete'), (data) {
      final controlPointLabel =
          _controlPointLabel(data['controlPointId'] as String?);
      final guildLabel = _guildLabel(data['capturedBy'] as String?);
      _mutateControlPoint(data['controlPointId'] as String?, (cp) {
        return cp.copyWith(
          capturedBy: data['capturedBy'] as String?,
          capturingGuild: null,
          captureStartedAt: null,
          captureProgress: 100,
          readyCount: 0,
          requiredCount: 0,
        );
      });
      _pushRecentEvent(
        'Capture secured | $controlPointLabel | $guildLabel',
        kind: 'capture',
        controlPointId: data['controlPointId'] as String?,
      );
      // 점령 완료: 우리 길드면 확보 알림, 아니면 빼앗김 알림
      final myGuildId = state.myState.guildId;
      if (myGuildId != null && data['capturedBy'] != null) {
        if (data['capturedBy'] == myGuildId) {
          _notify(FwNotifyKind.cpCapturedByUs, {
            'cpName': controlPointLabel,
          });
        } else {
          _notify(FwNotifyKind.cpCapturedByEnemy, {
            'cpName': controlPointLabel,
            'guildName': guildLabel,
          });
        }
      }
      _scheduleStateRefresh();
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:capture_cancelled'), (data) {
      final controlPointLabel =
          _controlPointLabel(data['controlPointId'] as String?);
      final interruptedByGuild =
          _guildLabel(data['interruptedByGuild'] as String?);
      final reason = data['reason'] as String?;
      _mutateControlPoint(data['controlPointId'] as String?, (cp) {
        return cp.copyWith(
          capturingGuild: null,
          captureStartedAt: null,
          captureProgress: 0,
          readyCount: 0,
          requiredCount: 0,
        );
      });
      _pushRecentEvent(
        'Capture cancelled | $controlPointLabel${reason == null ? '' : ' | $reason'}${data['interruptedByGuild'] == null ? '' : ' | by $interruptedByGuild'}',
        kind: 'capture',
        controlPointId: data['controlPointId'] as String?,
      );
      // 적 마법사가 봉쇄로 우리 점령을 끊었을 때 알림
      final myGuildIdForBlockade = state.myState.guildId;
      if (reason == 'blockaded' &&
          myGuildIdForBlockade != null &&
          data['interruptedGuild'] == myGuildIdForBlockade) {
        _notify(FwNotifyKind.cpBlockadedAgainstUs, {
          'cpName': controlPointLabel,
        });
      }
      // 새로고침이 필요한 경우:
      //  - 내 길드가 직접 cancel/disrupt 한 길드인 경우 (guildId / interruptedByGuild)
      //  - 내 길드가 disrupt 당해서 점령이 끊긴 길드인 경우 (interruptedGuild). 이 분기를
      //    누락하면 myState.captureZone 등 사적 상태가 stale 로 남아 점령 / 결투 UI 가
      //    잠긴 채 유지된다.
      final myGuildId = state.myState.guildId;
      if (data['guildId'] == myGuildId ||
          data['interruptedByGuild'] == myGuildId ||
          data['interruptedGuild'] == myGuildId) {
        _scheduleStateRefresh();
      }
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:player_attacked'), (data) {
      final myUserId = _myUserId;
      if (myUserId == null) {
        return;
      }
      if (data['targetId'] == myUserId) {
        state = state.copyWith(
          myState: state.myState.copyWith(
            hp: (data['targetHp'] as num?)?.toInt() ?? state.myState.hp,
          ),
        );
      }
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:player_eliminated'), (data) {
      final eliminatedId = data['userId'] as String?;
      if (eliminatedId == null) {
        return;
      }
      final killerId = data['killedBy'] as String?;

      final alive =
          state.alivePlayerIds.where((id) => id != eliminatedId).toList();
      final eliminated =
          <String>{...state.eliminatedPlayerIds, eliminatedId}.toList();
      state = state.copyWith(
        alivePlayerIds: alive,
        eliminatedPlayerIds: eliminated,
      );
      _pushRecentEvent(
        'Player eliminated | ${_playerLabel(eliminatedId)}${killerId == null ? '' : ' | by ${_playerLabel(killerId)}'}',
        kind: 'combat',
        primaryUserId: eliminatedId,
        secondaryUserId: killerId,
      );

      if (eliminatedId == _myUserId) {
        state = state.copyWith(
          myState: state.myState.copyWith(
            isAlive: false,
            hp: 0,
            inDuel: false,
            dungeonEntered: false,
            reviveReady: false,
            nextReviveAt: null,
            captureZone: null,
          ),
        );
        _scheduleStateRefresh();
        _notify(FwNotifyKind.eliminatedSelf, const {});
      }
      // 우리 길드 마스터 탈락 → 위기 알림 (자기 탈락과 별개로 추가 발화 가능)
      final myGuildId = state.myState.guildId;
      final myGuildMasterId = myGuildId == null
          ? null
          : state.guilds[myGuildId]?.guildMasterId;
      if (myGuildMasterId != null && eliminatedId == myGuildMasterId) {
        _notify(FwNotifyKind.masterEliminatedUs, const {});
      }
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:player_revived'), (data) {
      final revivedId = data['targetUserId'] as String?;
      if (revivedId == null) {
        return;
      }

      final eliminated =
          state.eliminatedPlayerIds.where((id) => id != revivedId).toList();
      final alive = <String>{...state.alivePlayerIds, revivedId}.toList();
      state = state.copyWith(
        alivePlayerIds: alive,
        eliminatedPlayerIds: eliminated,
      );
      _pushRecentEvent(
        'Player revived | ${_playerLabel(revivedId)}',
        kind: 'revive',
        primaryUserId: revivedId,
      );

      if (revivedId == _myUserId) {
        state = state.copyWith(
          myState: state.myState.copyWith(
            isAlive: true,
            hp: 100,
            remainingLives: state.myState.job == 'warrior' ? 2 : 1,
            dungeonEntered: false,
            reviveReady: false,
            nextReviveAt: null,
            nextReviveChance: null,
          ),
        );
        _scheduleStateRefresh();
        _notify(FwNotifyKind.revived, const {});
      }
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:revive_failed'), (data) {
      final targetUserId = data['targetUserId'] as String?;
      if (targetUserId == null || targetUserId != _myUserId) {
        return;
      }

      state = state.copyWith(
        myState: state.myState.copyWith(
          dungeonEntered: true,
          reviveReady: false,
          nextReviveAt: (data['nextAttemptAt'] as num?)?.toInt(),
          nextReviveChance: (data['nextChance'] as num?)?.toDouble(),
        ),
      );
      _pushRecentEvent(
        'Revive failed | ${_playerLabel(targetUserId)}',
        kind: 'revive',
        primaryUserId: targetUserId,
      );
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:revive_ready'), (data) {
      final targetUserId = data['targetUserId'] as String?;
      if (targetUserId == null || targetUserId != _myUserId) {
        return;
      }
      state = state.copyWith(
        myState: state.myState.copyWith(
          dungeonEntered: true,
          reviveReady: true,
          nextReviveAt: null,
        ),
      );
      _pushRecentEvent(
        'Revive ready | ${_playerLabel(targetUserId)}',
        kind: 'revive',
        primaryUserId: targetUserId,
      );
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:skill_cooldown'), (data) {
      final skill = data['skill'] as String?;
      final remainSec = (data['remainSec'] as num?)?.toInt() ?? 0;
      if (skill == null) {
        return;
      }

      final updated = Map<String, int>.from(state.myState.skillUsedAt)
        ..[skill] = DateTime.now().millisecondsSinceEpoch + remainSec * 1000;

      state = state.copyWith(
        myState: state.myState.copyWith(skillUsedAt: updated),
      );
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:skill_used'), (data) {
      final skill = data['skill'] as String?;
      if (skill == null) {
        return;
      }
      final cooldownMs = cooldownMsForSkill(skill);
      if (cooldownMs <= 0) {
        return;
      }

      final updated = Map<String, int>.from(state.myState.skillUsedAt)
        ..[skill] = DateTime.now().millisecondsSinceEpoch + cooldownMs;
      state = state.copyWith(
        myState: state.myState.copyWith(skillUsedAt: updated),
      );
    }));

    _subs.add(_listen(_socket.onGameEvent('fw:player_skill'), (data) {
      final actorId = data['userId'] as String?;
      final result =
          (data['result'] as Map?)?.cast<String, dynamic>() ?? const {};
      final type = result['type'] as String?;
      if (type == null) {
        return;
      }

      switch (type) {
        case 'blockade':
          final cpId = result['cpId'] as String?;
          final actorGuildId =
              actorId == null ? null : _guildIdForUser(actorId);
          _mutateControlPoint(cpId, (cp) {
            return cp.copyWith(
              blockadedBy: actorGuildId,
              blockadeExpiresAt: (result['expiresAt'] as num?)?.toInt(),
            );
          });
          _pushRecentEvent(
            'Skill used | ${_playerLabel(actorId)} | ${_skillLabel(type)} | ${_controlPointLabel(cpId)}',
            kind: 'skill',
            primaryUserId: actorId,
            controlPointId: cpId,
          );
          break;
        case 'shield':
          final targetUserId = result['targetUserId'] as String?;
          _pushRecentEvent(
            'Skill used | ${_playerLabel(actorId)} | ${_skillLabel(type)} | ${_playerLabel(targetUserId)}',
            kind: 'skill',
            primaryUserId: targetUserId ?? actorId,
            secondaryUserId: targetUserId != null && targetUserId != actorId
                ? actorId
                : null,
          );
          if (targetUserId == _myUserId) {
            state = state.copyWith(
              myState: state.myState.copyWith(
                shieldCount: (result['shieldCount'] as num?)?.toInt() ??
                    state.myState.shieldCount + 1,
              ),
            );
            _scheduleStateRefresh();
          }
          break;
        case 'reveal':
          _pushRecentEvent(
            'Skill used | ${_playerLabel(actorId)} | ${_skillLabel(type)} | ${_playerLabel(result['targetUserId'] as String?)}',
            kind: 'skill',
            primaryUserId: result['targetUserId'] as String? ?? actorId,
            secondaryUserId: actorId,
          );
          if (actorId == _myUserId) {
            state = state.copyWith(
              myState: state.myState.copyWith(
                revealUntil: (result['revealUntil'] as num?)?.toInt(),
                trackedTargetUserId: result['targetUserId'] as String?,
              ),
            );
            _scheduleStateRefresh();
          }
          break;
        case 'execution':
          _pushRecentEvent(
            'Skill used | ${_playerLabel(actorId)} | ${_skillLabel(type)}',
            kind: 'skill',
            primaryUserId: actorId,
          );
          if (actorId == _myUserId) {
            state = state.copyWith(
              myState: state.myState.copyWith(
                executionArmedUntil: (result['armedUntil'] as num?)?.toInt(),
              ),
            );
            _scheduleStateRefresh();
          }
          break;
      }
    }));

    _subs.add(_listen(_socket.onFwDuelChallenged, (data) {
      if (data['self'] == true) {
        return;
      }
      state = state.copyWith(
        duel: FwDuelState(
          duelId: data['duelId'] as String?,
          opponentId: data['challengerId'] as String?,
          phase: 'challenged',
        ),
      );
      // 결투 신청 도착 알림 (도전자 측만 self=true 라 여기는 수신자 케이스만 도달)
      _notify(FwNotifyKind.duelChallengedToMe, {
        'opponentName': _playerLabel(data['challengerId'] as String?),
      });
    }));

    _subs.add(_listen(_socket.onFwDuelAccepted, (data) {
      if (state.duel.phase != 'challenging') {
        return;
      }
      state = state.copyWith(
        duel: state.duel.copyWith(
          duelId: data['duelId'] as String? ?? state.duel.duelId,
        ),
      );
    }));

    _subs.add(_listen(_socket.onFwDuelRejected, (_) {
      state = state.copyWith(duel: const FwDuelState());
    }));

    _subs.add(_listen(_socket.onFwDuelCancelled, (_) {
      state = state.copyWith(duel: const FwDuelState());
    }));

    _subs.add(_listen(_socket.onFwDuelStarted, (data) {
      final rawParams = data['params'];
      final params = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : <String, dynamic>{};
      state = state.copyWith(
        duel: FwDuelState(
          duelId: data['duelId'] as String?,
          opponentId: state.duel.opponentId,
          phase: 'in_game',
          minigameType: data['minigameType'] as String?,
          minigameParams: params,
        ),
        myState: state.myState.copyWith(
          inDuel: true,
          duelExpiresAt: (data['startedAt'] as num?)?.toInt() == null
              ? state.myState.duelExpiresAt
              : ((data['startedAt'] as num).toInt() +
                  ((data['gameTimeoutMs'] as num?)?.toInt() ?? 30000)),
        ),
      );
    }));

    _subs.add(_listen(_socket.onFwDuelResult, (data) {
      // 이중 안전망: 서버는 더 이상 sendToSession 으로 result 를 broadcast 하지 않지만,
      // 잘못 전파된 event 가 비참가자에 도달해도 자기 duel state 를 덮어쓰지 않도록
      // duelId 를 비교. 본인이 진행 중이던 결투 결과만 반영한다.
      final eventDuelId = data['duelId'] as String?;
      final myDuelId = state.duel.duelId;
      if (eventDuelId != null && myDuelId != null && eventDuelId != myDuelId) {
        return;
      }
      final result = FwDuelResult.fromMap(data);
      state = state.copyWith(
        duel: state.duel.copyWith(
          phase: 'result',
          duelResult: result,
        ),
        myState: state.myState.copyWith(
          inDuel: false,
          duelExpiresAt: null,
        ),
      );
      _scheduleStateRefresh();
      // 결투 결과 알림: 승리/패배/실드 흡수
      final myUserId = _myUserId;
      if (myUserId != null) {
        if (result.winnerId != null && result.winnerId == myUserId) {
          _notify(FwNotifyKind.duelWon, const {});
        } else if (result.loserId != null && result.loserId == myUserId) {
          _notify(FwNotifyKind.duelLost, const {});
        }
        if (result.shieldAbsorbed &&
            (result.winnerId == myUserId || result.loserId == myUserId)) {
          _notify(FwNotifyKind.shieldConsumed, const {});
        }
      }
      // result 는 자동 dismiss 하지 않는다. 사용자가 결과 화면의 "전장으로" CTA 를
      // 눌러야 clearDuelResult() 가 호출된다. (3초 자동 clear 는 high-pressure
      // 흐름에서 정보 누락의 직접 원인이었음.)
    }));

    // 본 게임 타이머가 서버에서 가동된 시점 (VS+briefing 종료 직후) 의 startedAt 으로
    // duelExpiresAt 를 다시 계산. fw:duel:started 의 accept-time 기준 expiry 는
    // pre-play 길이만큼 짧아 로컬 타이머/배너 가 조기 만료되는 문제를 해소한다.
    _subs.add(_listen(_socket.onFwDuelPlayArmed, (data) {
      final startedAt = (data['startedAt'] as num?)?.toInt();
      final timeoutMs = (data['gameTimeoutMs'] as num?)?.toInt();
      if (startedAt == null || timeoutMs == null) return;
      state = state.copyWith(
        myState: state.myState.copyWith(
          duelExpiresAt: startedAt + timeoutMs,
        ),
      );
    }));

    // 턴 기반 미니게임의 새 public state. params.state 만 갱신해 RR 위젯이
    // 같은 minigameType 안에서 history/turn 변화를 그릴 수 있게 한다.
    _subs.add(_listen(_socket.onFwDuelState, (data) {
      final newState = data['state'];
      if (newState is! Map) return;
      final params = state.duel.minigameParams ?? const <String, dynamic>{};
      final next = Map<String, dynamic>.from(params);
      next['state'] = Map<String, dynamic>.from(newState);
      state = state.copyWith(
        duel: state.duel.copyWith(minigameParams: next),
      );
    }));

    _subs.add(_listen(_socket.onFwDuelInvalidated, (data) {
      state = state.copyWith(
        duel: state.duel.copyWith(
          phase: 'invalidated',
          duelResult: FwDuelResult.invalidated(),
        ),
        duelDebug: FwDuelDebugInfo.invalidated(data['reason'] as String?),
        myState: state.myState.copyWith(
          inDuel: false,
          duelExpiresAt: null,
        ),
      );
      _scheduleStateRefresh();
      // invalidated 도 자동 dismiss 하지 않는다 — 사용자가 사유(BLE 미확인,
      // 거리 이탈 등) 를 충분히 읽고 닫도록 한다.
    }));
  }

  void _handleStateUpdate(Map<String, dynamic> data) {
    final sessionId = data['sessionId'] as String?;
    if (sessionId != null && sessionId != _sessionId) {
      return;
    }

    final hasGuilds = data.containsKey('guilds');
    final hasControlPoints = data.containsKey('controlPoints');
    final hasPlayableArea = data.containsKey('playableArea');
    final hasSpawnZones = data.containsKey('spawnZones');
    final hasDungeons = data.containsKey('dungeons');
    final hasAlivePlayerIds = data.containsKey('alivePlayerIds');
    final hasEliminatedPlayerIds = data.containsKey('eliminatedPlayerIds');
    final hasWinCondition = data.containsKey('winCondition');

    var nextState = state.copyWith(
      status: data['status'] as String? ?? state.status,
      duelRangeMeters:
          (data['duelRangeMeters'] as num?)?.toInt() ?? state.duelRangeMeters,
      bleEvidenceFreshnessMs:
          (data['bleEvidenceFreshnessMs'] as num?)?.toInt() ??
              state.bleEvidenceFreshnessMs,
      allowGpsFallbackWithoutBle: data['allowGpsFallbackWithoutBle'] as bool? ??
          state.allowGpsFallbackWithoutBle,
      guilds: hasGuilds ? parseGuilds(data['guilds']) : state.guilds,
      controlPoints: hasControlPoints
          ? parseControlPoints(data['controlPoints'])
          : state.controlPoints,
      playableArea: hasPlayableArea
          ? parseGeoPoints(data['playableArea'])
          : state.playableArea,
      spawnZones: hasSpawnZones
          ? parseSpawnZones(data['spawnZones'])
          : state.spawnZones,
      dungeons: hasDungeons ? parseDungeons(data['dungeons']) : state.dungeons,
      alivePlayerIds: hasAlivePlayerIds
          ? (data['alivePlayerIds'] as List?)?.whereType<String>().toList() ??
              const []
          : state.alivePlayerIds,
      eliminatedPlayerIds: hasEliminatedPlayerIds
          ? (data['eliminatedPlayerIds'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const []
          : state.eliminatedPlayerIds,
      winCondition: hasWinCondition
          ? (data['winCondition'] is Map
              ? Map<String, dynamic>.from(data['winCondition'] as Map)
              : null)
          : state.winCondition,
    );

    if (data.containsKey('guildId')) {
      nextState = nextState.copyWith(
        myState: parseMyState(nextState.myState, data),
      );
    }

    state = nextState;
  }

  void _requestStateNow() {
    _stateRefreshTimer?.cancel();
    if (_socket.isConnected) {
      _socket.requestGameState(_sessionId);
    }
  }

  void refreshState() => _requestStateNow();

  void _scheduleStateRefresh(
      [Duration delay = const Duration(milliseconds: 120)]) {
    _stateRefreshTimer?.cancel();
    _stateRefreshTimer = Timer(delay, () {
      if (mounted && _socket.isConnected) {
        _socket.requestGameState(_sessionId);
      }
    });
  }

  String? _guildIdForUser(String userId) {
    for (final guild in state.guilds.values) {
      if (guild.memberIds.contains(userId)) {
        return guild.guildId;
      }
    }
    return null;
  }

  void _mutateControlPoint(
    String? controlPointId,
    FwControlPoint Function(FwControlPoint current) update,
  ) {
    if (controlPointId == null) {
      return;
    }

    state = state.copyWith(
      controlPoints: state.controlPoints
          .map((controlPoint) => controlPoint.id == controlPointId
              ? update(controlPoint)
              : controlPoint)
          .toList(),
    );
  }

  Future<Map<String, dynamic>> startCapture(String controlPointId) async {
    final result = await _socket.sendFwCaptureStart(_sessionId, controlPointId);
    if (result['ok'] == true) {
      _scheduleStateRefresh();
    }
    return result;
  }

  Future<Map<String, dynamic>> cancelCapture(String controlPointId) async {
    final result =
        await _socket.sendFwCaptureCancel(_sessionId, controlPointId);
    if (result['ok'] == true) {
      _scheduleStateRefresh();
    }
    return result;
  }

  // 적 길드의 점령 진행을 명시적으로 방해. 살아있고 zone 안에 있어야 서버가
  // 허용한다. 성공 시 서버가 fw:capture_cancelled (reason='disrupted') 를
  // 브로드캐스트한다.
  Future<Map<String, dynamic>> disruptCapture(String controlPointId) async {
    final result =
        await _socket.sendFwCaptureDisrupt(_sessionId, controlPointId);
    if (result['ok'] == true) {
      _scheduleStateRefresh();
    }
    return result;
  }

  Future<Map<String, dynamic>> enterDungeon(
      {String dungeonId = 'dungeon_main'}) async {
    final result =
        await _socket.sendFwDungeonEnter(_sessionId, dungeonId: dungeonId);
    if (result['ok'] == true) {
      state = state.copyWith(
        myState: state.myState.copyWith(
          dungeonEntered: true,
          reviveReady: false,
          // 서버 권위 타임스탬프가 도착할 때까지 60초 가짜 카운트다운으로 시작.
          nextReviveAt: DateTime.now().millisecondsSinceEpoch + 60000,
          nextReviveChance: state.myState.nextReviveChance ?? 0.3,
        ),
      );
      _scheduleStateRefresh();
    }
    return result;
  }

  Future<Map<String, dynamic>> attemptRevive() async {
    final result = await _socket.sendFwRevive(_sessionId);
    if (result['ok'] == true) {
      // 결과는 fw:player_revived / fw:revive_failed 이벤트가 권위로 처리한다.
      // ack 직후엔 reviveReady 만 끄고 응답 대기.
      state = state.copyWith(
        myState: state.myState.copyWith(reviveReady: false),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> useSkill({
    String? targetUserId,
    String? controlPointId,
  }) async {
    final job = state.myState.job;
    if (job == null) {
      return {'ok': false, 'error': 'NO_JOB'};
    }

    final skill = switch (job) {
      'priest' => 'shield',
      'mage' => 'blockade',
      'ranger' => 'reveal',
      'rogue' => 'execution',
      _ => null,
    };
    if (skill == null) {
      return {'ok': false, 'error': 'NO_ACTIVE_SKILL'};
    }

    final result = await _socket.sendFwUseSkill(
      _sessionId,
      skill: skill,
      targetUserId: targetUserId,
      controlPointId: controlPointId,
    );
    if (result['ok'] == true) {
      _scheduleStateRefresh();
    }
    return result;
  }

  Future<Map<String, dynamic>> challengeDuel(
    String targetUserId, {
    Map<String, dynamic>? proximity,
  }) async {
    final result = await _socket.sendDuelChallenge(
      _sessionId,
      targetUserId,
      proximity: proximity,
    );
    if (result['ok'] == true) {
      // accept ack race 와 동일한 이유 — server 가 먼저 fw:duel:started 를 emit 한 뒤
      // ack 를 돌려주면 phase='challenging' 으로 회귀해 mini-game 화면이 사라진다.
      final currentPhase = state.duel.phase;
      if (currentPhase != 'in_game' && currentPhase != 'result') {
        state = state.copyWith(
          duel: FwDuelState(
            duelId: result['duelId'] as String?,
            opponentId: targetUserId,
            phase: 'challenging',
          ),
          duelDebug: FwDuelDebugInfo.fromResponse(
            stage: 'challenge',
            response: result,
          ),
        );
      } else {
        state = state.copyWith(
          duelDebug: FwDuelDebugInfo.fromResponse(
            stage: 'challenge',
            response: result,
          ),
        );
      }
    } else {
      state = state.copyWith(
        duelDebug: FwDuelDebugInfo.fromResponse(
          stage: 'challenge',
          response: result,
        ),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> acceptDuel(
    String duelId, {
    Map<String, dynamic>? proximity,
  }) async {
    final result = await _socket.sendDuelAccept(duelId, proximity: proximity);
    if (result['ok'] == true) {
      // 서버는 accept 처리 시 fw:duel:started 를 먼저 emit 한 뒤 ack 를 반환한다.
      // ack 가 started 이벤트보다 늦게 도착하는 race 에서 phase='accepted' 로 회귀하면
      // _DuelPhase.pendingSent 로 빠져 무한 로딩이 된다.
      // started 이벤트가 이미 도착해 phase='in_game' 인 경우엔 그대로 유지하고,
      // 아직 challenged 상태라면 'accepted' 로 한 단계 진행시킨다.
      final currentPhase = state.duel.phase;
      if (currentPhase != 'in_game' && currentPhase != 'result') {
        state = state.copyWith(
          duel: state.duel.copyWith(
            duelId: duelId,
            phase: 'accepted',
          ),
        );
      }
    }
    state = state.copyWith(
      duelDebug: FwDuelDebugInfo.fromResponse(
        stage: 'accept',
        response: result,
      ),
    );
    return result;
  }

  Future<Map<String, dynamic>> rejectDuel(String duelId) async {
    final result = await _socket.sendDuelReject(duelId);
    if (result['ok'] == true) {
      state = state.copyWith(duel: const FwDuelState());
    }
    return result;
  }

  Future<Map<String, dynamic>> cancelDuel() async {
    final duelId = state.duel.duelId;
    if (duelId == null) {
      state = state.copyWith(duel: const FwDuelState());
      return {'ok': true};
    }

    final result = await _socket.sendDuelCancel(duelId);
    if (result['ok'] == true) {
      state = state.copyWith(duel: const FwDuelState());
    }
    return result;
  }

  Future<Map<String, dynamic>> submitMinigame(
      Map<String, dynamic> result) async {
    final duelId = state.duel.duelId;
    if (duelId == null || state.duel.submitted) {
      return {'ok': false, 'error': 'DUEL_NOT_ACTIVE'};
    }

    final response = await _socket.sendDuelSubmit(duelId, result);
    if (response['ok'] == true) {
      state = state.copyWith(
        duel: state.duel.copyWith(submitted: true),
      );
    }
    return response;
  }

  // 턴 기반 미니게임용 액션 dispatch. 서버 검증 후 fw:duel:state broadcast 로 양 클라가
  // 동일 state 를 수신한다. terminal action 이면 곧이어 fw:duel:result 가 따라온다.
  Future<Map<String, dynamic>> sendDuelAction(
      Map<String, dynamic> action) async {
    final duelId = state.duel.duelId;
    if (duelId == null) {
      return {'ok': false, 'error': 'DUEL_NOT_ACTIVE'};
    }
    return _socket.sendDuelAction(duelId, action);
  }

  void clearDuelResult() {
    if (!mounted) {
      return;
    }
    state = state.copyWith(duel: const FwDuelState());
  }

  @override
  void dispose() {
    _stateRefreshTimer?.cancel();
    for (final subscription in _subs) {
      subscription.cancel();
    }
    super.dispose();
  }
}
