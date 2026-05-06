// ignore_for_file: unnecessary_brace_in_string_interps, unused_element

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/app_router.dart';
import '../../../../../core/services/app_initialization_service.dart';
import '../../../../../core/services/fantasy_wars_proximity_service.dart';
import '../../../../../core/services/fcm_service.dart';
import '../../../../../core/services/mediasoup_audio_service.dart';
import '../../../../../core/services/socket_service.dart';
import '../../../../auth/data/auth_repository.dart';
import '../../../../home/data/session_repository.dart';
import '../../../../lobby/providers/lobby_provider.dart';
import '../../../../map/data/map_session_provider.dart';
import '../../../../map/presentation/map_session_models.dart';
import '../../../providers/ble_duel_provider.dart';
import '../../../providers/fantasy_wars_provider.dart';
import '../../../providers/voice_speaking_provider.dart';
import '../../../widgets/ai_master_status_widget.dart';
import '../../../widgets/ble_status_widget.dart';
import 'duel/fw_duel_screen_v2.dart' show FwDuelScreen;
import 'fantasy_wars_design_tokens.dart';
import 'fantasy_wars_hud.dart';
import 'services/fantasy_wars_geo_service.dart';
import 'services/fantasy_wars_overlay_sync_service.dart';
import 'services/fantasy_wars_targeting_service.dart';
import 'services/fw_notification_service.dart';
import 'widgets/fw_action_dock.dart';
import 'widgets/fw_ai_chat_sheet.dart';
import 'widgets/fw_battle_panel.dart';
import 'widgets/fw_bootstrap_steps.dart';
import 'widgets/fw_capture_progress_overlay.dart';
import 'widgets/fw_choice_badge.dart';
import 'widgets/fw_control_point_bar.dart';
import 'widgets/fw_corner_badges.dart';
import 'widgets/fw_distance_capsule.dart';
import 'widgets/fw_duel_overlay.dart';
import 'widgets/fw_game_result_screen.dart';
import 'widgets/fw_host_panels.dart';
import 'widgets/fw_map_buttons.dart';
import 'widgets/fw_toast_overlay.dart';
import 'widgets/fw_voice_chip.dart';

class FantasyWarsGameScreen extends ConsumerStatefulWidget {
  const FantasyWarsGameScreen({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  ConsumerState<FantasyWarsGameScreen> createState() =>
      _FantasyWarsGameScreenState();
}

class _FantasyWarsGameScreenState extends ConsumerState<FantasyWarsGameScreen> {
  // PlatformView 재생성 여부를 가시화하기 위한 디버그 카운터.
  // 정상 흐름에서는 createCount/readyCount 모두 1 이어야 한다.
  static int _naverMapCreateCount = 0;
  static int _naverMapReadyCount = 0;

  static const _duelProximity = FantasyWarsProximityService();
  static const _geo = FantasyWarsGeoService();
  static const _targeting = FantasyWarsTargetingService();
  final FantasyWarsOverlaySyncService _overlaySync =
      FantasyWarsOverlaySyncService();
  static const double _captureRadiusMeters = 40;
  // 점령 최소 인원: 1명. SOLO / 소규모 세션 에서도 점령 가능. 백엔드 capture
  // validator 와 같은 값을 유지해야 클라/서버 검증이 일치한다.
  static const int _minCaptureMemberCount = 1;

  NaverMapController? _mapController;
  bool _mapSdkReady = false;
  bool _bootstrapping = false;
  String? _bootstrapError;

  // NaverMap 위젯 자체 준비 상태 (onMapReady 이후 true)
  bool _naverMapWidgetReady = false;
  String? _naverMapWidgetError;
  Timer? _naverMapWidgetTimer;
  bool _naverMapTimerStarted = false;
  // GlobalKey 사용: Stack 트리 안에서 위치가 바뀌어도 Element/State/SurfaceTexture를 보존한다.
  // retry 시에만 새 키로 교체해 PlatformView를 의도적으로 재생성한다.
  GlobalKey _mapViewKey = GlobalKey(debugLabel: 'fw_naver_map');
  NLatLng? _initialMapTarget;
  NLatLng? _stableMapInitialTarget;
  Widget? _stableNaverMapLayer;
  bool? _lastShowBootstrapView;

  final Map<String, NCircleOverlay> _cpOverlays = {};
  final Map<String, NPolygonOverlay> _spawnZoneOverlays = {};
  final Map<String, NMarker> _playerMarkers = {};
  // 플레이어 마커 아이콘 캐시: '<colorValue>:<speakingFlag>' → NOverlayImage.
  // NOverlayImage.fromWidget 은 비싼 위젯→비트맵 합성을 하므로 동일 (color, speaking)
  // 조합은 한 번만 그리고 재사용한다.
  final Map<String, NOverlayImage> _playerMarkerIconCache = {};
  // 비동기 아이콘 로드와 더 새로운 speaking 변화 사이의 race 가드.
  // 마지막으로 의도한 isSpeaking 을 기록해 두고, 콜백 완료 시점의 의도가 다르면 무시.
  final Map<String, bool> _playerMarkerSpeakingIntent = {};
  // PlatformView 가 실제로 재생성되었음을 알리는 per-instance 플래그.
  // _retryBootstrap 이 새 _mapViewKey 를 생성할 때 true 로 올리고,
  // 다음 _handleNaverMapReady 에서 icon cache 를 비울지 결정하는 데 사용한다.
  // 첫 진입에서는 false 라 icon cache 를 보존해 NOverlayImage.fromWidget 재합성을 피한다.
  bool _pendingPlatformViewReplacement = false;
  // PlatformView 세대 식별자. retry 로 새 PlatformView 가 만들어질 때마다 +1.
  // 비동기 NOverlayImage.fromWidget 시작 시점의 generation 을 캡처해 두고,
  // 완료 시점의 generation 과 다르면 stale 로 간주해 cache write / setIcon 을 모두 스킵한다.
  int _markerIconGeneration = 0;
  NPolygonOverlay? _playableAreaOverlay;
  NMarker? _distanceLabelMarker;
  NPolylineOverlay? _distanceLine;
  String? _distanceLabelCacheKey;

  Timer? _bootstrapTimeoutTimer;
  StreamSubscription<bool>? _socketConnectionSub;
  ProviderSubscription<FantasyWarsGameState>? _fwStateSubscription;
  ProviderSubscription<MapSessionState>? _mapStateSubscription;
  ProviderSubscription<AsyncValue<AppUser?>>? _authSubscription;
  // Voice 표시 — 마커 ring + HUD chip 양쪽에서 사용.
  ProviderSubscription<Set<String>>? _voiceSpeakingSubscription;
  StreamSubscription<bool>? _selfSpeakingSub;
  bool _isSelfSpeaking = false;
  // HUD voice chip — 마이크 음소거 / ready 상태.
  StreamSubscription<bool>? _micMutedSub;
  bool _isMicMuted = false;
  // Mediasoup join 실패 — 사용자에게 SnackBar 노출.
  StreamSubscription<String>? _voiceJoinErrorSub;
  // 빠른 사전 비교용 state 객체 identity. 같으면 overlay signature 재계산을 건너뛴다.
  String? _lastControlPointSignature;
  String? _lastBattlefieldSignature;
  bool _lastWasKicked = false;
  String? _lastDuelPhase;
  String? _blePresenceStartKey;
  String? _selectedMemberId;
  String? _selectedControlPointId;
  final TextEditingController _aiChatController = TextEditingController();
  final FocusNode _aiChatFocusNode = FocusNode(debugLabel: 'fw_ai_chat');
  final ValueNotifier<List<_FwAiChatLine>> _aiChatLinesNotifier =
      ValueNotifier<List<_FwAiChatLine>>(const []);
  final ValueNotifier<bool> _aiChatSendingNotifier = ValueNotifier(false);
  StreamSubscription<Map<String, dynamic>>? _aiMessageSub;
  StreamSubscription<Map<String, dynamic>>? _aiReplySub;
  // PR N2: 알림 카탈로그 → 토스트 디스패치. 카탈로그가 emit 한 한국어 메시지 +
  // toastKind 가 즉시 _toastMessage 로 들어가 기존 FwToastOverlay 가 그대로 표시.
  StreamSubscription<FwNotifyEvent>? _notifyEventSub;

  // Layer 4: AI 채팅 시트 사이즈
  // - compact (기본 104): 입력 + 최신 1줄 미리보기. 지도를 거의 안 가림.
  // - expanded (토글 1단계 220): 메시지 로그 짧게 노출.
  // - 드래그 (사용자 의지): 최대 화면 50% 까지 확장.
  // 새 메시지 수신 시 자동 확장 없음. 사용자 탭/드래그에서만 확장.
  // FwAiChatSheet 의 collapsed 상태에 header(~48) + compact preview row(~16) + input(~52)
  // 가 모두 들어가도록 충분한 minHeight 를 둔다. 이전 104 에서는 preview 가 항상
  // 잘려 가독성 0 이었음.
  static const double _chatSheetMin = 124.0;
  static const double _chatSheetExpanded = 220.0;
  double _chatSheetHeight = _chatSheetMin;
  // Layer 2: 우측 전장 정보 패널 접힘/펼침 상태 (기본 접힘)
  bool _battlePanelExpanded = false;
  // Layer 7: 토스트 표시 상태
  String? _toastMessage;
  String? _toastKind;
  Timer? _toastTimer;
  int? _lastToastEventAt;
  bool _stateSideEffectsScheduled = false;

  @override
  void initState() {
    super.initState();
    _bindAiChatStreams();
    _socketConnectionSub =
        SocketService().onConnectionChange.listen((connected) {
      if (!connected) {
        return;
      }

      final socket = SocketService();
      socket.joinSession(widget.sessionId);
      ref.read(fantasyWarsProvider(widget.sessionId).notifier).refreshState();
    });
    _fwStateSubscription = ref.listenManual(
      fantasyWarsProvider(widget.sessionId),
      (_, __) => _scheduleStateSideEffectsFromRefs(),
    );
    _mapStateSubscription = ref.listenManual(
      mapSessionProvider(widget.sessionId),
      (_, __) => _scheduleStateSideEffectsFromRefs(),
    );
    _authSubscription = ref.listenManual(
      authProvider,
      (_, __) => _scheduleStateSideEffectsFromRefs(),
    );
    // 다른 피어 발화 변화 → marker 갱신.
    _voiceSpeakingSubscription = ref.listenManual<Set<String>>(
      voiceSpeakingProvider(widget.sessionId),
      (_, __) => _scheduleStateSideEffectsFromRefs(),
    );
    // 본인 발화는 round-trip latency 없이 로컬 stream으로 추적.
    _selfSpeakingSub =
        MediaSoupAudioService().isSpeakingStream.listen((speaking) {
      if (!mounted) return;
      if (_isSelfSpeaking == speaking) return;
      _isSelfSpeaking = speaking;
      _scheduleStateSideEffectsFromRefs();
      setState(() {});
    });
    // HUD voice chip — 음소거 토글 동기화.
    _isMicMuted = MediaSoupAudioService().isMuted;
    _micMutedSub = MediaSoupAudioService().isMutedStream.listen((muted) {
      if (!mounted) return;
      if (_isMicMuted == muted) return;
      setState(() => _isMicMuted = muted);
    });
    _voiceJoinErrorSub =
        MediaSoupAudioService().joinErrorStream.listen((reason) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      final text = reason == 'voice_timeout'
          ? '음성 채널 연결이 지연돼 실패했어요. 네트워크가 안정되면 자동으로 재연결됩니다.'
          : '음성 채널 연결에 실패했어요. 네트워크 상태를 확인해주세요.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 4),
        ),
      );
    });
    // PR N2: notification service 의 events stream 구독 — 알림이 발화되면
    // 한국어 메시지 + toastKind 로 _toastMessage 업데이트, 기존 FwToastOverlay 가
    // 그대로 표시. recentEvents 기반 영문 토스트보다 우선 노출 (가장 최신 setState 가 보임).
    _notifyEventSub = ref
        .read(fwNotificationServiceProvider)
        .events
        .listen((event) {
      if (!mounted) return;
      setState(() {
        _toastMessage = event.message;
        _toastKind = event.toastKind;
      });
      _toastTimer?.cancel();
      _toastTimer = Timer(const Duration(milliseconds: 2000), () {
        if (!mounted) return;
        setState(() {
          _toastMessage = null;
          _toastKind = null;
        });
      });
    });
    _scheduleStateSideEffectsFromRefs();
    unawaited(_bootstrapScreen());
  }

  @override
  void dispose() {
    _overlaySync.dispose();
    _bootstrapTimeoutTimer?.cancel();
    _naverMapWidgetTimer?.cancel();
    _socketConnectionSub?.cancel();
    _fwStateSubscription?.close();
    _mapStateSubscription?.close();
    _authSubscription?.close();
    _voiceSpeakingSubscription?.close();
    _selfSpeakingSub?.cancel();
    _micMutedSub?.cancel();
    _voiceJoinErrorSub?.cancel();
    _aiMessageSub?.cancel();
    _aiReplySub?.cancel();
    _notifyEventSub?.cancel();
    _aiChatController.dispose();
    _aiChatFocusNode.dispose();
    _aiChatLinesNotifier.dispose();
    _aiChatSendingNotifier.dispose();
    _toastTimer?.cancel();
    _blePresenceStartKey = null;
    unawaited(ref.read(bleDuelProvider.notifier).stopAfterDuel());
    _cpOverlays.clear();
    _spawnZoneOverlays.clear();
    _playerMarkers.clear();
    _playerMarkerIconCache.clear();
    _playerMarkerSpeakingIntent.clear();
    _playableAreaOverlay = null;
    _distanceLabelMarker = null;
    _distanceLine = null;
    _distanceLabelCacheKey = null;
    super.dispose();
  }

  void _scheduleStateSideEffectsFromRefs() {
    if (_stateSideEffectsScheduled || !mounted) {
      return;
    }

    _stateSideEffectsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stateSideEffectsScheduled = false;
      if (!mounted) {
        return;
      }
      _runStateSideEffectsFromRefs();
    });
  }

  void _runStateSideEffectsFromRefs() {
    final fwState = ref.read(fantasyWarsProvider(widget.sessionId));
    final mapState = ref.read(mapSessionProvider(widget.sessionId));
    final myId = ref.read(authProvider).valueOrNull?.id;

    _reconcileBootstrapState(fwState);
    final showBootstrapView = !_isCriticalBootstrapReady(fwState, mapState) ||
        _bootstrapError != null;
    _syncFocusWithBootstrapVisibility(showBootstrapView);
    _maybeStartNaverMapWidgetTimer(showBootstrapView);
    _handleStateSideEffectsClean(fwState, mapState, myId);
  }

  void _maybeStartNaverMapWidgetTimer(bool showBootstrapView) {
    if (showBootstrapView ||
        _naverMapTimerStarted ||
        _naverMapWidgetReady ||
        _naverMapWidgetError != null) {
      return;
    }

    _naverMapTimerStarted = true;
    debugPrint(
      '[FW-BOOT] game screen first frame rendered, starting NaverMap widget timer',
    );
    _startNaverMapWidgetTimer();
  }

  void _bindAiChatStreams() {
    final socket = SocketService();
    _aiMessageSub =
        socket.onGameEvent(SocketService.gameAiMessage).listen((data) {
      _handleAiChatPayload(data, fallbackRole: 'system');
    });
    _aiReplySub = socket.onGameEvent(SocketService.gameAiReply).listen((data) {
      _handleAiChatPayload(data, fallbackRole: 'ai');
    });
  }

  void _handleAiChatPayload(
    Map<String, dynamic> data, {
    required String fallbackRole,
  }) {
    final eventSessionId = data['sessionId'] as String?;
    if (eventSessionId != null && eventSessionId != widget.sessionId) {
      return;
    }

    final text = _firstStringValue(data, const [
      'message',
      'reply',
      'answer',
      'content',
      'text',
    ]);
    if (text == null || text.trim().isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }

    _appendAiChatLine(
      _FwAiChatLine(
        role: data['role'] as String? ?? fallbackRole,
        text: text.trim(),
        createdAt: DateTime.now(),
      ),
    );
    if (fallbackRole == 'ai' && _aiChatSendingNotifier.value) {
      _aiChatSendingNotifier.value = false;
    }
  }

  String? _firstStringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  void _appendAiChatLine(_FwAiChatLine line) {
    if (!mounted) {
      return;
    }
    final next = <_FwAiChatLine>[
      ..._aiChatLinesNotifier.value,
      line,
    ];
    if (next.length > 8) {
      next.removeRange(0, next.length - 8);
    }
    _aiChatLinesNotifier.value = List.unmodifiable(next);
  }

  Future<Map<String, dynamic>> _sendAiQuestion(String question) {
    final completer = Completer<Map<String, dynamic>>();
    SocketService().sendAiQuestion(widget.sessionId, question, (ack) {
      completer.complete(Map<String, dynamic>.from(ack));
    });
    return completer.future;
  }

  Future<void> _sendAiChatMessage() async {
    final question = _aiChatController.text.trim();
    if (question.isEmpty || _aiChatSendingNotifier.value) {
      return;
    }

    _aiChatController.clear();
    _appendAiChatLine(
      _FwAiChatLine(
        role: 'user',
        text: question,
        createdAt: DateTime.now(),
      ),
    );
    _aiChatSendingNotifier.value = true;

    final result = await _sendAiQuestion(question);
    if (!mounted) {
      return;
    }

    if (result['ok'] != true) {
      _aiChatSendingNotifier.value = false;
      _appendAiChatLine(
        _FwAiChatLine(
          role: 'system',
          text: _resolveErrorLabelClean(result['error'] as String?),
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final immediateReply = _firstStringValue(result, const [
      'reply',
      'answer',
      'message',
      'content',
    ]);
    if (immediateReply != null && immediateReply.trim().isNotEmpty) {
      _aiChatSendingNotifier.value = false;
      _appendAiChatLine(
        _FwAiChatLine(
          role: 'ai',
          text: immediateReply.trim(),
          createdAt: DateTime.now(),
        ),
      );
    } else {
      _aiChatSendingNotifier.value = false;
    }
  }

  Future<void> _bootstrapScreen() async {
    debugPrint('[FW-BOOT] bootstrap started, sessionId=${widget.sessionId}');
    _bootstrapTimeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _bootstrapping = true;
        _bootstrapError = null;
      });
    }

    try {
      final socket = SocketService();
      debugPrint('[FW-BOOT] socket.isConnected=${socket.isConnected}');
      if (!socket.isConnected) {
        debugPrint('[FW-BOOT] connecting socket...');
        await socket.connect();
        debugPrint('[FW-BOOT] socket connected');
      }

      socket.joinSession(widget.sessionId);
      debugPrint(
          '[FW-BOOT] joinSession emitted, currentSessionId=${socket.currentSessionId}');

      ref.read(fantasyWarsProvider(widget.sessionId).notifier).refreshState();
      debugPrint('[FW-BOOT] game:request_state emitted');

      debugPrint('[FW-BOOT] naver map sdk init...');
      await AppInitializationService().ensureNaverMapInitialized();
      debugPrint(
          '[FW-BOOT] naver map sdk ready, authFailed=${AppInitializationService().isNaverMapAuthFailed}');

      if (!mounted) {
        return;
      }

      setState(() {
        _mapSdkReady = true;
        _bootstrapping = false;
      });
      debugPrint('[FW-BOOT] _mapSdkReady=true, bootstrap phase complete');

      unawaited(_warmInitialGameState());
      _scheduleBootstrapTimeout();
    } catch (error, stackTrace) {
      debugPrint('[FW-BOOT] bootstrap FAILED: $error');
      debugPrintStack(
        label: '[FW-BOOT] bootstrap stack',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapping = false;
        _bootstrapError = error.toString();
      });
    }
  }

  void _scheduleBootstrapTimeout() {
    _bootstrapTimeoutTimer?.cancel();
    // 8s 였을 때 약한 셀룰러 / Naver SDK 첫 로드 / 첫 game:state_update 의
    // round-trip 이 합쳐져 false negative 가 잦았다. 15s 로 늘려 정상 fetch 가
    // 끝나기를 기다린다. 이 시간 안에도 안 오면 사용자에게 명시적 안내.
    _bootstrapTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) {
        return;
      }

      final fwState = ref.read(fantasyWarsProvider(widget.sessionId));
      if (_hasRenderableGameState(fwState) || _bootstrapError != null) {
        return;
      }

      final mapState = ref.read(mapSessionProvider(widget.sessionId));
      setState(() {
        _bootstrapError = mapState.isConnected || mapState.hasEverConnected
            ? '게임 상태를 아직 받지 못했습니다. 다시 시도해 주세요.'
            : '게임 서버 연결이 지연되고 있습니다. 다시 시도해 주세요.';
      });
    });
  }

  bool _hasRenderableGameState(FantasyWarsGameState fwState) {
    return fwState.status != 'none' ||
        fwState.guilds.isNotEmpty ||
        fwState.controlPoints.isNotEmpty ||
        fwState.playableArea.length >= 3 ||
        fwState.spawnZones.isNotEmpty;
  }

  Future<void> _warmInitialGameState() async {
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 500),
      Duration(milliseconds: 1400),
    ];

    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!mounted) {
        return;
      }
      final fwState = ref.read(fantasyWarsProvider(widget.sessionId));
      if (_hasRenderableGameState(fwState)) {
        debugPrint(
          '[FW-BOOT] game:state_update seen ??status=${fwState.status}, '
          'guilds=${fwState.guilds.length}, '
          'controlPoints=${fwState.controlPoints.length}, '
          'playableArea=${fwState.playableArea.length}',
        );
        return;
      }
      debugPrint(
          '[FW-BOOT] no renderable state yet, delay=${delay.inMilliseconds}ms, retrying...');
      notifier.refreshState();
    }
    debugPrint(
        '[FW-BOOT] warm init done ??state still not renderable after retries');
  }

  void _reconcileBootstrapState(FantasyWarsGameState fwState) {
    if (!_hasRenderableGameState(fwState)) {
      return;
    }

    _bootstrapTimeoutTimer?.cancel();

    if (_bootstrapError == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bootstrapError == null) {
        return;
      }
      setState(() => _bootstrapError = null);
    });
  }

  bool _isCriticalBootstrapReady(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    return _cleanBootstrapSteps(fwState, mapState)
        .where((step) => step.required)
        .every((step) => step.ready);
  }

  List<FwBootstrapStep> _bootstrapSteps(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    final socket = SocketService();
    final socketConnected = socket.isConnected;
    final sessionSubscribed = socket.currentSessionId == widget.sessionId;
    final stateReady = _hasRenderableGameState(fwState);
    final mapReady = _mapSdkReady;
    final gpsReady = mapState.myPosition != null;
    final voiceReady = MediaSoupAudioService().isReady;
    final fcmReady = FcmService().isInitialized;

    return [
      FwBootstrapStep(
        title: '실시간 서버 연결',
        description: socketConnected ? '서버 연결이 완료되었습니다.' : '백엔드 서버에 연결하는 중입니다.',
        ready: socketConnected,
        required: true,
        icon: Icons.hub_rounded,
      ),
      FwBootstrapStep(
        title: '세션 채널 구독',
        description:
            sessionSubscribed ? '현재 게임 세션 채널에 참여했습니다.' : '게임 세션 채널에 참여하는 중입니다.',
        ready: sessionSubscribed,
        required: true,
        icon: Icons.link_rounded,
      ),
      FwBootstrapStep(
        title: '초기 게임 상태 수신',
        description: stateReady
            ? '전장 정보와 플레이어 상태를 받았습니다.'
            : '거점, 길드, 개인 상태를 서버에서 불러오는 중입니다.',
        ready: stateReady,
        required: true,
        icon: Icons.sync_alt_rounded,
      ),
      FwBootstrapStep(
        title: '지도 엔진 초기화',
        description:
            mapReady ? '네이버 지도 SDK 준비가 완료되었습니다.' : '지도 엔진과 전장 오버레이를 준비하는 중입니다.',
        ready: mapReady,
        required: true,
        icon: Icons.map_rounded,
      ),
      FwBootstrapStep(
        title: '현재 위치 정보',
        description: gpsReady
            ? '현재 위치를 받았습니다.'
            : '거점 점령과 결투 판정에 GPS가 필요합니다. 위치 권한을 허용하고 GPS를 켜 주세요.',
        ready: gpsReady,
        required: true,
        icon: Icons.my_location_rounded,
      ),
      FwBootstrapStep(
        title: '음성 채널 준비',
        description: voiceReady
            ? 'Mediasoup 음성 채널 준비가 완료되었습니다.'
            : 'Mediasoup 음성 채널에 연결하는 중입니다.',
        ready: voiceReady,
        required: false,
        icon: Icons.headset_mic_rounded,
      ),
      FwBootstrapStep(
        title: '알림 채널 준비',
        description:
            fcmReady ? 'FCM 초기화가 완료되었습니다.' : '푸시 알림 모듈을 백그라운드에서 준비하는 중입니다.',
        ready: fcmReady,
        required: false,
        icon: Icons.notifications_active_rounded,
      ),
    ];
  }

  List<FwBootstrapStep> _cleanBootstrapSteps(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    final socket = SocketService();
    final socketConnected = socket.isConnected;
    final sessionSubscribed = socket.currentSessionId == widget.sessionId;
    final stateReady = _hasRenderableGameState(fwState);
    final mapReady = _mapSdkReady;
    final gpsReady = mapState.myPosition != null;
    final voiceReady = MediaSoupAudioService().isReady;
    final fcmReady = FcmService().isInitialized;

    return [
      FwBootstrapStep(
        title: '실시간 서버 연결',
        description: socketConnected ? '서버 연결이 완료되었습니다.' : '백엔드 서버에 연결하는 중입니다.',
        ready: socketConnected,
        required: true,
        icon: Icons.hub_rounded,
      ),
      FwBootstrapStep(
        title: '세션 채널 구독',
        description:
            sessionSubscribed ? '현재 게임 세션 채널에 참여했습니다.' : '게임 세션 채널에 참여하는 중입니다.',
        ready: sessionSubscribed,
        required: true,
        icon: Icons.link_rounded,
      ),
      FwBootstrapStep(
        title: '초기 게임 상태 수신',
        description: stateReady
            ? '전장 정보와 플레이어 상태를 받았습니다.'
            : '거점, 길드, 개인 상태를 서버에서 불러오는 중입니다.',
        ready: stateReady,
        required: true,
        icon: Icons.sync_alt_rounded,
      ),
      FwBootstrapStep(
        title: '지도 엔진 초기화',
        description:
            mapReady ? '네이버 지도 SDK 준비가 완료되었습니다.' : '지도 엔진과 전장 오버레이를 준비하는 중입니다.',
        ready: mapReady,
        required: true,
        icon: Icons.map_rounded,
      ),
      FwBootstrapStep(
        title: '현재 위치 정보',
        description: gpsReady
            ? '현재 위치를 받았습니다.'
            : '거점 점령과 결투 판정에 GPS가 필요합니다. 위치 권한을 허용하고 GPS를 켜 주세요.',
        ready: gpsReady,
        required: true,
        icon: Icons.my_location_rounded,
      ),
      FwBootstrapStep(
        title: '음성 채널 준비',
        description: voiceReady
            ? 'Mediasoup 음성 채널 준비가 완료되었습니다.'
            : 'Mediasoup 음성 채널에 연결하는 중입니다.',
        ready: voiceReady,
        required: false,
        icon: Icons.headset_mic_rounded,
      ),
      FwBootstrapStep(
        title: '알림 채널 준비',
        description:
            fcmReady ? 'FCM 초기화가 완료되었습니다.' : '푸시 알림 모듈을 백그라운드에서 준비하는 중입니다.',
        ready: fcmReady,
        required: false,
        icon: Icons.notifications_active_rounded,
      ),
    ];
  }

  String _cleanBootstrapHeadline(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    if (_bootstrapError != null) {
      return '게임 준비에 실패했습니다';
    }

    for (final step in _cleanBootstrapSteps(fwState, mapState)) {
      if (step.required && !step.ready) {
        return '${step.title} 준비 중';
      }
    }
    return '전장 준비 완료';
  }

  String _cleanBootstrapDescription(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    if (_bootstrapError != null) {
      final socket = SocketService();
      if (!socket.isConnected) {
        return '실시간 서버 연결이 지연되고 있습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.';
      }
      if (!_hasRenderableGameState(fwState)) {
        return '서버에는 연결되었지만 초기 게임 상태를 아직 받지 못했습니다. 다시 시도하면 상태를 다시 요청합니다.';
      }
      return '초기화 중 문제가 발생했습니다. 다시 시도해 주세요.';
    }

    for (final step in _cleanBootstrapSteps(fwState, mapState)) {
      if (step.required && !step.ready) {
        return step.description;
      }
    }
    return '필수 모듈 준비가 끝났습니다. 선택 모듈은 백그라운드에서 이어서 초기화됩니다.';
  }

  String _cleanMapWidgetError(String message) {
    if (message.contains('NaverMap')) {
      return 'NaverMap 인증에 실패했습니다.\n클라이언트 ID(ir4goe1vir)가 이 기기/환경에서 유효한지 확인해 주세요.';
    }
    return message;
  }

  String _bootstrapHeadline(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    if (_bootstrapError != null) {
      return '게임 준비에 실패했습니다';
    }

    for (final step in _bootstrapSteps(fwState, mapState)) {
      if (step.required && !step.ready) {
        return '${step.title} 준비 중';
      }
    }
    return '전장 준비 완료';
  }

  String _bootstrapDescription(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
  ) {
    if (_bootstrapError != null) {
      final socket = SocketService();
      if (!socket.isConnected) {
        return '실시간 서버 연결이 지연되고 있습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.';
      }
      if (!_hasRenderableGameState(fwState)) {
        return '서버에는 연결되었지만 초기 게임 상태를 아직 받지 못했습니다. 다시 시도하면 상태를 다시 요청합니다.';
      }
      return '초기화 중 문제가 발생했습니다. 다시 시도해 주세요.';
    }

    for (final step in _bootstrapSteps(fwState, mapState)) {
      if (step.required && !step.ready) {
        return step.description;
      }
    }
    return '필수 모듈 준비가 끝났습니다. 선택 모듈은 백그라운드에서 이어서 초기화됩니다.';
  }

  Future<void> _retryBootstrap() async {
    // Reset NaverMap widget state so the overlay and timer restart.
    if (mounted) {
      setState(() {
        _naverMapWidgetReady = false;
        _naverMapWidgetError = null;
        _naverMapTimerStarted = false;
        _mapController = null;
        _stableNaverMapLayer = null;
        _stableMapInitialTarget = null;
        _initialMapTarget = null;
        _mapViewKey = GlobalKey(
          debugLabel:
              'fw_naver_map_retry_${DateTime.now().millisecondsSinceEpoch}',
        );
        _mapSdkReady = false;
        // 새 _mapViewKey 로 PlatformView 가 재생성되므로 이전 channel 에 묶인
        // NOverlayImage 들을 다음 onMapReady 에서 비우게 표시. generation 도
        // 즉시 올려 in-flight icon load 가 stale write 를 못 하도록 차단.
        _pendingPlatformViewReplacement = true;
        _markerIconGeneration += 1;
      });
    }
    AppInitializationService().resetNaverMapAuthFailure();
    await _bootstrapScreen();
  }

  Future<void> _syncMapOverlays(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
    int syncId,
  ) async {
    final controller = _mapController;
    if (controller == null || !mounted || !_overlaySync.isCurrent(syncId)) {
      return;
    }

    await _syncBattlefieldOverlays(
      controller: controller,
      fwState: fwState,
      syncId: syncId,
    );
    if (!mounted || !_overlaySync.isCurrent(syncId)) {
      return;
    }

    await _syncControlPointOverlays(
      controller: controller,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
      syncId: syncId,
    );
    if (!mounted || !_overlaySync.isCurrent(syncId)) {
      return;
    }
    // 거점은 NCircleOverlay (영역 폴리곤) 만 사용.
    // 폴리곤 자체에 onTap 이 걸려 있어 탭하면 _handleControlPointTappedClean 가
    // 정보 시트를 띄운다. 핀 마커는 영역과 시각적으로 충돌하므로 제거.
    await _syncDistanceLabel(
      controller: controller,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
      syncId: syncId,
    );
    if (!mounted || !_overlaySync.isCurrent(syncId)) {
      return;
    }
    await _syncPlayerMarkers(
      controller: controller,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
      syncId: syncId,
    );
  }

  /// NaverMap의 NPolygonOverlay는 닫힌 링(첫 좌표 = 마지막 좌표)을 요구한다.
  /// 백엔드가 열린 polyline 형태로 보내는 경우(playableArea, spawnZone polygonPoints)
  /// 마지막에 첫 좌표를 한 번 더 붙여 보정한다. 이미 닫혀 있으면 그대로 반환한다.
  List<NLatLng> _closedRing(List<NLatLng> coords) {
    if (coords.length < 3) return coords;
    final first = coords.first;
    final last = coords.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      return coords;
    }
    return [...coords, NLatLng(first.latitude, first.longitude)];
  }

  Future<void> _syncBattlefieldOverlays({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required int syncId,
  }) async {
    final signature = _battlefieldSignature(fwState);
    if (_lastBattlefieldSignature == signature) {
      return;
    }

    // 모든 add를 set에 모아 addOverlayAll(Set) 한 번으로 합친다.
    // delete는 NaverMap에 batch API가 없어 개별 호출하되,
    // signature 비교로 변경 없는 케이스는 앞에서 early return 처리한다.
    final overlaysToAdd = <NAddableOverlay>{};

    if (_playableAreaOverlay != null) {
      try {
        await controller.deleteOverlay(
          const NOverlayInfo(
              type: NOverlayType.polygonOverlay, id: 'fw_playable_area'),
        );
      } catch (_) {}
      _playableAreaOverlay = null;
      if (!mounted || !_overlaySync.isCurrent(syncId)) {
        return;
      }
    }

    if (fwState.playableArea.length >= 3) {
      final polygon = NPolygonOverlay(
        id: 'fw_playable_area',
        coords: _closedRing(
          fwState.playableArea
              .map((point) => NLatLng(point.lat, point.lng))
              .toList(),
        ),
        color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
        outlineColor: const Color(0xFF38BDF8).withValues(alpha: 0.8),
        outlineWidth: 3,
      );
      _playableAreaOverlay = polygon;
      overlaysToAdd.add(polygon);
    }

    final activeSpawnIds = <String>{};
    for (final spawnZone in fwState.spawnZones) {
      if (spawnZone.polygonPoints.length < 3) {
        continue;
      }

      final overlayId = 'spawn_${spawnZone.teamId}';
      activeSpawnIds.add(overlayId);
      final existing = _spawnZoneOverlays.remove(overlayId);
      if (existing != null) {
        try {
          await controller.deleteOverlay(
            NOverlayInfo(type: NOverlayType.polygonOverlay, id: overlayId),
          );
        } catch (_) {}
        if (!mounted || !_overlaySync.isCurrent(syncId)) return;
      }

      final color =
          _colorFromHex(spawnZone.colorHex) ?? guildColor(spawnZone.teamId);
      final overlay = NPolygonOverlay(
        id: overlayId,
        coords: _closedRing(
          spawnZone.polygonPoints
              .map((point) => NLatLng(point.lat, point.lng))
              .toList(),
        ),
        color: color.withValues(alpha: 0.14),
        outlineColor: color.withValues(alpha: 0.9),
        outlineWidth: 4,
      );
      _spawnZoneOverlays[overlayId] = overlay;
      overlaysToAdd.add(overlay);
    }

    final staleSpawnIds = _spawnZoneOverlays.keys
        .where((overlayId) => !activeSpawnIds.contains(overlayId))
        .toList(growable: false);
    for (final overlayId in staleSpawnIds) {
      _spawnZoneOverlays.remove(overlayId);
      try {
        await controller.deleteOverlay(
          NOverlayInfo(type: NOverlayType.polygonOverlay, id: overlayId),
        );
      } catch (_) {}
      if (!mounted || !_overlaySync.isCurrent(syncId)) {
        return;
      }
    }

    // 모든 오버레이를 한 번의 platform call로 일괄 추가한다.
    if (overlaysToAdd.isNotEmpty) {
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
      await controller.addOverlayAll(overlaysToAdd);
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
    }

    _lastBattlefieldSignature = signature;
  }

  Future<void> _syncControlPointOverlays({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
    required int syncId,
  }) async {
    final signature = _controlPointSignature(fwState);
    if (_lastControlPointSignature == signature && _cpOverlays.isNotEmpty) {
      return;
    }

    final nextIds = <String>{};
    final overlaysToAdd = <NAddableOverlay>{};
    for (final controlPoint in fwState.controlPoints) {
      if (controlPoint.lat == null || controlPoint.lng == null) {
        continue;
      }

      nextIds.add(controlPoint.id);
      final existing = _cpOverlays[controlPoint.id];
      if (existing != null) {
        _applyControlPointOverlayState(
          overlay: existing,
          controlPoint: controlPoint,
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        );
        continue;
      }

      final overlay = _buildControlPointOverlay(
        controlPoint: controlPoint,
        fwState: fwState,
        mapState: mapState,
        myId: myId,
      );
      _cpOverlays[controlPoint.id] = overlay;
      overlaysToAdd.add(overlay);
    }

    if (overlaysToAdd.isNotEmpty) {
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
      await controller.addOverlayAll(overlaysToAdd);
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
    }

    final staleIds = _cpOverlays.keys
        .where((controlPointId) => !nextIds.contains(controlPointId))
        .toList(growable: false);
    for (final controlPointId in staleIds) {
      _cpOverlays.remove(controlPointId);
      try {
        await controller.deleteOverlay(
          NOverlayInfo(
              type: NOverlayType.circleOverlay, id: 'cp_$controlPointId'),
        );
      } catch (_) {}
      if (!mounted || !_overlaySync.isCurrent(syncId)) {
        return;
      }
    }

    _lastControlPointSignature = signature;
  }

  NCircleOverlay _buildControlPointOverlay({
    required FwControlPoint controlPoint,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final overlay = NCircleOverlay(
      id: 'cp_${controlPoint.id}',
      center: NLatLng(controlPoint.lat!, controlPoint.lng!),
      radius: 30,
      color: _cpFillColor(controlPoint).withValues(alpha: 0.25),
      outlineColor: _cpFillColor(controlPoint).withValues(alpha: 0.84),
      outlineWidth: 3,
    );
    _applyControlPointOverlayState(
      overlay: overlay,
      controlPoint: controlPoint,
      fwState: fwState,
      mapState: mapState,
      myId: myId,
    );
    return overlay;
  }

  void _applyControlPointOverlayState({
    required NCircleOverlay overlay,
    required FwControlPoint controlPoint,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final isSelected = controlPoint.id == _selectedControlPointId;
    final fillColor = _cpFillColor(controlPoint);
    final outlineColor = isSelected
        ? Colors.amberAccent
        : controlPoint.isBlockaded
            ? Colors.redAccent
            : fillColor.withValues(alpha: 0.84);

    overlay
      ..setCenter(NLatLng(controlPoint.lat!, controlPoint.lng!))
      ..setRadius(isSelected ? 38 : 30)
      ..setColor(fillColor.withValues(alpha: isSelected ? 0.34 : 0.25))
      ..setOutlineColor(outlineColor)
      ..setOutlineWidth(isSelected ? 5 : 3)
      ..setGlobalZIndex(isSelected ? 250 : 120)
      ..setOnTapListener((_) {
        unawaited(_handleControlPointTappedClean(
          controlPointId: controlPoint.id,
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        ));
      });
  }

  // ─── 거리 라벨 — 사용자 ↔ 가장 가까운 거점 점선 + 캡슐 ────────────────────
  Future<void> _syncDistanceLabel({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
    required int syncId,
  }) async {
    final ctx = context;
    if (!ctx.mounted) return;

    final myPos = mapState.myPosition;
    final nearest = _nearestControlPoint(fwState, mapState, myId);
    final dist = nearest == null
        ? null
        : _distanceToControlPoint(nearest, mapState, myId);

    final shouldShow = myPos != null &&
        nearest != null &&
        nearest.lat != null &&
        nearest.lng != null &&
        dist != null &&
        dist.isFinite &&
        dist > 8 &&
        dist < 800;

    if (!shouldShow) {
      if (_distanceLine != null) {
        try {
          await controller.deleteOverlay(
            const NOverlayInfo(
              type: NOverlayType.polylineOverlay,
              id: 'fw_dist_line',
            ),
          );
        } catch (_) {}
        _distanceLine = null;
      }
      if (_distanceLabelMarker != null) {
        try {
          await controller.deleteOverlay(
            const NOverlayInfo(
              type: NOverlayType.marker,
              id: 'fw_dist_label',
            ),
          );
        } catch (_) {}
        _distanceLabelMarker = null;
        _distanceLabelCacheKey = null;
      }
      return;
    }

    final start = NLatLng(myPos.latitude, myPos.longitude);
    final end = NLatLng(nearest.lat!, nearest.lng!);
    final mid = NLatLng(
      (start.latitude + end.latitude) / 2,
      (start.longitude + end.longitude) / 2,
    );

    // 점선 polyline (NaverMap 자체 dash 미지원 → 단순 솔리드, 약간 투명).
    if (_distanceLine == null) {
      final line = NPolylineOverlay(
        id: 'fw_dist_line',
        coords: [start, end],
        color: FwColors.ink900.withValues(alpha: 0.55),
        width: 2,
      );
      line.setGlobalZIndex(150);
      _distanceLine = line;
      await controller.addOverlay(line);
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
    } else {
      _distanceLine!.setCoords([start, end]);
    }

    // 거리 텍스트는 5m 단위로 양자화 (잦은 위젯→이미지 합성 방지).
    final bucket = (dist / 5).round();
    final cacheKey = 'dist:$bucket';
    if (_distanceLabelMarker != null && _distanceLabelCacheKey == cacheKey) {
      _distanceLabelMarker!.setPosition(mid);
      return;
    }

    if (!mounted) return;
    final ctxForIcon = context;
    final icon = await NOverlayImage.fromWidget(
      widget: FwDistanceCapsule(distanceMeters: dist),
      size: const Size(72, 28),
      // ignore: use_build_context_synchronously
      context: ctxForIcon,
    );
    if (!mounted || !_overlaySync.isCurrent(syncId)) return;

    if (_distanceLabelMarker == null) {
      final marker = NMarker(
        id: 'fw_dist_label',
        position: mid,
        icon: icon,
        size: const Size(72, 28),
        anchor: const NPoint(0.5, 0.5),
      );
      marker.setGlobalZIndex(260);
      _distanceLabelMarker = marker;
      await controller.addOverlay(marker);
    } else {
      _distanceLabelMarker!
        ..setPosition(mid)
        ..setIcon(icon);
    }
    _distanceLabelCacheKey = cacheKey;
  }

  String _controlPointSignature(FantasyWarsGameState fwState) {
    final buffer = StringBuffer();
    buffer.write(_selectedControlPointId ?? '');
    buffer.write('|');
    for (final controlPoint in fwState.controlPoints) {
      buffer
        ..write(controlPoint.id)
        ..write(':')
        ..write(controlPoint.capturedBy ?? '')
        ..write(':')
        ..write(controlPoint.capturingGuild ?? '')
        ..write(':')
        ..write(controlPoint.readyCount)
        ..write('/')
        ..write(controlPoint.requiredCount)
        ..write(':')
        ..write(controlPoint.blockadedBy ?? '')
        ..write(':')
        ..write(controlPoint.blockadeExpiresAt ?? 0)
        ..write(':')
        ..write(controlPoint.lat ?? 0)
        ..write(',')
        ..write(controlPoint.lng ?? 0)
        ..write('|');
    }
    return buffer.toString();
  }

  NMarker? _buildPlayerMarker({
    required String userId,
    required MemberState member,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool isSpeaking,
  }) {
    if ((member.lat == 0 && member.lng == 0) ||
        mapState.eliminatedUserIds.contains(userId)) {
      return null;
    }

    final marker = NMarker(
      id: 'player_$userId',
      position: NLatLng(member.lat, member.lng),
      size: const Size(
        _kFwPlayerMarkerBoxSize,
        _kFwPlayerMarkerBoxSize,
      ),
      anchor: const NPoint(0.5, 0.5),
    );
    _applyPlayerMarkerState(
      marker: marker,
      userId: userId,
      member: member,
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      isSpeaking: isSpeaking,
    );
    return marker;
  }

  void _applyPlayerMarkerState({
    required NMarker marker,
    required String userId,
    required MemberState member,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool isSpeaking,
  }) {
    final memberGuildId = _guildIdForUser(fwState.guilds, userId);
    final isMe = userId == myId;
    final isAlly = memberGuildId == fwState.myState.guildId;
    final isTrackedTarget = fwState.myState.isRevealActive &&
        fwState.myState.trackedTargetUserId == userId;
    final isSelected = userId == _selectedMemberId;

    final markerColor = isSelected
        ? Colors.amberAccent
        : isTrackedTarget
            ? Colors.amberAccent
            : isMe
                ? Colors.white
                : isAlly
                    ? guildColor(memberGuildId)
                    : Colors.red.shade300;
    final captionText = isMe
        ? '나'
        : isTrackedTarget
            ? '추적 ${member.nickname}'
            : member.nickname;

    // 발화 중 마커는 항상 최상단으로 끌어올린다 (selected/tracked 보다 한 단계 아래).
    marker.setCaption(
      NOverlayCaption(
        text: captionText,
        color: markerColor,
        textSize: 11,
        haloColor: Colors.black,
      ),
    );
    marker.setGlobalZIndex(isSelected
        ? 300
        : isTrackedTarget
            ? 240
            : isSpeaking
                ? 200
                : 160);
    marker.setOnTapListener((_) {
      unawaited(_handleMemberTappedClean(
        userId: userId,
        fwState: fwState,
        mapState: mapState,
        myId: myId,
      ));
    });

    // 아이콘 갱신: 캐시 hit 이면 즉시 동기 적용. miss 이면 비동기로 합성하고
    // 완료 시점에 의도가 여전히 동일한지 가드한 뒤 적용한다.
    _playerMarkerSpeakingIntent[userId] = isSpeaking;
    final cacheKey =
        'p:${markerColor.toARGB32().toRadixString(16)}:${isSpeaking ? 1 : 0}';
    final cached = _playerMarkerIconCache[cacheKey];
    if (cached != null) {
      marker.setIcon(cached);
    } else {
      unawaited(_loadAndApplyPlayerMarkerIcon(
        cacheKey: cacheKey,
        color: markerColor,
        isSpeaking: isSpeaking,
        userId: userId,
        marker: marker,
      ));
    }
  }

  Future<void> _loadAndApplyPlayerMarkerIcon({
    required String cacheKey,
    required Color color,
    required bool isSpeaking,
    required String userId,
    required NMarker marker,
  }) async {
    if (!mounted) return;
    // 비동기 시작 시점의 PlatformView 세대를 캡처. await 동안 PlatformView 가
    // 재생성되면 generation 이 올라가고, 그 시점부터 NOverlayImage 는 죽은
    // channel 에 묶이게 된다. 완료 후 generation 이 다르면 cache write 도 하면
    // 안 된다(그러면 새 세대의 cache 에 stale icon 이 박혀 다음 sync 에서 죽은
    // channel 에 setIcon 을 시도하게 된다).
    final iconGen = _markerIconGeneration;
    final ctx = context;
    final NOverlayImage icon;
    try {
      icon = await NOverlayImage.fromWidget(
        widget: _FwPlayerMarkerIcon(color: color, isSpeaking: isSpeaking),
        size: const Size(
          _kFwPlayerMarkerBoxSize,
          _kFwPlayerMarkerBoxSize,
        ),
        // ignore: use_build_context_synchronously
        context: ctx,
      );
    } catch (e) {
      // 위젯→비트맵 합성 실패 시 기본 핀 그대로 둠.
      debugPrint('[FW] player marker icon build failed: $e');
      return;
    }
    if (!mounted) return;
    if (iconGen != _markerIconGeneration) return;
    _playerMarkerIconCache[cacheKey] = icon;

    // race 가드: 비동기 시작 이후 더 새로운 speaking 변화가 들어왔으면 적용 스킵.
    if (_playerMarkerSpeakingIntent[userId] != isSpeaking) return;
    if (_playerMarkers[userId] != marker) return;
    marker.setIcon(icon);
  }

  Future<void> _syncPlayerMarkers({
    required NaverMapController controller,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
    required int syncId,
  }) async {
    final nextIds = <String>{};
    final markersToAdd = <NAddableOverlay>{};
    // remote(`voiceSpeakingProvider`) + self(`_isSelfSpeaking`) 합친 표시용 set.
    final speakingIds = _displaySpeakingIds();

    for (final entry in mapState.members.entries) {
      final userId = entry.key;
      final member = entry.value;
      if (!_shouldRenderPlayerMarker(userId, fwState, myId)) {
        continue;
      }
      if ((member.lat == 0 && member.lng == 0) ||
          mapState.eliminatedUserIds.contains(userId)) {
        continue;
      }

      nextIds.add(userId);
      final isSpeaking = speakingIds.contains(userId);
      final existing = _playerMarkers[userId];
      if (existing != null) {
        existing.setPosition(NLatLng(member.lat, member.lng));
        _applyPlayerMarkerState(
          marker: existing,
          userId: userId,
          member: member,
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          isSpeaking: isSpeaking,
        );
        continue;
      }

      final marker = _buildPlayerMarker(
        userId: userId,
        member: member,
        mapState: mapState,
        fwState: fwState,
        myId: myId,
        isSpeaking: isSpeaking,
      );
      if (marker == null) {
        continue;
      }

      _playerMarkers[userId] = marker;
      markersToAdd.add(marker);
    }

    if (markersToAdd.isNotEmpty) {
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
      await controller.addOverlayAll(markersToAdd);
      if (!mounted || !_overlaySync.isCurrent(syncId)) return;
    }

    final staleIds = _playerMarkers.keys
        .where((userId) => !nextIds.contains(userId))
        .toList(growable: false);
    for (final userId in staleIds) {
      _playerMarkers.remove(userId);
      _playerMarkerSpeakingIntent.remove(userId);
      try {
        await controller.deleteOverlay(
          NOverlayInfo(type: NOverlayType.marker, id: 'player_$userId'),
        );
      } catch (_) {}
      if (!mounted || !_overlaySync.isCurrent(syncId)) {
        return;
      }
    }
  }

  bool _shouldRenderPlayerMarker(
    String userId,
    FantasyWarsGameState fwState,
    String? myId,
  ) {
    if (userId == myId) {
      return false;
    }
    return fwState.myState.isRevealActive &&
        fwState.myState.trackedTargetUserId == userId;
  }

  void _scheduleOverlaySync(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    // 1차 게이트: state 객체 identity가 같으면 직접 overlay 동기화를 건너뛴다.
    // Riverpod Notifier가 새 state를 반환하지 않은 build에서는 O(1)로 종료한다.
    _overlaySync.schedule(
      fwState: fwState,
      mapState: mapState,
      myId: myId,
      selectedMemberId: _selectedMemberId,
      selectedControlPointId: _selectedControlPointId,
      syncOverlays: (syncId) async {
        if (!mounted) {
          return;
        }
        await _syncMapOverlays(fwState, mapState, myId, syncId);
      },
      onError: (error, stackTrace) {
        debugPrint('[FantasyWars] overlay sync failed: $error');
        debugPrintStack(
          label: '[FantasyWars] overlay sync stack',
          stackTrace: stackTrace,
        );
      },
    );

    // 2차 게이트: 내용 기반 signature. 다른 인스턴스라도 내용이 같으면 skip.
    // debounce 완화: 매 rebuild마다 platform call이 나가지 않도록 방지한다.
  }

  void _handleStateSideEffectsClean(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    if (!_lastWasKicked && mapState.wasKicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoutes.home);
        }
      });
    }
    _lastWasKicked = mapState.wasKicked;

    if (_lastDuelPhase != 'invalidated' &&
        fwState.duel.phase == 'invalidated') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('대결이 무효 처리되었습니다.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      });
    }
    _lastDuelPhase = fwState.duel.phase;

    _syncToastFromRecentEvents(fwState);
    _syncBleDuelPresence(fwState, mapState, myId);
    _scheduleOverlaySync(fwState, mapState, myId);
  }

  void _handleStateSideEffects(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    if (!_lastWasKicked && mapState.wasKicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoutes.home);
        }
      });
    }
    _lastWasKicked = mapState.wasKicked;

    if (_lastDuelPhase != 'invalidated' &&
        fwState.duel.phase == 'invalidated') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('대결이 무효 처리되었습니다.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      });
    }
    _lastDuelPhase = fwState.duel.phase;

    _syncToastFromRecentEvents(fwState);
    _syncBleDuelPresence(fwState, mapState, myId);
    _scheduleOverlaySync(fwState, mapState, myId);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 8-레이어 UI 전용 헬퍼들
  // ─────────────────────────────────────────────────────────────────────

  FwDuelPhase _resolveDuelPhase(String phase) => switch (phase) {
        'challenging' => FwDuelPhase.pendingSent,
        'accepted' => FwDuelPhase.accepted,
        'challenged' => FwDuelPhase.pendingReceived,
        'in_game' => FwDuelPhase.inGame,
        'result' || 'invalidated' => FwDuelPhase.result,
        _ => FwDuelPhase.none,
      };

  String _dungeonStatusLabel(FantasyWarsGameState fwState) {
    if (fwState.dungeons.isEmpty) {
      return '던전 · 정보 없음';
    }
    final d = fwState.dungeons.first;
    final label = switch (d.status) {
      'open' => '열림',
      'cleared' => '정리됨',
      'closed' => '폐쇄',
      _ => d.status,
    };
    return '던전 · ${d.displayName} · $label';
  }

  String? _relicHolderLabel(
      FantasyWarsGameState fwState, MapSessionState mapState) {
    if (fwState.dungeons.isEmpty) return null;
    final heldBy = fwState.dungeons.first.artifact.heldBy;
    if (heldBy == null || heldBy.isEmpty) {
      return '성유물 · 없음';
    }
    final label = mapState.members[heldBy]?.nickname ?? heldBy;
    return '성유물 · $label';
  }

  String? _trackedTargetLabel(
      FantasyWarsGameState fwState, Map<String, String> memberLabels) {
    final myState = fwState.myState;
    if (myState.job != 'ranger' || !myState.isRevealActive) return null;
    final id = myState.trackedTargetUserId;
    if (id == null) return null;
    return '추적 · ${memberLabels[id] ?? id}';
  }

  String? _resolveOpponentLabel(
      FantasyWarsGameState fwState, Map<String, String> memberLabels) {
    final id = fwState.duel.opponentId;
    if (id == null) return null;
    return memberLabels[id] ?? id;
  }

  List<FwChatMessage> _composeChatMessages(
    FantasyWarsGameState fwState,
    List<_FwAiChatLine> aiChatLines,
  ) {
    // AI/유저 라인 + 게임 이벤트(recentEvents)를 시간순 통합.
    final out = <FwChatMessage>[];
    for (final line in aiChatLines) {
      out.add(FwChatMessage(
        type: switch (line.role) {
          'user' => FwChatType.user,
          'ai' => FwChatType.ai,
          _ => FwChatType.gameEvent,
        },
        text: line.text,
        createdAt: line.createdAt,
      ));
    }
    for (final ev in fwState.recentEvents.take(8)) {
      out.add(FwChatMessage(
        type: FwChatType.gameEvent,
        text: ev.message,
        createdAt: DateTime.fromMillisecondsSinceEpoch(ev.recordedAt),
      ));
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (out.isEmpty) {
      out.add(FwChatMessage(
        type: FwChatType.gameEvent,
        text: switch (fwState.status) {
          'in_progress' => '게임이 시작되었습니다. 주변을 탐색하세요.',
          'finished' => '게임이 종료되었습니다.',
          _ => '게임 준비 중입니다.',
        },
        createdAt: DateTime.now(),
      ));
    }
    return out;
  }

  /// Layer 7 토스트: recentEvents 의 최신 항목이 새로 들어왔을 때 잠깐 표시.
  void _syncToastFromRecentEvents(FantasyWarsGameState fwState) {
    if (fwState.recentEvents.isEmpty) {
      return;
    }
    final latest = fwState.recentEvents.first;
    if (_lastToastEventAt == latest.recordedAt) {
      return;
    }
    _lastToastEventAt = latest.recordedAt;

    if (!mounted) {
      return;
    }
    setState(() {
      _toastMessage = latest.message;
      _toastKind = latest.kind;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _toastMessage = null;
        _toastKind = null;
      });
    });
  }

  void _syncBleDuelPresence(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    final shouldRun = fwState.isStarted && !fwState.isFinished && myId != null;
    if (!shouldRun) {
      if (_blePresenceStartKey != null) {
        _blePresenceStartKey = null;
        unawaited(ref.read(bleDuelProvider.notifier).stopAfterDuel());
      }
      return;
    }

    final memberIds = _bleMemberIds(mapState, myId);
    final nextKey = '${widget.sessionId}|$myId|${memberIds.join(',')}';
    final bleState = ref.read(bleDuelProvider);
    if (_blePresenceStartKey == nextKey &&
        bleState.phase != BleDuelPhase.idle) {
      return;
    }
    if (bleState.phase == BleDuelPhase.starting ||
        bleState.phase == BleDuelPhase.running) {
      _blePresenceStartKey = nextKey;
      return;
    }

    _blePresenceStartKey = nextKey;
    unawaited(
      ref.read(bleDuelProvider.notifier).startForDuel(
            sessionId: widget.sessionId,
            userId: myId,
            memberUserIds: memberIds,
          ),
    );
  }

  List<String> _bleMemberIds(MapSessionState mapState, String myId) {
    final ids = <String>{
      myId,
      ...mapState.members.keys,
      ...mapState.memberDistances.keys,
    }.toList()
      ..sort();
    return ids;
  }

  /// HUD voice chip 라벨: in_progress + 길드 있음 → 길드 표시명, 그 외 → '로비'.
  /// 백엔드 `getVoicePolicy` 와 동일 로직 — server-side `team:{guildId}` 채널과
  /// 정합성을 유지한다.
  String _voiceChannelLabel(FantasyWarsGameState fwState) {
    if (fwState.status != 'in_progress') return '로비';
    final guildId = fwState.myState.guildId;
    if (guildId == null || guildId.isEmpty) return '로비';
    return fwState.guilds[guildId]?.displayName ?? '길드';
  }

  Color _voiceChannelColor(FantasyWarsGameState fwState) {
    if (fwState.status != 'in_progress') return FwColors.ink500;
    final guildId = fwState.myState.guildId;
    if (guildId == null || guildId.isEmpty) return FwColors.ink500;
    return guildColor(guildId);
  }

  /// Step 3 진입점: remote(`voiceSpeakingProvider`) + self(`_isSelfSpeaking`)
  /// 두 소스를 합쳐 마커/HUD 가 사용할 발화 userId 집합을 반환.
  /// Step 2 단계에서는 호출처가 없으므로 file-level `unused_element` ignore 가
  /// 경고를 흡수한다.
  Set<String> _displaySpeakingIds() {
    final remote = ref.read(voiceSpeakingProvider(widget.sessionId));
    if (!_isSelfSpeaking) return remote;
    final myId = ref.read(authProvider).valueOrNull?.id;
    if (myId == null || myId.isEmpty || remote.contains(myId)) return remote;
    return {...remote, myId};
  }

  Color _cpFillColor(FwControlPoint controlPoint) {
    if (controlPoint.capturedBy != null) {
      return guildColor(controlPoint.capturedBy);
    }
    if (controlPoint.capturingGuild != null) {
      return guildColor(controlPoint.capturingGuild).withValues(alpha: 0.5);
    }
    return Colors.white;
  }

  String _battlefieldSignature(FantasyWarsGameState fwState) {
    final buffer = StringBuffer();
    for (final point in fwState.playableArea) {
      buffer
        ..write(point.lat)
        ..write(',')
        ..write(point.lng)
        ..write('|');
    }
    buffer.write('#');
    for (final spawnZone in fwState.spawnZones) {
      buffer
        ..write(spawnZone.teamId)
        ..write(':')
        ..write(spawnZone.colorHex ?? '')
        ..write(':');
      for (final point in spawnZone.polygonPoints) {
        buffer
          ..write(point.lat)
          ..write(',')
          ..write(point.lng)
          ..write(';');
      }
      buffer.write('|');
    }
    return buffer.toString();
  }

  Color? _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) {
      return null;
    }

    final normalized = hex.replaceFirst('#', '');
    final argb = normalized.length == 6 ? 'FF$normalized' : normalized;
    final value = int.tryParse(argb, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(value);
  }

  Future<void> _confirmLeaveClean() async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('게임 나가기'),
            content: const Text('정말로 게임을 나가시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('나가기'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldLeave && mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _confirmLeave() async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('게임 나가기'),
            content: const Text('정말로 게임을 나가시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('나가기'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLeave || !mounted) {
      return;
    }

    await ref
        .read(sessionRepositoryProvider)
        .leaveSession(widget.sessionId)
        .catchError((_) {});
    SocketService().leaveSession(sessionId: widget.sessionId);
    if (!mounted) {
      return;
    }
    context.go(AppRoutes.home);
  }

  String? _guildIdForUser(Map<String, FwGuildInfo> guilds, String userId) {
    return _geo.guildIdForUser(guilds, userId);
  }

  ({double lat, double lng})? _myPosition(
      MapSessionState mapState, String? myId) {
    return _geo.myPosition(mapState, myId);
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    return _geo.distanceMeters(lat1, lng1, lat2, lng2);
  }

  FwControlPoint? _nearestControlPoint(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    return _targeting.nearestControlPoint(fwState, mapState, myId);
  }

  double? _distanceToControlPoint(
    FwControlPoint controlPoint,
    MapSessionState mapState,
    String? myId,
  ) {
    return _geo.distanceToControlPoint(controlPoint, mapState, myId);
  }

  ({int count, int required}) _captureCrewStatus(
    FwControlPoint controlPoint,
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    return _geo.captureCrewStatus(
      controlPoint,
      fwState,
      mapState,
      myId,
      captureRadiusMeters: _captureRadiusMeters,
      minCaptureMemberCount: _minCaptureMemberCount,
    );
  }

  int _captureRequiredCount(FwControlPoint controlPoint) {
    return _geo.captureRequiredCount(
      controlPoint,
      minCaptureMemberCount: _minCaptureMemberCount,
    );
  }

  double? _distanceToMember(
    String userId,
    MapSessionState mapState,
    String? myId,
  ) {
    return _geo.distanceToMember(userId, mapState, myId);
  }

  FwDuelProximityContext? _duelProximityForUser(
    String userId,
    MapSessionState mapState,
    String? myId,
  ) {
    final fwState = ref.read(fantasyWarsProvider(widget.sessionId));
    return _duelProximity.forTarget(
      targetUserId: userId,
      mapState: mapState,
      myUserId: myId,
      allowGpsFallbackWithoutBle: fwState.allowGpsFallbackWithoutBle,
      bleFreshnessWindowMs: fwState.bleEvidenceFreshnessMs,
      gpsFallbackMaxRangeMeters: fwState.duelRangeMeters.toDouble(),
    );
  }

  List<String> _candidateMemberIds({
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
    bool nearbyOnly = false,
  }) {
    return _targeting.candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: enemy,
      includeSelf: includeSelf,
      nearbyOnly: nearbyOnly,
      proximityForUser: (userId) =>
          _duelProximityForUser(userId, mapState, myId),
    );
  }

  List<FwControlPoint> _candidateControlPoints(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    return _targeting.candidateControlPoints(fwState, mapState, myId);
  }

  bool _isOutsideBattlefield(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) {
    return _geo.isOutsideBattlefield(fwState, mapState, myId);
  }

  bool _containsPoint({
    required List<FwGeoPoint> polygon,
    required double lat,
    required double lng,
  }) {
    return _geo.containsPoint(polygon: polygon, lat: lat, lng: lng);
  }

  ({double lat, double lng})? _battlefieldCenter(
    FantasyWarsGameState fwState,
  ) {
    return _geo.battlefieldCenter(fwState);
  }

  Future<void> _handleBattlefieldWarningClean(
    FantasyWarsGameState fwState,
  ) async {
    _showError('전장 영역을 벗어났습니다. 전장 안으로 이동해 주세요.');
    final center = _battlefieldCenter(fwState);
    if (center == null) {
      return;
    }
    await _focusMapTarget(
      lat: center.lat,
      lng: center.lng,
      zoom: 15.2,
    );
  }

  Future<void> _handleBattlefieldWarning(
    FantasyWarsGameState fwState,
  ) async {
    _showError('전장 영역을 벗어났습니다. 전장 안으로 이동해 주세요.');
    final center = _battlefieldCenter(fwState);
    if (center == null) {
      return;
    }
    await _focusMapTarget(
      lat: center.lat,
      lng: center.lng,
      zoom: 15.2,
    );
  }

  Future<T?> _showTargetSheet<T>({
    required String title,
    required List<_TargetChoice<T>> choices,
  }) async {
    if (choices.isEmpty || !mounted) {
      return null;
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${choices.length}개',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: choices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final choice = choices[index];
                      final accent = choice.accentColor ?? Colors.white70;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(choice.value),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: choice.isHighlighted
                                  ? accent.withValues(alpha: 0.14)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: choice.isHighlighted
                                    ? accent.withValues(alpha: 0.8)
                                    : Colors.white12,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(choice.icon, color: accent),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                choice.label,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            if (choice.badge != null)
                                              FwChoiceBadge(
                                                label: choice.badge!,
                                                color: accent,
                                              ),
                                          ],
                                        ),
                                        if (choice.subtitle != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            choice.subtitle!,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        if (choice.helper != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            choice.helper!,
                                            style: TextStyle(
                                              color: accent.withValues(
                                                  alpha: 0.92),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (choice.trailing != null) ...[
                                    const SizedBox(width: 12),
                                    Text(
                                      choice.trailing!,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _pickMemberTargetClean({
    required String title,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
    bool nearbyOnly = false,
  }) {
    final userIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: enemy,
      includeSelf: includeSelf,
      nearbyOnly: nearbyOnly,
    );

    final choices = userIds.map((userId) {
      final nickname =
          userId == myId ? '나' : _memberLabelClean(mapState.members, userId);
      final distance = _distanceToMember(userId, mapState, myId);
      final guildId = _guildIdForUser(fwState.guilds, userId);
      final guildName = guildId == null
          ? null
          : fwState.guilds[guildId]?.displayName ?? guildId;
      final isNearest = userIds.isNotEmpty && identical(userIds.first, userId);
      final duelProximity =
          nearbyOnly ? _duelProximityForUser(userId, mapState, myId) : null;
      return _TargetChoice(
        value: userId,
        label: nickname,
        subtitle: guildName ?? (userId == myId ? '현재 플레이어' : '길드 정보 없음'),
        trailing: distance != null && distance.isFinite
            ? '${distance.round()}m'
            : '거리 불명',
        badge: userId == myId
            ? '나'
            : nearbyOnly
                ? (duelProximity?.source == 'ble' ? 'BLE' : 'GPS')
                : enemy
                    ? '적'
                    : '아군',
        helper: nearbyOnly
            ? (duelProximity?.source == 'ble' ? 'BLE 근접 확인' : 'GPS 거리 확인')
            : (isNearest ? '현재 위치 기준 가장 가까운 대상' : null),
        accentColor: userId == myId
            ? Colors.white
            : enemy
                ? Colors.redAccent
                : guildColor(guildId),
        icon: userId == myId
            ? Icons.person_pin_circle_outlined
            : enemy
                ? Icons.gps_fixed_rounded
                : Icons.shield_outlined,
        isHighlighted: isNearest,
      );
    }).toList();
    return _showTargetSheet(title: title, choices: choices);
  }

  Future<String?> _pickControlPointTargetClean({
    required String title,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final controlPoints = _candidateControlPoints(fwState, mapState, myId);
    final choices = controlPoints.map((controlPoint) {
      final distance = _distanceToControlPoint(controlPoint, mapState, myId);
      final isNearest =
          controlPoints.isNotEmpty && controlPoints.first.id == controlPoint.id;
      final ownerGuild = controlPoint.capturedBy == null
          ? null
          : fwState.guilds[controlPoint.capturedBy!]?.displayName ??
              controlPoint.capturedBy;
      final isOwnedByMe = controlPoint.capturedBy == fwState.myState.guildId;
      final badge = controlPoint.isBlockaded
          ? '봉쇄됨'
          : ownerGuild == null
              ? '미점령'
              : isOwnedByMe
                  ? '아군'
                  : '적군';
      final helper = controlPoint.requiredCount > 0
          ? '점령 준비 ${controlPoint.readyCount}/${controlPoint.requiredCount}'
          : controlPoint.capturingGuild != null
              ? '점령 진행 중'
              : null;
      return _TargetChoice(
        value: controlPoint.id,
        label: controlPoint.displayName,
        subtitle: ownerGuild == null ? '미점령 거점' : '점령 길드 · $ownerGuild',
        trailing: distance != null && distance.isFinite
            ? '${distance.round()}m'
            : '거리 불명',
        badge: badge,
        helper: helper ?? (isNearest ? '현재 위치 기준 가장 가까운 거점' : null),
        accentColor: controlPoint.isBlockaded
            ? Colors.redAccent
            : _cpFillColor(controlPoint),
        icon: Icons.place_rounded,
        isHighlighted: isNearest,
      );
    }).toList();
    return _showTargetSheet(title: title, choices: choices);
  }

  String _memberLabelClean(Map<String, MemberState> members, String? userId) {
    if (userId == null) {
      return '대상 없음';
    }
    return members[userId]?.nickname ?? userId;
  }

  Future<String?> _pickMemberTarget({
    required String title,
    required MapSessionState mapState,
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
    bool nearbyOnly = false,
  }) {
    final userIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: enemy,
      includeSelf: includeSelf,
      nearbyOnly: nearbyOnly,
    );

    final choices = userIds.map((userId) {
      final nickname =
          userId == myId ? '나' : _memberLabel(mapState.members, userId);
      final distance = _distanceToMember(userId, mapState, myId);
      final guildId = _guildIdForUser(fwState.guilds, userId);
      final guildName = guildId == null
          ? null
          : fwState.guilds[guildId]?.displayName ?? guildId;
      final isNearest = userIds.isNotEmpty && identical(userIds.first, userId);
      final duelProximity =
          nearbyOnly ? _duelProximityForUser(userId, mapState, myId) : null;
      return _TargetChoice(
        value: userId,
        label: nickname,
        subtitle: guildName ?? (userId == myId ? '현재 플레이어' : '길드 정보 없음'),
        trailing: distance != null && distance.isFinite
            ? '${distance.round()}m'
            : '거리 불명',
        badge: userId == myId
            ? '자신'
            : nearbyOnly
                ? (duelProximity?.source == 'ble' ? 'BLE' : '근접')
                : enemy
                    ? '적'
                    : '아군',
        helper: nearbyOnly
            ? (duelProximity?.source == 'ble' ? 'BLE 근접 확인' : '근거리 결투 가능')
            : (isNearest ? '현재 위치 기준 가장 가까운 대상' : null),
        accentColor: userId == myId
            ? Colors.white
            : enemy
                ? Colors.redAccent
                : guildColor(guildId),
        icon: userId == myId
            ? Icons.person_pin_circle_outlined
            : enemy
                ? Icons.gps_fixed_rounded
                : Icons.shield_outlined,
        isHighlighted: isNearest,
      );
    }).toList();
    return _showTargetSheet(title: title, choices: choices);
  }

  Future<String?> _pickControlPointTarget({
    required String title,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) {
    final controlPoints = _candidateControlPoints(fwState, mapState, myId);
    final choices = controlPoints.map((controlPoint) {
      final distance = _distanceToControlPoint(controlPoint, mapState, myId);
      final isNearest =
          controlPoints.isNotEmpty && controlPoints.first.id == controlPoint.id;
      final ownerGuild = controlPoint.capturedBy == null
          ? null
          : fwState.guilds[controlPoint.capturedBy!]?.displayName ??
              controlPoint.capturedBy;
      final isOwnedByMe = controlPoint.capturedBy == fwState.myState.guildId;
      final badge = controlPoint.isBlockaded
          ? '봉쇄'
          : ownerGuild == null
              ? '중립'
              : isOwnedByMe
                  ? '아군'
                  : '적군';
      final helper = controlPoint.requiredCount > 0
          ? '점령 준비 ${controlPoint.readyCount}/${controlPoint.requiredCount}'
          : controlPoint.capturingGuild != null
              ? '점령 진행 중'
              : null;
      return _TargetChoice(
        value: controlPoint.id,
        label: controlPoint.displayName,
        subtitle: ownerGuild == null ? '미점령 거점' : '점령 길드 · $ownerGuild',
        trailing: distance != null && distance.isFinite
            ? '${distance.round()}m'
            : '거리 불명',
        badge: badge,
        helper: helper ?? (isNearest ? '현재 위치 기준 가장 가까운 거점' : null),
        accentColor: controlPoint.isBlockaded
            ? Colors.redAccent
            : _cpFillColor(controlPoint),
        icon: Icons.place_rounded,
        isHighlighted: isNearest,
      );
    }).toList();
    return _showTargetSheet(title: title, choices: choices);
  }

  String _memberLabel(Map<String, MemberState> members, String? userId) {
    if (userId == null) {
      return '대상 없음';
    }
    return members[userId]?.nickname ?? userId;
  }

  FwControlPoint? _controlPointById(
      FantasyWarsGameState fwState, String? controlPointId) {
    if (controlPointId == null) {
      return null;
    }
    for (final controlPoint in fwState.controlPoints) {
      if (controlPoint.id == controlPointId) {
        return controlPoint;
      }
    }
    return null;
  }

  String? _preferredSelectedMember({
    required FantasyWarsGameState fwState,
    required String? myId,
    required bool enemy,
    bool includeSelf = false,
  }) {
    final selectedUserId = _selectedMemberId;
    if (selectedUserId == null) {
      return null;
    }
    if (selectedUserId == myId && !includeSelf) {
      return null;
    }
    if (fwState.eliminatedPlayerIds.contains(selectedUserId)) {
      return null;
    }

    final memberGuildId = _guildIdForUser(fwState.guilds, selectedUserId);
    if (enemy) {
      return memberGuildId != null && memberGuildId != fwState.myState.guildId
          ? selectedUserId
          : null;
    }
    if (selectedUserId == myId) {
      return selectedUserId;
    }
    return memberGuildId != null && memberGuildId == fwState.myState.guildId
        ? selectedUserId
        : null;
  }

  void _setSelection({
    String? memberId,
    String? controlPointId,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedMemberId = memberId;
      _selectedControlPointId = controlPointId;
    });
    _overlaySync.invalidate();
  }

  Future<void> _focusMapTarget({
    required double lat,
    required double lng,
    double zoom = 16.4,
  }) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }
    try {
      await controller.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(lat, lng),
          zoom: zoom,
        )..setAnimation(animation: NCameraAnimation.easing),
      );
    } catch (_) {}
  }

  NLatLng _resolveInitialMapTarget(MapSessionState mapState) {
    final cached = _initialMapTarget;
    if (cached != null) {
      return cached;
    }

    final position = mapState.myPosition;
    final target = position == null
        ? const NLatLng(37.5665, 126.9780)
        : NLatLng(position.latitude, position.longitude);
    _initialMapTarget = target;
    return target;
  }

  Widget _stableMapLayer(NLatLng initialTarget) {
    _stableMapInitialTarget ??= initialTarget;
    final cached = _stableNaverMapLayer;
    if (cached != null) {
      return cached;
    }

    _naverMapCreateCount += 1;
    debugPrint(
      '[FW-MAP] NaverMap widget create #$_naverMapCreateCount '
      '(ready #$_naverMapReadyCount)',
    );

    final layer = Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth == 0 ||
              constraints.maxHeight == 0) {
            return const SizedBox.shrink();
          }
          return SizedBox.expand(
            child: RepaintBoundary(
              child: NaverMap(
                key: _mapViewKey,
                options: NaverMapViewOptions(
                  locationButtonEnable: false,
                  initialCameraPosition: NCameraPosition(
                    target: _stableMapInitialTarget!,
                    zoom: 16,
                  ),
                ),
                onMapTapped: (_, __) {
                  if (_selectedMemberId != null ||
                      _selectedControlPointId != null) {
                    _setSelection();
                  }
                },
                onMapReady: _handleNaverMapReady,
              ),
            ),
          );
        },
      ),
    );
    _stableNaverMapLayer = layer;
    return layer;
  }

  Future<void> _handleNaverMapReady(NaverMapController controller) async {
    _naverMapReadyCount += 1;
    debugPrint(
      '[FW-MAP] onMapReady fired #$_naverMapReadyCount '
      '(create #$_naverMapCreateCount)',
    );
    debugPrint('[FW-BOOT] NaverMap onMapReady fired ??platform view ready');
    _mapController = controller;
    // PlatformView 가 새로 생성된 경우 이전 컨트롤러에 매여 있던 overlay 객체들은
    // 이미 죽은 method channel(flutter_naver_map_overlay#N) 을 가리킨다.
    // 다음 sync 가 그 객체에 .center / .radius 를 set 하면 MissingPluginException
    // 폭주가 난다. 컬렉션을 통째로 비우고 generation 을 bump 해서 in-flight
    // sync 콜백도 abort 시킨다.
    _cpOverlays.clear();
    _spawnZoneOverlays.clear();
    _playerMarkers.clear();
    // PlatformView 재생성 시에만 이전 NOverlayImage 가 죽은 channel 에 묶여 있을
    // 수 있으므로 icon cache 를 비운다. 첫 진입에는 cache 가 비어 있고 보존해도
    // 무해하므로 NOverlayImage.fromWidget 재합성을 피하기 위해 유지한다.
    if (_pendingPlatformViewReplacement) {
      _playerMarkerIconCache.clear();
      _playerMarkerSpeakingIntent.clear();
      _pendingPlatformViewReplacement = false;
      debugPrint(
        '[FW-MAP] PlatformView replaced — cleared player marker icon cache',
      );
    }
    _playableAreaOverlay = null;
    _distanceLabelMarker = null;
    _distanceLine = null;
    _distanceLabelCacheKey = null;
    _overlaySync.invalidate();
    _lastControlPointSignature = null;
    _lastBattlefieldSignature = null;
    if (mounted) {
      setState(() {
        _naverMapWidgetReady = true;
        _naverMapWidgetError = null;
        _naverMapWidgetTimer?.cancel();
      });
      debugPrint(
          '[FW-BOOT] NaverMap widget ready ??first renderable state achieved');
    }
    // mediasoup Device.load + BG service flutter engine boot 가 NaverMap
    // PlatformView 첫 attach 와 같은 프레임에 메인스레드를 점유하지 않도록,
    // map_session_provider 측의 두 비동기 작업이 이 시그널을 기다린다.
    ref
        .read(mapSessionProvider(widget.sessionId).notifier)
        .signalFirstMapReady();
    try {
      controller.setLocationTrackingMode(
        NLocationTrackingMode.noFollow,
      );
    } catch (_) {}
    if (!mounted) {
      return;
    }
    // 첫 overlay sync 는 onMapReady 와 같은 프레임에서 시작하지 않는다.
    // PlatformView attach + mediasoup Device.load + 첫 sync 가 같은 ~2초 구간에
    // 몰려 Davey 1.8~2초 jank 가 발생하므로, 첫 프레임을 양보한 뒤 짧은 지연을
    // 둬 platform-view init 비용을 분산시킨다. invalidate() 는 위에서 즉시 처리
    // 했으므로 in-flight sync 가 살아남지 않는다.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    // delay 중 최신 fwState/mapState 가 들어왔을 수 있으므로 여기서 다시 read.
    final fwState = ref.read(fantasyWarsProvider(widget.sessionId));
    final mapState = ref.read(mapSessionProvider(widget.sessionId));
    final myId = ref.read(authProvider).valueOrNull?.id;
    _scheduleOverlaySync(fwState, mapState, myId);
  }

  void _syncFocusWithBootstrapVisibility(bool showBootstrapView) {
    if (_lastShowBootstrapView == showBootstrapView) {
      return;
    }
    _lastShowBootstrapView = showBootstrapView;

    // Track only the visibility edge. Forcing unfocus during bootstrap
    // transitions can create IME show/hide and viewport metric churn.
  }

  Future<void> _focusMyLocationClean(MapSessionState mapState) async {
    final position = mapState.myPosition;
    if (position == null) {
      _showError('현재 위치를 아직 확인하지 못했습니다.');
      return;
    }

    await _focusMapTarget(
      lat: position.latitude,
      lng: position.longitude,
      zoom: 17,
    );
  }

  Future<void> _focusMyLocation(MapSessionState mapState) async {
    final position = mapState.myPosition;
    if (position == null) {
      _showError('현재 위치를 아직 확인하지 못했습니다.');
      return;
    }

    await _focusMapTarget(
      lat: position.latitude,
      lng: position.longitude,
      zoom: 17,
    );
  }

  String? _telemetryLabel(MapSessionState mapState) {
    final timestamp = mapState.myPosition?.timestamp;
    if (timestamp != null) {
      final ageMs = DateTime.now().difference(timestamp).inMilliseconds;
      if (ageMs >= 0 && ageMs < 60000) {
        return 'GPS ${ageMs}ms';
      }
    }
    return mapState.isConnected ? 'Socket ?곌껐' : 'Socket ?딄?';
  }

  Future<void> _focusRecentEvent(
    FwRecentEvent event, {
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
  }) async {
    final controlPointId = event.controlPointId;
    if (controlPointId != null) {
      final controlPoint = _controlPointById(fwState, controlPointId);
      if (controlPoint != null) {
        _setSelection(memberId: null, controlPointId: controlPointId);
        if (controlPoint.lat != null && controlPoint.lng != null) {
          await _focusMapTarget(
            lat: controlPoint.lat!,
            lng: controlPoint.lng!,
            zoom: 16.2,
          );
        }
        return;
      }
    }

    final memberId = event.primaryUserId ?? event.secondaryUserId;
    if (memberId == null) {
      if (controlPointId != null) {
        _setSelection(memberId: null, controlPointId: controlPointId);
      }
      return;
    }

    final member = mapState.members[memberId];
    _setSelection(memberId: memberId, controlPointId: null);
    if (member == null || (member.lat == 0 && member.lng == 0)) {
      return;
    }

    await _focusMapTarget(
      lat: member.lat,
      lng: member.lng,
      zoom: 16.8,
    );
  }

  Future<void> _openRecentEventDetails(FwRecentEvent event) async {
    if (!mounted) {
      return;
    }
    final fwState = ref.read(fantasyWarsProvider(widget.sessionId));
    final mapState = ref.read(mapSessionProvider(widget.sessionId));
    final myId = ref.read(authProvider).valueOrNull?.id;

    await _focusRecentEvent(
      event,
      fwState: fwState,
      mapState: mapState,
    );

    if (!mounted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) {
      return;
    }

    final controlPointId = event.controlPointId;
    if (controlPointId != null &&
        _controlPointById(fwState, controlPointId) != null) {
      await _handleControlPointTappedClean(
        controlPointId: controlPointId,
        fwState: fwState,
        mapState: mapState,
        myId: myId,
      );
      return;
    }

    String? memberId;
    for (final candidateUserId in [
      event.primaryUserId,
      event.secondaryUserId
    ]) {
      if (candidateUserId != null &&
          mapState.members.containsKey(candidateUserId)) {
        memberId = candidateUserId;
        break;
      }
    }
    if (memberId != null) {
      await _handleMemberTappedClean(
        userId: memberId,
        fwState: fwState,
        mapState: mapState,
        myId: myId,
      );
    }
  }

  Future<void> _handleMemberTappedClean({
    required String userId,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) async {
    _setSelection(memberId: userId, controlPointId: null);

    final member = mapState.members[userId];
    final guildId = _guildIdForUser(fwState.guilds, userId);
    final guildLabel = guildId == null
        ? '길드 정보 없음'
        : fwState.guilds[guildId]?.displayName ?? guildId;
    final distance = _distanceToMember(userId, mapState, myId);
    final isEnemy = guildId != null && guildId != fwState.myState.guildId;
    final isSelf = userId == myId;
    final isAlly =
        !isSelf && guildId != null && guildId == fwState.myState.guildId;
    final canAct = fwState.myState.isAlive && !fwState.myState.inDuel;
    final duelProximity = _duelProximityForUser(userId, mapState, myId);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);

    final actions = <_QuickAction>[];
    if (canAct &&
        isEnemy &&
        fwState.duel.phase == 'idle' &&
        duelProximity != null) {
      actions.add(
        _QuickAction(
          label: '대결 요청',
          icon: Icons.sports_martial_arts_rounded,
          color: const Color(0xFF991B1B),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.challengeDuel(
                  userId,
                  proximity: duelProximity.toMap(),
                ));
          },
        ),
      );
    }
    if (canAct && fwState.myState.job == 'ranger' && isEnemy) {
      actions.add(
        _QuickAction(
          label: '추적 사용',
          icon: Icons.gps_fixed_rounded,
          color: const Color(0xFF0F766E),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(targetUserId: userId));
          },
        ),
      );
    }
    if (canAct && fwState.myState.job == 'priest' && (isAlly || isSelf)) {
      actions.add(
        _QuickAction(
          label: '보호막 부여',
          icon: Icons.shield_outlined,
          color: const Color(0xFF4338CA),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(targetUserId: userId));
          },
        ),
      );
    }

    await _showQuickActionSheet(
      title: member?.nickname ?? userId,
      subtitle: [
        guildLabel,
        if (distance != null && distance.isFinite) '${distance.round()}m',
        if (isSelf) '나',
      ].join(' · '),
      accentColor: isEnemy
          ? Colors.redAccent
          : isSelf
              ? Colors.white
              : guildColor(guildId),
      lines: [
        if (member != null) '상태 · ${member.status}',
        if (fwState.eliminatedPlayerIds.contains(userId)) '전투 불가 · 탈락 상태',
        if (isEnemy && !canAct) '현재 상태에서는 상호작용할 수 없습니다.',
      ],
      actions: actions,
    );
  }

  Future<void> _handleControlPointTappedClean({
    required String controlPointId,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) async {
    final controlPoint = _controlPointById(fwState, controlPointId);
    if (controlPoint == null) {
      return;
    }

    _setSelection(memberId: null, controlPointId: controlPointId);

    final distance = _distanceToControlPoint(controlPoint, mapState, myId);
    final crew = _captureCrewStatus(controlPoint, fwState, mapState, myId);
    final isCancelling = fwState.myState.captureZone == controlPoint.id &&
        controlPoint.capturingGuild == fwState.myState.guildId;
    final canReachCapture = fwState.myState.isAlive &&
        !fwState.myState.inDuel &&
        (distance ?? double.infinity) <= _captureRadiusMeters &&
        controlPoint.capturedBy != fwState.myState.guildId;
    final canCapture =
        canReachCapture && (isCancelling || crew.count >= crew.required);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);

    final actions = <_QuickAction>[];
    if (canCapture) {
      actions.add(
        _QuickAction(
          label: isCancelling ? '점령 취소' : '점령 시작',
          icon: isCancelling ? Icons.pause_circle_outline : Icons.flag_outlined,
          color: const Color(0xFF0F766E),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() {
              return isCancelling
                  ? notifier.cancelCapture(controlPoint.id)
                  : notifier.startCapture(controlPoint.id);
            });
          },
        ),
      );
    }
    if (fwState.myState.isAlive &&
        !fwState.myState.inDuel &&
        fwState.myState.job == 'mage') {
      actions.add(
        _QuickAction(
          label: '봉쇄 마법',
          icon: Icons.block_flipped,
          color: const Color(0xFF7C3AED),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(
                () => notifier.useSkill(controlPointId: controlPoint.id));
          },
        ),
      );
    }

    final ownerGuild = controlPoint.capturedBy == null
        ? '미점령'
        : fwState.guilds[controlPoint.capturedBy!]?.displayName ??
            controlPoint.capturedBy!;

    await _showQuickActionSheet(
      title: controlPoint.displayName,
      subtitle: [
        '점령 길드 · $ownerGuild',
        if (distance != null && distance.isFinite) '${distance.round()}m',
      ].join(' · '),
      accentColor: controlPoint.isBlockaded
          ? Colors.redAccent
          : _cpFillColor(controlPoint),
      lines: [
        '점령 인원 ${crew.count}/${crew.required}',
        if (canReachCapture && !isCancelling && crew.count < crew.required)
          '같은 길드원이 ${crew.required}명 이상 거점 안에 있어야 합니다.',
        if (controlPoint.isBlockaded) '현재 봉쇄 중입니다.',
        if (controlPoint.requiredCount > 0)
          '점령 준비 ${controlPoint.readyCount}/${controlPoint.requiredCount}',
        if (controlPoint.capturingGuild != null &&
            controlPoint.requiredCount == 0)
          '점령 진행 중인 거점입니다.',
      ],
      actions: actions,
    );
  }

  Future<void> _handleMemberTapped({
    required String userId,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) async {
    _setSelection(memberId: userId, controlPointId: null);

    final member = mapState.members[userId];
    final guildId = _guildIdForUser(fwState.guilds, userId);
    final guildLabel = guildId == null
        ? '길드 정보 없음'
        : fwState.guilds[guildId]?.displayName ?? guildId;
    final distance = _distanceToMember(userId, mapState, myId);
    final isEnemy = guildId != null && guildId != fwState.myState.guildId;
    final isSelf = userId == myId;
    final isAlly =
        !isSelf && guildId != null && guildId == fwState.myState.guildId;
    final canAct = fwState.myState.isAlive && !fwState.myState.inDuel;
    final duelProximity = _duelProximityForUser(userId, mapState, myId);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);

    final actions = <_QuickAction>[];
    if (canAct &&
        isEnemy &&
        fwState.duel.phase == 'idle' &&
        duelProximity != null) {
      actions.add(
        _QuickAction(
          label: '대결 요청',
          icon: Icons.sports_martial_arts_rounded,
          color: const Color(0xFF991B1B),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.challengeDuel(
                  userId,
                  proximity: duelProximity.toMap(),
                ));
          },
        ),
      );
    }
    if (canAct && fwState.myState.job == 'ranger' && isEnemy) {
      actions.add(
        _QuickAction(
          label: '추적 사용',
          icon: Icons.gps_fixed_rounded,
          color: const Color(0xFF0F766E),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(targetUserId: userId));
          },
        ),
      );
    }
    if (canAct && fwState.myState.job == 'priest' && (isAlly || isSelf)) {
      actions.add(
        _QuickAction(
          label: '보호막 부여',
          icon: Icons.shield_outlined,
          color: const Color(0xFF4338CA),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() => notifier.useSkill(targetUserId: userId));
          },
        ),
      );
    }

    await _showQuickActionSheet(
      title: member?.nickname ?? userId,
      subtitle: [
        guildLabel,
        if (distance != null && distance.isFinite) '${distance.round()}m',
        if (isSelf) '나',
      ].join(' · '),
      accentColor: isEnemy
          ? Colors.redAccent
          : isSelf
              ? Colors.white
              : guildColor(guildId),
      lines: [
        if (member != null) '상태 · ${member.status}',
        if (fwState.eliminatedPlayerIds.contains(userId)) '전투 불가 · 탈락 상태',
        if (isEnemy && !canAct) '현재 상태에서는 상호작용할 수 없습니다.',
      ],
      actions: actions,
    );
  }

  Future<void> _handleControlPointTapped({
    required String controlPointId,
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String? myId,
  }) async {
    final controlPoint = _controlPointById(fwState, controlPointId);
    if (controlPoint == null) {
      return;
    }

    _setSelection(memberId: null, controlPointId: controlPointId);

    final distance = _distanceToControlPoint(controlPoint, mapState, myId);
    final crew = _captureCrewStatus(controlPoint, fwState, mapState, myId);
    final isCancelling = fwState.myState.captureZone == controlPoint.id &&
        controlPoint.capturingGuild == fwState.myState.guildId;
    final canReachCapture = fwState.myState.isAlive &&
        !fwState.myState.inDuel &&
        (distance ?? double.infinity) <= _captureRadiusMeters &&
        controlPoint.capturedBy != fwState.myState.guildId;
    final canCapture =
        canReachCapture && (isCancelling || crew.count >= crew.required);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);

    final actions = <_QuickAction>[];
    if (canCapture) {
      actions.add(
        _QuickAction(
          label: isCancelling ? '점령 취소' : '점령 시작',
          icon: isCancelling ? Icons.pause_circle_outline : Icons.flag_outlined,
          color: const Color(0xFF0F766E),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(() {
              return isCancelling
                  ? notifier.cancelCapture(controlPoint.id)
                  : notifier.startCapture(controlPoint.id);
            });
          },
        ),
      );
    }
    if (fwState.myState.isAlive &&
        !fwState.myState.inDuel &&
        fwState.myState.job == 'mage') {
      actions.add(
        _QuickAction(
          label: '봉쇄 마법',
          icon: Icons.block_flipped,
          color: const Color(0xFF7C3AED),
          onTap: () async {
            Navigator.of(context).pop();
            await _runAck(
                () => notifier.useSkill(controlPointId: controlPoint.id));
          },
        ),
      );
    }

    final ownerGuild = controlPoint.capturedBy == null
        ? '미점령'
        : fwState.guilds[controlPoint.capturedBy!]?.displayName ??
            controlPoint.capturedBy!;

    await _showQuickActionSheet(
      title: controlPoint.displayName,
      subtitle: [
        '점령 길드 · $ownerGuild',
        if (distance != null && distance.isFinite) '${distance.round()}m',
      ].join(' · '),
      accentColor: controlPoint.isBlockaded
          ? Colors.redAccent
          : _cpFillColor(controlPoint),
      lines: [
        '점령 인원 ${crew.count}/${crew.required}',
        if (canReachCapture && !isCancelling && crew.count < crew.required)
          '같은 길드원이 ${crew.required}명 이상 거점 안에 있어야 합니다.',
        if (controlPoint.isBlockaded) '현재 봉쇄 중입니다.',
        if (controlPoint.requiredCount > 0)
          '점령 준비 ${controlPoint.readyCount}/${controlPoint.requiredCount}',
        if (controlPoint.capturingGuild != null &&
            controlPoint.requiredCount == 0)
          '점령 진행 중인 거점입니다.',
      ],
      actions: actions,
    );
  }

  Future<void> _showQuickActionSheet({
    required String title,
    required String subtitle,
    required Color accentColor,
    required List<String> lines,
    required List<_QuickAction> actions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF111827),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final line in lines) ...[
                    Text(
                      line,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final action in actions)
                        FilledButton.tonalIcon(
                          onPressed: () => unawaited(action.onTap()),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                action.color.withValues(alpha: 0.18),
                            foregroundColor: action.color,
                          ),
                          icon: Icon(action.icon, size: 18),
                          label: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runAck(Future<Map<String, dynamic>> Function() action) async {
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      if (result['ok'] != true) {
        _showError(_resolveErrorLabelClean(result['error'] as String?));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  Future<void> _handleCaptureActionClean(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final nearest = _controlPointById(fwState, _selectedControlPointId) ??
        _nearestControlPoint(fwState, mapState, myId);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    if (nearest == null) {
      _showError('근처 거점을 찾지 못했습니다.');
      return;
    }

    // 적 길드가 점령 진행 중이면 같은 버튼이 disrupt(방해) 로 동작.
    final isDisrupting = nearest.capturingGuild != null &&
        nearest.capturingGuild != fwState.myState.guildId;
    if (isDisrupting) {
      await _runAck(() => notifier.disruptCapture(nearest.id));
      return;
    }

    final isCancelling = fwState.myState.captureZone == nearest.id &&
        nearest.capturingGuild == fwState.myState.guildId;
    final crew = _captureCrewStatus(nearest, fwState, mapState, myId);
    if (!isCancelling && crew.count < crew.required) {
      _showError('같은 길드원이 ${crew.required}명 이상 거점 안에 있어야 합니다.');
      return;
    }

    await _runAck(() {
      return isCancelling
          ? notifier.cancelCapture(nearest.id)
          : notifier.startCapture(nearest.id);
    });
  }

  Future<void> _handleSkillActionClean(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    final job = fwState.myState.job;

    String? targetUserId;
    String? controlPointId;

    switch (job) {
      case 'priest':
        targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: false,
          includeSelf: true,
        );
        targetUserId ??= await _pickMemberTargetClean(
          title: '보호막을 줄 아군 선택',
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          enemy: false,
          includeSelf: true,
        );
        if (targetUserId == null) {
          return;
        }
        break;
      case 'mage':
        controlPointId = _selectedControlPointId;
        controlPointId ??= await _pickControlPointTargetClean(
          title: '봉쇄할 거점 선택',
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        );
        if (controlPointId == null) {
          return;
        }
        break;
      case 'ranger':
        targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: true,
        );
        targetUserId ??= await _pickMemberTargetClean(
          title: '추적할 적 선택',
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          enemy: true,
        );
        if (targetUserId == null) {
          return;
        }
        break;
      case 'rogue':
        break;
      default:
        _showError('사용 가능한 스킬이 없습니다.');
        return;
    }

    await _runAck(() {
      return notifier.useSkill(
        targetUserId: targetUserId,
        controlPointId: controlPointId,
      );
    });
  }

  Future<void> _handleDuelActionClean(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final selectedTargetUserId = _preferredSelectedMember(
      fwState: fwState,
      myId: myId,
      enemy: true,
    );
    final nearbyTargetIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
      nearbyOnly: true,
    );
    final selectedTargetProximity = selectedTargetUserId == null
        ? null
        : _duelProximityForUser(selectedTargetUserId, mapState, myId);
    final missingNearbyTarget =
        selectedTargetProximity == null && nearbyTargetIds.isEmpty;
    if (missingNearbyTarget) {
      _showError(_bleRequirementMessageClean(mapState));
      return;
    }

    final targetUserId = selectedTargetProximity != null
        ? selectedTargetUserId
        : await _pickMemberTargetClean(
            title: '대결할 적 선택',
            mapState: mapState,
            fwState: fwState,
            myId: myId,
            enemy: true,
            nearbyOnly: true,
          );
    if (targetUserId == null) {
      return;
    }

    final proximity = _duelProximityForUser(targetUserId, mapState, myId);
    if (proximity == null) {
      _showError(_bleRequirementMessageClean(mapState));
      return;
    }

    await _runAck(() {
      return ref
          .read(fantasyWarsProvider(widget.sessionId).notifier)
          .challengeDuel(
            targetUserId,
            proximity: proximity.toMap(),
          );
    });
  }

  Future<void> _handleCaptureAction(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final nearest = _controlPointById(fwState, _selectedControlPointId) ??
        _nearestControlPoint(fwState, mapState, myId);
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    if (nearest == null) {
      _showError('근처 거점을 찾지 못했습니다.');
      return;
    }

    final isCancelling = fwState.myState.captureZone == nearest.id &&
        nearest.capturingGuild == fwState.myState.guildId;
    final crew = _captureCrewStatus(nearest, fwState, mapState, myId);
    if (!isCancelling && crew.count < crew.required) {
      _showError('같은 길드원이 ${crew.required}명 이상 거점 안에 있어야 합니다.');
      return;
    }

    await _runAck(() {
      return isCancelling
          ? notifier.cancelCapture(nearest.id)
          : notifier.startCapture(nearest.id);
    });
  }

  Future<void> _handleSkillAction(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final notifier = ref.read(fantasyWarsProvider(widget.sessionId).notifier);
    final job = fwState.myState.job;

    String? targetUserId;
    String? controlPointId;

    switch (job) {
      case 'priest':
        targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: false,
          includeSelf: true,
        );
        if (targetUserId != null) {
          break;
        }
        targetUserId = await _pickMemberTarget(
          title: '보호막을 줄 아군 선택',
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          enemy: false,
          includeSelf: true,
        );
        if (targetUserId == null) {
          return;
        }
        break;
      case 'mage':
        controlPointId = _selectedControlPointId;
        if (controlPointId != null) {
          break;
        }
        controlPointId = await _pickControlPointTarget(
          title: '봉쇄할 거점 선택',
          fwState: fwState,
          mapState: mapState,
          myId: myId,
        );
        if (controlPointId == null) {
          return;
        }
        break;
      case 'ranger':
        targetUserId = _preferredSelectedMember(
          fwState: fwState,
          myId: myId,
          enemy: true,
        );
        if (targetUserId != null) {
          break;
        }
        targetUserId = await _pickMemberTarget(
          title: '추적할 적 선택',
          mapState: mapState,
          fwState: fwState,
          myId: myId,
          enemy: true,
        );
        if (targetUserId == null) {
          return;
        }
        break;
      case 'rogue':
        break;
      default:
        _showError('사용 가능한 스킬이 없습니다.');
        return;
    }

    await _runAck(() {
      return notifier.useSkill(
        targetUserId: targetUserId,
        controlPointId: controlPointId,
      );
    });
  }

  Future<void> _handleDuelAction(
    FantasyWarsGameState fwState,
    MapSessionState mapState,
    String? myId,
  ) async {
    final selectedTargetUserId = _preferredSelectedMember(
      fwState: fwState,
      myId: myId,
      enemy: true,
    );
    final nearbyTargetIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
      nearbyOnly: true,
    );
    final selectedTargetProximity = selectedTargetUserId == null
        ? null
        : _duelProximityForUser(selectedTargetUserId, mapState, myId);
    final missingNearbyTarget =
        selectedTargetProximity == null && nearbyTargetIds.isEmpty;
    if (missingNearbyTarget) {
      _showError(_bleRequirementMessage(mapState));
      return;
    }
    if (selectedTargetProximity == null && nearbyTargetIds.isEmpty) {
      _showError('가까운 적이 있어야 결투를 신청할 수 있습니다.');
      return;
    }
    final targetUserId = selectedTargetProximity != null
        ? selectedTargetUserId
        : await _pickMemberTarget(
            title: '대결할 적 선택',
            mapState: mapState,
            fwState: fwState,
            myId: myId,
            enemy: true,
            nearbyOnly: true,
          );
    if (targetUserId == null) {
      return;
    }

    final proximity = _duelProximityForUser(targetUserId, mapState, myId);
    final missingProximity = proximity == null;
    if (missingProximity) {
      _showError(_bleRequirementMessage(mapState));
      return;
    }
    // ignore: unnecessary_null_comparison
    if (proximity == null) {
      _showError('근거리 감지가 확인된 대상만 결투할 수 있습니다.');
      return;
    }

    await _runAck(() {
      return ref
          .read(fantasyWarsProvider(widget.sessionId).notifier)
          .challengeDuel(
            targetUserId,
            proximity: proximity.toMap(),
          );
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  // 비활성 액션 버튼 탭 시 가능 조건만 알려주는 짧은 toast.
  void _showInfoToast(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xCC1F2937), // gray-800
          duration: const Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ),
      );
  }

  String _captureDisabledReason({
    required FantasyWarsGameState fwState,
    required FwControlPoint? nearestControlPoint,
    required double? nearestControlPointDistance,
    required ({int count, int required})? captureCrew,
    required bool isOutsideBattlefield,
  }) {
    if (!fwState.myState.isAlive) return '사망 상태에서는 점령할 수 없습니다.';
    if (fwState.myState.inDuel) return '결투 중에는 점령할 수 없습니다.';
    if (isOutsideBattlefield) return '전장 영역 안으로 이동해 주세요.';
    if (nearestControlPoint == null) return '근처에 거점이 없습니다.';
    if (nearestControlPoint.capturedBy == fwState.myState.guildId) {
      return '이미 우리 길드의 거점입니다.';
    }
    final dist = nearestControlPointDistance;
    if (dist == null || dist > _captureRadiusMeters) {
      return '거점에 더 가까이 이동해 주세요. (40m 이내)';
    }
    if (captureCrew != null && captureCrew.count < captureCrew.required) {
      return '같은 길드원이 ${captureCrew.required}명 이상 거점 안에 있어야 합니다.';
    }
    return '점령 조건이 충족되지 않았습니다.';
  }

  String _duelDisabledReason({
    required FantasyWarsGameState fwState,
    required List<String> duelCandidateIds,
  }) {
    if (!fwState.myState.isAlive) return '사망 상태에서는 결투를 신청할 수 없습니다.';
    if (fwState.myState.inDuel) return '이미 결투 중입니다.';
    if (fwState.myState.captureZone != null) {
      return '점령 진행 중에는 결투할 수 없습니다.';
    }
    if (fwState.duel.phase != 'idle') return '결투가 이미 진행 중입니다.';
    if (duelCandidateIds.isEmpty) return '근처에 적이 없습니다.';
    return '결투 조건이 충족되지 않았습니다.';
  }

  String _dungeonDisabledReason(FantasyWarsGameState fwState) {
    if (fwState.myState.isAlive) return '사망 후에만 던전에 입장할 수 있습니다.';
    if (fwState.myState.dungeonEntered) return '이미 던전에 입장했습니다.';
    return '던전 입장 조건이 충족되지 않았습니다.';
  }

  String _bleRequirementMessageClean(MapSessionState mapState) {
    final strictBleRequired = !ref
        .read(fantasyWarsProvider(widget.sessionId))
        .allowGpsFallbackWithoutBle;
    if (!strictBleRequired) {
      return '근거리 판정이 확인되지 않았습니다. 상대에게 더 가까이 이동해 주세요.';
    }

    switch (mapState.blePresenceStatus) {
      case 'permissionDenied':
        return '근접 결투를 하려면 Bluetooth와 위치 권한을 허용해 주세요.';
      case 'requestingPermission':
        return 'Bluetooth 권한을 확인하는 중입니다. 잠시 후 다시 시도해 주세요.';
      case 'bluetoothUnavailable':
        return mapState.blePresenceMessage == null ||
                mapState.blePresenceMessage!.isEmpty
            ? 'Bluetooth 또는 위치 서비스 상태를 확인한 뒤 다시 시도해 주세요.'
            : '${mapState.blePresenceMessage} 다시 시도해 주세요.';
      case 'starting':
        return 'BLE 근접 탐색을 준비 중입니다. 잠시 후 다시 시도해 주세요.';
      case 'running':
        return mapState.bleContacts.isEmpty
            ? '아직 근거리 감지가 없습니다. 상대에게 더 가까이 이동해 주세요.'
            : '근거리 감지가 갱신되지 않았습니다. 상대에게 다시 가까이 이동해 주세요.';
      case 'error':
        return mapState.blePresenceMessage == null ||
                mapState.blePresenceMessage!.isEmpty
            ? 'BLE 근접 탐색을 시작하지 못했습니다. Bluetooth 상태를 확인해 주세요.'
            : '${mapState.blePresenceMessage} 다시 시도해 주세요.';
      case 'unsupported':
        return '이 기기에서는 BLE 근접 결투를 지원하지 않습니다.';
      default:
        return '근거리 판정이 확인되지 않았습니다. 상대에게 더 가까이 이동해 주세요.';
    }
  }

  String? _bleSummaryClean(MapSessionState mapState, int nearbyEnemyCount) {
    if (mapState.gameState.status != 'in_progress') {
      return null;
    }

    switch (mapState.blePresenceStatus) {
      case 'running':
        if (nearbyEnemyCount > 0) {
          return 'BLE · 적 $nearbyEnemyCount명 감지';
        }
        final freshContacts = _freshBleContactCount(mapState);
        return freshContacts > 0 ? 'BLE · $freshContacts명 감지' : 'BLE 탐색 중';
      case 'starting':
        return 'BLE 준비 중';
      case 'requestingPermission':
        return 'BLE 권한 확인 중';
      case 'permissionDenied':
        return 'BLE · 권한 필요';
      case 'bluetoothUnavailable':
        return 'BLE · ${mapState.blePresenceMessage ?? '상태 확인 필요'}';
      case 'error':
        return 'BLE · ${mapState.blePresenceMessage ?? '초기화 실패'}';
      case 'unsupported':
        return 'BLE 미지원';
      default:
        return 'BLE 대기 중';
    }
  }

  List<String> _duelDebugLinesClean(FantasyWarsGameState fwState) {
    final debug = fwState.duelDebug;
    if (!_shouldShowDuelDebug(debug)) {
      return const [];
    }

    final info = debug!;
    final lines = <String>[
      switch (info.stage) {
        'challenge' => info.ok ? '마지막 대결 요청 성공' : '마지막 대결 요청 실패',
        'accept' => info.ok ? '마지막 대결 수락 성공' : '마지막 대결 수락 실패',
        'invalidated' => '대결이 무효 처리됨',
        _ => info.ok ? '대결 조건 확인 성공' : '대결 조건 확인 실패',
      },
    ];

    if (info.stage == 'invalidated') {
      lines.add(_duelInvalidationLabelClean(info.code));
    } else if (info.code != null) {
      lines.add(_resolveErrorLabelClean(info.code));
    }

    if (info.distanceMeters != null || info.duelRangeMeters != null) {
      lines.add(
        '거리 ${info.distanceMeters ?? '?'}m / 허용 ${info.duelRangeMeters ?? fwState.duelRangeMeters}m',
      );
    }

    final proximityLine = _duelDebugProximityLineClean(info);
    if (proximityLine != null) {
      lines.add(proximityLine);
    }

    final evidenceLine = _duelDebugEvidenceLineClean(info);
    if (evidenceLine != null) {
      lines.add(evidenceLine);
    }

    return lines.take(4).toList(growable: false);
  }

  String? _duelDebugProximityLineClean(FwDuelDebugInfo info) {
    if (info.bleConfirmed == true) {
      return info.mutualProximity == true
          ? '근접 판정 BLE 확인 · 상호 감지'
          : '근접 판정 BLE 확인';
    }
    if (info.gpsFallbackUsed == true) {
      return info.allowGpsFallbackWithoutBle == true
          ? '근접 판정 GPS fallback 허용'
          : '근접 판정 GPS fallback 차단';
    }
    if (info.proximitySource != null) {
      return '근접 판정 ${info.proximitySource}';
    }
    return null;
  }

  String? _duelDebugEvidenceLineClean(FwDuelDebugInfo info) {
    if (info.recentProximityReports == null &&
        info.freshestEvidenceAgeMs == null) {
      return null;
    }

    final reportCount = info.recentProximityReports ?? 0;
    final freshnessWindowSec =
        ((info.bleEvidenceFreshnessMs ?? 0) / 1000).round();
    if (info.freshestEvidenceAgeMs == null) {
      return '최근 근접 보고 $reportCount건';
    }

    final seenAgoSec = (info.freshestEvidenceAgeMs! / 1000).toStringAsFixed(1);
    if (freshnessWindowSec > 0) {
      return '최근 근접 보고 $reportCount건 · ${seenAgoSec}초 전 / 기준 ${freshnessWindowSec}초';
    }
    return '최근 근접 보고 $reportCount건 · ${seenAgoSec}초 전';
  }

  String _duelInvalidationLabelClean(String? reason) => switch (reason) {
        'challenge_timeout' => '상대가 제한 시간 안에 수락하지 않았습니다.',
        'disconnect' => '참가자 연결이 끊겨 대결이 취소되었습니다.',
        'BLE_PROXIMITY_REQUIRED' => '수락 시점에 BLE 근접 확인이 필요했습니다.',
        'TARGET_OUT_OF_RANGE' => '수락 시점에 대결 가능 거리 밖으로 벗어났습니다.',
        'LOCATION_STALE' => '수락 시점 위치 정보가 오래되어 대결이 취소되었습니다.',
        'LOCATION_UNAVAILABLE' => '수락 시점 위치 정보를 확인하지 못했습니다.',
        _ => reason ?? '대결 조건이 유지되지 않았습니다.',
      };

  String _resolveErrorLabelClean(String? code) {
    if (code == 'BLE_PROXIMITY_REQUIRED') {
      final mapState = ref.read(mapSessionProvider(widget.sessionId));
      return _bleRequirementMessageClean(mapState);
    }
    return switch (code) {
      'LOCATION_UNAVAILABLE' => '위치 정보를 아직 받지 못했습니다.',
      'LOCATION_STALE' => '위치 정보가 오래되었습니다.',
      'NOT_IN_CAPTURE_ZONE' => '거점 반경 안에서만 점령을 시작할 수 있습니다.',
      'NOT_ENOUGH_TEAMMATES_IN_ZONE' => '같은 길드원이 2명 이상 필요합니다.',
      'ENEMY_IN_ZONE' => '적이 거점 안에 있어 점령을 시작할 수 없습니다.',
      'BLOCKADED' => '현재 봉쇄된 거점입니다.',
      'TARGET_IN_DUEL' => '대결 중인 대상에게는 사용할 수 없습니다.',
      'PLAYER_CAPTURING' => '점령 진행 중에는 대결을 신청할 수 없습니다. 먼저 점령을 취소해 주세요.',
      'TARGET_CAPTURING' => '상대가 점령 중이라 대결을 신청할 수 없습니다.',
      'TARGET_NOT_ENEMY' => '적 대상이 필요합니다.',
      'TARGET_NOT_ALLY' => '아군 대상이 필요합니다.',
      'REVIVE_DISABLED_USE_DUNGEON' => '부활 시도는 던전에서만 가능합니다.',
      'DUNGEON_CLOSED' => '던전이 닫혀 있습니다.',
      'ALREADY_IN_DUNGEON' => '이미 던전에서 부활을 대기 중입니다.',
      'PLAYER_NOT_FOUND' => '플레이어 상태를 찾지 못했습니다.',
      'PLAYER_DEAD' => '탈락 상태에서는 해당 행동을 할 수 없습니다.',
      'ATTACK_DISABLED_USE_DUEL' => '직접 공격 대신 대결을 사용해 주세요.',
      'CP_NOT_FOUND' => '거점 정보를 찾지 못했습니다.',
      'ACTION_REJECTED' => '요청이 거절되었습니다.',
      _ => code ?? '처리에 실패했습니다.',
    };
  }

  String _bleRequirementMessage(MapSessionState mapState) {
    final strictBleRequired = !ref
        .read(fantasyWarsProvider(widget.sessionId))
        .allowGpsFallbackWithoutBle;
    if (!strictBleRequired) {
      return '근거리 판정을 확인하지 못했습니다. 상대와 더 가까워져 주세요.';
    }

    switch (mapState.blePresenceStatus) {
      case 'permissionDenied':
        return '근접 결투를 하려면 Bluetooth와 위치 권한을 허용해 주세요.';
      case 'requestingPermission':
        return 'Bluetooth 권한을 확인하는 중입니다. 잠시 후 다시 시도해 주세요.';
      case 'bluetoothUnavailable':
        return mapState.blePresenceMessage == null ||
                mapState.blePresenceMessage!.isEmpty
            ? 'Bluetooth 또는 위치 서비스 상태를 확인한 뒤 다시 시도해 주세요.'
            : '${mapState.blePresenceMessage} 다시 시도해 주세요.';
      case 'starting':
        return 'BLE 근접 탐색을 준비 중입니다. 잠시 후 다시 시도해 주세요.';
      case 'running':
        return mapState.bleContacts.isEmpty
            ? '아직 근거리 감지가 없습니다. 상대와 더 가까워져 주세요.'
            : '근거리 감지가 갱신되지 않았습니다. 상대와 다시 가까워져 주세요.';
      case 'error':
        return mapState.blePresenceMessage == null ||
                mapState.blePresenceMessage!.isEmpty
            ? 'BLE 근접 탐색을 시작하지 못했습니다. Bluetooth 상태를 확인해 주세요.'
            : '${mapState.blePresenceMessage} 다시 시도해 주세요.';
      case 'unsupported':
        return '이 기기에서는 BLE 근접 결투를 지원하지 않습니다.';
      default:
        return '근거리 감지가 확인되지 않았습니다. 상대와 더 가까워져 주세요.';
    }
  }

  int _freshBleContactCount(MapSessionState mapState) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final bleFreshnessWindowMs =
        ref.read(fantasyWarsProvider(widget.sessionId)).bleEvidenceFreshnessMs;
    return mapState.bleContacts.values
        .where(
          (contact) => nowMs - contact.seenAtMs <= bleFreshnessWindowMs,
        )
        .length;
  }

  String? _bleSummary(MapSessionState mapState, int nearbyEnemyCount) {
    if (mapState.gameState.status != 'in_progress') {
      return null;
    }

    switch (mapState.blePresenceStatus) {
      case 'running':
        if (nearbyEnemyCount > 0) {
          return 'BLE 근처 적 $nearbyEnemyCount명 감지';
        }
        final freshContacts = _freshBleContactCount(mapState);
        return freshContacts > 0 ? 'BLE 근접 $freshContacts명 감지' : 'BLE 탐색 중';
      case 'starting':
        return 'BLE 준비 중';
      case 'requestingPermission':
        return 'BLE 권한 확인 중';
      case 'permissionDenied':
        return 'BLE 권한 필요';
      case 'bluetoothUnavailable':
        return 'BLE ${mapState.blePresenceMessage ?? '상태 확인 필요'}';
      case 'error':
        return 'BLE ${mapState.blePresenceMessage ?? '초기화 실패'}';
      case 'unsupported':
        return 'BLE 미지원';
      default:
        return 'BLE 대기 중';
    }
  }

  bool _shouldShowDuelDebug(FwDuelDebugInfo? info) {
    if (info == null) {
      return false;
    }
    final ageMs = DateTime.now().millisecondsSinceEpoch - info.recordedAt;
    return ageMs <= 15000;
  }

  List<String> _duelDebugLines(FantasyWarsGameState fwState) {
    final debug = fwState.duelDebug;
    if (!_shouldShowDuelDebug(debug)) {
      return const [];
    }

    final info = debug!;
    final lines = <String>[
      switch (info.stage) {
        'challenge' => info.ok ? '마지막 대결 요청 성공' : '마지막 대결 요청 실패',
        'accept' => info.ok ? '마지막 대결 수락 성공' : '마지막 대결 수락 실패',
        'invalidated' => '대결 무효 처리',
        _ => info.ok ? '최근 결투 판정 성공' : '최근 결투 판정 실패',
      },
    ];

    if (info.stage == 'invalidated') {
      lines.add(_duelInvalidationLabel(info.code));
    } else if (info.code != null) {
      lines.add(_resolveErrorLabelClean(info.code));
    }

    if (info.distanceMeters != null || info.duelRangeMeters != null) {
      lines.add(
        '거리 ${info.distanceMeters ?? '?'}m / 허용 ${info.duelRangeMeters ?? fwState.duelRangeMeters}m',
      );
    }

    final proximityLine = _duelDebugProximityLine(info);
    if (proximityLine != null) {
      lines.add(proximityLine);
    }

    final evidenceLine = _duelDebugEvidenceLine(info);
    if (evidenceLine != null) {
      lines.add(evidenceLine);
    }

    return lines.take(4).toList(growable: false);
  }

  String? _duelDebugProximityLine(FwDuelDebugInfo info) {
    if (info.bleConfirmed == true) {
      return info.mutualProximity == true
          ? '근접 판정 BLE 확인 · 상호 감지'
          : '근접 판정 BLE 확인';
    }
    if (info.gpsFallbackUsed == true) {
      return info.allowGpsFallbackWithoutBle == true
          ? '근접 판정 GPS fallback 허용'
          : '근접 판정 GPS fallback 차단';
    }
    if (info.proximitySource != null) {
      return '근접 판정 ${info.proximitySource}';
    }
    return null;
  }

  String? _duelDebugEvidenceLine(FwDuelDebugInfo info) {
    if (info.recentProximityReports == null &&
        info.freshestEvidenceAgeMs == null) {
      return null;
    }

    final reportCount = info.recentProximityReports ?? 0;
    final freshnessWindowSec =
        ((info.bleEvidenceFreshnessMs ?? 0) / 1000).round();
    if (info.freshestEvidenceAgeMs == null) {
      return '최근 근접 보고 $reportCount건';
    }

    final seenAgoSec = (info.freshestEvidenceAgeMs! / 1000).toStringAsFixed(1);
    if (freshnessWindowSec > 0) {
      return '최근 근접 보고 $reportCount건 · ${seenAgoSec}초 전 / 기준 ${freshnessWindowSec}초';
    }
    return '최근 근접 보고 $reportCount건 · ${seenAgoSec}초 전';
  }

  String _duelInvalidationLabel(String? reason) => switch (reason) {
        'challenge_timeout' => '상대가 제한 시간 안에 수락하지 않았습니다.',
        'disconnect' => '참가자 연결이 끊겨 대결이 취소되었습니다.',
        'BLE_PROXIMITY_REQUIRED' => '수락 시점에 BLE 근접 확인이 필요했습니다.',
        'TARGET_OUT_OF_RANGE' => '수락 시점에 대상이 가능 거리 밖으로 벗어났습니다.',
        'LOCATION_STALE' => '수락 시점 위치 정보가 오래되어 대결이 취소되었습니다.',
        'LOCATION_UNAVAILABLE' => '수락 시점 위치 정보를 확인할 수 없었습니다.',
        _ => reason ?? '대결 조건을 유지하지 못했습니다.',
      };

  Future<void> _openHostDebugSheet({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required Map<String, String> memberLabels,
    required List<String> duelCandidateIds,
    required String? myId,
  }) {
    if (!mounted) {
      return Future.value();
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final systemLines = _hostDebugSystemLines(
      fwState: fwState,
      mapState: mapState,
      nearbyEnemyCount: duelCandidateIds.length,
    );
    final duelLines = _duelDebugLinesClean(fwState);
    final bleLines = _hostDebugBleContactLines(
      fwState: fwState,
      mapState: mapState,
      memberLabels: memberLabels,
      myId: myId,
      nowMs: nowMs,
    );
    final candidateLines = _hostDebugCandidateLines(
      fwState: fwState,
      mapState: mapState,
      memberLabels: memberLabels,
      myId: myId,
      nowMs: nowMs,
    );

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0F766E).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Color(0xFF5EEAD4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '호스트 로그',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '실시간 전장 디버그 정보',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        HostDebugSection(
                          title: '시스템',
                          lines: systemLines,
                        ),
                        const SizedBox(height: 12),
                        HostEventSection(
                          title: '최근 이벤트',
                          events: fwState.recentEvents,
                          onEventTap: (event) {
                            Navigator.of(context).pop();
                            unawaited(() async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              if (!mounted) {
                                return;
                              }
                              await _focusRecentEvent(
                                event,
                                fwState: ref.read(
                                    fantasyWarsProvider(widget.sessionId)),
                                mapState: ref
                                    .read(mapSessionProvider(widget.sessionId)),
                              );
                            }());
                          },
                          onEventInspectTap: (event) {
                            Navigator.of(context).pop();
                            unawaited(() async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              if (!mounted) {
                                return;
                              }
                              await _openRecentEventDetails(event);
                            }());
                          },
                        ),
                        const SizedBox(height: 12),
                        HostDebugSection(
                          title: '최근 결투 판정',
                          lines: duelLines.isEmpty
                              ? const ['최근 결투 디버그 없음']
                              : duelLines,
                        ),
                        const SizedBox(height: 12),
                        HostDebugSection(
                          title: 'BLE 접촉',
                          lines: bleLines,
                        ),
                        const SizedBox(height: 12),
                        HostDebugSection(
                          title: '적 후보',
                          lines: candidateLines,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _hostSystemLines({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required int nearbyEnemyCount,
  }) {
    final freshnessSeconds = (fwState.bleEvidenceFreshnessMs / 1000).round();
    final freshContactCount = _freshBleContactCount(mapState);
    return [
      'Session · ${mapState.gameState.status}',
      'Socket · ${mapState.isConnected ? 'connected' : 'disconnected'}',
      'BLE · ${_hostBleStatusLabel(mapState)}',
      'Duel Mode · ${fwState.allowGpsFallbackWithoutBle ? 'GPS fallback allowed' : 'BLE required'}',
      'Duel Range · ${fwState.duelRangeMeters}m / BLE window ${freshnessSeconds}s',
      'Nearby Summary · enemies $nearbyEnemyCount / fresh contacts $freshContactCount',
    ];
  }

  List<String> _hostBleContactLines({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required Map<String, String> memberLabels,
    required String? myId,
    required int nowMs,
  }) {
    final contacts = mapState.bleContacts.values.toList()
      ..sort((a, b) => b.seenAtMs.compareTo(a.seenAtMs));
    if (contacts.isEmpty) {
      return const ['No recent BLE contacts'];
    }

    return contacts.take(6).map((contact) {
      final name = memberLabels[contact.userId] ??
          _memberLabelClean(mapState.members, contact.userId);
      final ageMs = nowMs - contact.seenAtMs;
      final freshnessLabel =
          ageMs <= fwState.bleEvidenceFreshnessMs ? 'fresh' : 'stale';
      final distance = _distanceToMember(contact.userId, mapState, myId);
      final distanceLabel = distance != null && distance.isFinite
          ? ' · ${distance.round()}m'
          : '';
      return '$name · ${contact.rssi} dBm · ${_formatAgeMs(ageMs)} ago$distanceLabel · $freshnessLabel';
    }).toList(growable: false);
  }

  List<String> _hostCandidateLines({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required Map<String, String> memberLabels,
    required String? myId,
    required int nowMs,
  }) {
    if (myId == null) {
      return const ['현재 사용자 정보를 가져올 수 없습니다'];
    }

    final enemyIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
      nearbyOnly: false,
    );
    if (enemyIds.isEmpty) {
      return const ['보이는 적 후보가 없습니다'];
    }

    return enemyIds.take(8).map((userId) {
      final name =
          memberLabels[userId] ?? _memberLabelClean(mapState.members, userId);
      final distance = _distanceToMember(userId, mapState, myId);
      final distanceLabel = distance != null && distance.isFinite
          ? '${distance.round()}m'
          : '알 수 없음';
      final proximity = _duelProximityForUser(userId, mapState, myId);
      final status = _hostCandidateStatus(
        fwState: fwState,
        mapState: mapState,
        userId: userId,
        distance: distance,
        proximity: proximity,
        nowMs: nowMs,
      );
      return '$name · $distanceLabel · $status';
    }).toList(growable: false);
  }

  String _hostCandidateStatus({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String userId,
    required double? distance,
    required FwDuelProximityContext? proximity,
    required int nowMs,
  }) {
    if (proximity?.source == 'ble') {
      return proximity?.rssi == null
          ? 'BLE ready'
          : 'BLE ready (${proximity!.rssi} dBm)';
    }
    if (proximity?.source == 'gps_fallback') {
      return 'GPS fallback ready';
    }

    final contact = mapState.bleContacts[userId];
    if (contact != null) {
      final ageMs = nowMs - contact.seenAtMs;
      if (ageMs > fwState.bleEvidenceFreshnessMs) {
        return 'BLE stale (${_formatAgeMs(ageMs)} ago)';
      }
    }
    if (distance != null && distance.isFinite) {
      if (distance <= fwState.duelRangeMeters) {
        return fwState.allowGpsFallbackWithoutBle
            ? 'GPS in range'
            : 'in range · no BLE';
      }
      return 'out of range';
    }
    return 'unavailable';
  }

  String _hostBleStatusLabel(MapSessionState mapState) {
    return switch (mapState.blePresenceStatus) {
      'running' => 'running',
      'starting' => 'starting',
      'requestingPermission' => 'requesting permission',
      'permissionDenied' => 'permission denied',
      'bluetoothUnavailable' => mapState.blePresenceMessage == null ||
              mapState.blePresenceMessage!.isEmpty
          ? 'bluetooth unavailable'
          : mapState.blePresenceMessage!,
      'error' => mapState.blePresenceMessage == null ||
              mapState.blePresenceMessage!.isEmpty
          ? 'error'
          : mapState.blePresenceMessage!,
      'unsupported' => 'unsupported',
      _ => 'idle',
    };
  }

  String _formatAgeMs(int ageMs) {
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

  List<String> _hostEventLines(FantasyWarsGameState fwState) {
    if (fwState.recentEvents.isEmpty) {
      return const ['No recent session events'];
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return fwState.recentEvents
        .take(10)
        .map(
          (event) =>
              '${_formatDebugAge(nowMs - event.recordedAt)} 전 | ${event.message}',
        )
        .toList(growable: false);
  }

  List<String> _hostDebugSystemLines({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required int nearbyEnemyCount,
  }) {
    final freshnessSeconds = (fwState.bleEvidenceFreshnessMs / 1000).round();
    final freshContactCount = _freshBleContactCount(mapState);
    return [
      '세션 | ${_sessionStatusKo(mapState.gameState.status)}',
      '소켓 | ${mapState.isConnected ? '연결됨' : '끊김'}',
      'BLE | ${_hostDebugBleStatusText(mapState)}',
      '결투 모드 | ${fwState.allowGpsFallbackWithoutBle ? 'GPS 폴백 허용' : 'BLE 필수'}',
      '결투 사거리 | ${fwState.duelRangeMeters}m / BLE 윈도우 ${freshnessSeconds}초',
      '근처 요약 | 적 $nearbyEnemyCount / 신선 접촉 $freshContactCount',
    ];
  }

  String _sessionStatusKo(String status) => switch (status) {
        'waiting' => '대기 중',
        'in_progress' => '진행 중',
        'finished' => '종료됨',
        'none' => '없음',
        _ => status,
      };

  List<String> _hostDebugBleContactLines({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required Map<String, String> memberLabels,
    required String? myId,
    required int nowMs,
  }) {
    final contacts = mapState.bleContacts.values.toList()
      ..sort((a, b) => b.seenAtMs.compareTo(a.seenAtMs));
    if (contacts.isEmpty) {
      return const ['최근 BLE 접촉 없음'];
    }

    return contacts.take(6).map((contact) {
      final name = memberLabels[contact.userId] ??
          _memberLabelClean(mapState.members, contact.userId);
      final ageMs = nowMs - contact.seenAtMs;
      final freshnessLabel =
          ageMs <= fwState.bleEvidenceFreshnessMs ? '신선' : '만료';
      final distance = _distanceToMember(contact.userId, mapState, myId);
      final distanceLabel = distance != null && distance.isFinite
          ? ' | ${distance.round()}m'
          : '';
      return '$name | ${contact.rssi} dBm | ${_formatDebugAge(ageMs)} 전$distanceLabel | $freshnessLabel';
    }).toList(growable: false);
  }

  List<String> _hostDebugCandidateLines({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required Map<String, String> memberLabels,
    required String? myId,
    required int nowMs,
  }) {
    if (myId == null) {
      return const ['현재 사용자 정보를 가져올 수 없습니다'];
    }

    final enemyIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
      nearbyOnly: false,
    );
    if (enemyIds.isEmpty) {
      return const ['보이는 적 후보가 없습니다'];
    }

    return enemyIds.take(8).map((userId) {
      final name =
          memberLabels[userId] ?? _memberLabelClean(mapState.members, userId);
      final distance = _distanceToMember(userId, mapState, myId);
      final distanceLabel = distance != null && distance.isFinite
          ? '${distance.round()}m'
          : '알 수 없음';
      final proximity = _duelProximityForUser(userId, mapState, myId);
      final status = _hostDebugCandidateStatus(
        fwState: fwState,
        mapState: mapState,
        userId: userId,
        distance: distance,
        proximity: proximity,
        nowMs: nowMs,
      );
      return '$name | $distanceLabel | $status';
    }).toList(growable: false);
  }

  String _hostDebugCandidateStatus({
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
    required String userId,
    required double? distance,
    required FwDuelProximityContext? proximity,
    required int nowMs,
  }) {
    if (proximity?.source == 'ble') {
      return proximity?.rssi == null
          ? 'BLE 준비됨'
          : 'BLE 준비됨 (${proximity!.rssi} dBm)';
    }
    if (proximity?.source == 'gps_fallback') {
      return 'GPS 폴백 준비됨';
    }

    final contact = mapState.bleContacts[userId];
    if (contact != null) {
      final ageMs = nowMs - contact.seenAtMs;
      if (ageMs > fwState.bleEvidenceFreshnessMs) {
        return 'BLE 만료 (${_formatDebugAge(ageMs)} 전)';
      }
    }
    if (distance != null && distance.isFinite) {
      if (distance <= fwState.duelRangeMeters) {
        return fwState.allowGpsFallbackWithoutBle
            ? 'GPS 사거리 안'
            : '사거리 안 | BLE 없음';
      }
      return '사거리 밖';
    }
    return '정보 없음';
  }

  String _hostDebugBleStatusText(MapSessionState mapState) {
    return switch (mapState.blePresenceStatus) {
      'running' => '동작 중',
      'starting' => '시작 중',
      'requestingPermission' => '권한 요청 중',
      'permissionDenied' => '권한 거부됨',
      'bluetoothUnavailable' => mapState.blePresenceMessage == null ||
              mapState.blePresenceMessage!.isEmpty
          ? 'Bluetooth 사용 불가'
          : mapState.blePresenceMessage!,
      'error' => mapState.blePresenceMessage == null ||
              mapState.blePresenceMessage!.isEmpty
          ? '오류'
          : mapState.blePresenceMessage!,
      'unsupported' => '미지원',
      _ => '대기',
    };
  }

  String _formatDebugAge(int ageMs) {
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

  String _resolveErrorLabel(String? code) {
    if (code == 'BLE_PROXIMITY_REQUIRED') {
      return _bleRequirementMessage(
          ref.read(mapSessionProvider(widget.sessionId)));
    }
    return _errorLabel(code);
  }

  String _errorLabel(String? code) => switch (code) {
        'TARGET_OUT_OF_RANGE' => '대결 가능한 거리 밖입니다.',
        'BLE_PROXIMITY_REQUIRED' => '근거리 감지가 확인되지 않았습니다. 상대와 더 가까워져 주세요.',
        'LOCATION_UNAVAILABLE' => '위치 정보를 아직 받지 못했습니다.',
        'LOCATION_STALE' => '위치 정보가 오래되었습니다.',
        'NOT_IN_CAPTURE_ZONE' => '거점 반경 안에서만 점령을 시작할 수 있습니다.',
        'NOT_ENOUGH_TEAMMATES_IN_ZONE' => '같은 길드원이 2명 이상 필요합니다.',
        'ENEMY_IN_ZONE' => '적이 거점 안에 있어 점령을 시작할 수 없습니다.',
        'BLOCKADED' => '현재 봉쇄된 거점입니다.',
        'TARGET_IN_DUEL' => '대결 중인 대상에게는 사용할 수 없습니다.',
        'CHALLENGER_CAPTURING' => '점령 진행 중에는 대결을 신청할 수 없습니다. 먼저 점령을 취소해 주세요.',
        'TARGET_CAPTURING' => '상대가 점령 중이라 대결을 신청할 수 없습니다.',
        'TARGET_NOT_ENEMY' => '적 대상이 필요합니다.',
        'TARGET_NOT_ALLY' => '아군 대상이 필요합니다.',
        'REVIVE_DISABLED_USE_DUNGEON' => '부활 시도는 던전에서만 가능합니다.',
        'DUNGEON_CLOSED' => '던전이 닫혀 있습니다.',
        'ALREADY_IN_DUNGEON' => '이미 던전에서 부활을 대기 중입니다.',
        'PLAYER_NOT_DEAD' => '던전 입장은 탈락 상태에서만 가능합니다.',
        'PLAYER_NOT_FOUND' => '플레이어 상태를 찾지 못했습니다.',
        'PLAYER_DEAD' => '탈락 상태에서는 해당 행동을 할 수 없습니다.',
        'ATTACK_DISABLED_USE_DUEL' => '직접 공격 대신 대결을 사용해 주세요.',
        'CP_NOT_FOUND' => '거점 정보를 찾지 못했습니다.',
        'ACTION_REJECTED' => '요청이 거절되었습니다.',
        _ => code ?? '처리에 실패했습니다.',
      };

  void _startNaverMapWidgetTimer() {
    _naverMapWidgetTimer?.cancel();
    // 30s: PlatformView attach + Naver SDK 인증 + 첫 타일 fetch 가 모두 끝나야
    // onMapReady 가 발화한다. 약한 셀룰러 / 캐시 miss 환경에서 15s 는 부족했고
    // false negative 후 reconnect 폭주로 jank 가 더 심해졌다.
    debugPrint('[FW-BOOT] NaverMap widget timer started (30s)');
    _naverMapWidgetTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _naverMapWidgetReady) return;
      debugPrint(
          '[FW-BOOT] NaverMap widget timer EXPIRED ??onMapReady not received');
      // 인증 실패가 아닌 경우 오버레이 없이 ready 처리한다.
      if (AppInitializationService().isNaverMapAuthFailed) {
        setState(() {
          _naverMapWidgetError = 'NaverMap 인증에 실패했습니다.\n'
              '클라이언트 ID(ir4goe1vir)가 이 기기/환경에서 유효한지 확인해 주세요.';
        });
      } else {
        debugPrint('[FW-BOOT] assuming map is visible ??clearing overlay');
        setState(() => _naverMapWidgetReady = true);
      }
    });
  }

  Widget _buildMapLoadingOverlayClean() {
    if (_naverMapWidgetError != null) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                Text(
                  _cleanMapWidgetError(_naverMapWidgetError!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _retryBootstrap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('다시 시도'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _confirmLeaveClean,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('나가기'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const ColoredBox(
      color: Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54, strokeWidth: 3),
            SizedBox(height: 14),
            Text(
              '전장 지도를 불러오는 중...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingViewClean(
    BuildContext context, {
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
  }) {
    final steps = _cleanBootstrapSteps(fwState, mapState);
    final waiting = _bootstrapError == null &&
        !_isCriticalBootstrapReady(fwState, mapState);
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF020617).withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 30,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: waiting
                              ? const Color(0xFF0EA5E9).withValues(alpha: 0.16)
                              : colorScheme.error.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: waiting
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child:
                                    CircularProgressIndicator(strokeWidth: 3),
                              )
                            : Icon(
                                Icons.error_outline_rounded,
                                color: colorScheme.error,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cleanBootstrapHeadline(fwState, mapState),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _cleanBootstrapDescription(fwState, mapState),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < steps.length; index++) ...[
                          FwBootstrapStepTile(step: steps[index]),
                          if (index != steps.length - 1)
                            const Divider(color: Colors.white12, height: 16),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '필수 단계가 끝나면 전장 화면을 표시합니다. 선택 단계는 게임 화면을 연 뒤에도 이어서 초기화됩니다.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _bootstrapping ? null : _retryBootstrap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('다시 시도'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _confirmLeaveClean,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('로비로 나가기'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapLoadingOverlay() {
    if (_naverMapWidgetError != null) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                Text(
                  _naverMapWidgetError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _retryBootstrap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      child: const Text('다시 시도'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _confirmLeaveClean,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      child: const Text('나가기'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const ColoredBox(
      color: Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54, strokeWidth: 3),
            SizedBox(height: 14),
            Text(
              '전장 지도 로딩 중...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView(
    BuildContext context, {
    required FantasyWarsGameState fwState,
    required MapSessionState mapState,
  }) {
    final steps = _cleanBootstrapSteps(fwState, mapState);
    final waiting = _bootstrapError == null &&
        !_isCriticalBootstrapReady(fwState, mapState);
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF020617).withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 30,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: waiting
                              ? const Color(0xFF0EA5E9).withValues(alpha: 0.16)
                              : colorScheme.error.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: waiting
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child:
                                    CircularProgressIndicator(strokeWidth: 3),
                              )
                            : Icon(
                                Icons.error_outline_rounded,
                                color: colorScheme.error,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cleanBootstrapHeadline(fwState, mapState),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _cleanBootstrapDescription(fwState, mapState),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < steps.length; index++) ...[
                          FwBootstrapStepTile(step: steps[index]),
                          if (index != steps.length - 1)
                            const Divider(color: Colors.white12, height: 16),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '필수 단계가 끝나면 전장 화면을 표시합니다. 선택 단계는 게임 화면을 연 뒤 이어서 초기화됩니다.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _bootstrapping ? null : _retryBootstrap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('다시 시도'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _confirmLeaveClean,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('로비로 나가기'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fwState = ref.watch(fantasyWarsProvider(widget.sessionId));
    final mapState = ref.watch(mapSessionProvider(widget.sessionId));
    // authProvider 의 다른 필드(이메일/표시명 등) 변경에 게임 화면 전체가
    // rebuild 되지 않도록 id 만 좁게 구독한다.
    final myId =
        ref.watch(authProvider.select((value) => value.valueOrNull?.id));
    // 세션 만료 시각만 좁게 구독해 lobby 상태의 다른 필드(speakers 등) 변화로
    // 게임 화면이 통째로 rebuild 되지 않도록 한다.
    final gameExpiresAt = ref.watch(
      lobbyProvider(widget.sessionId).select((s) => s.sessionInfo?.expiresAt),
    );

    final showBootstrapView = !_isCriticalBootstrapReady(fwState, mapState) ||
        _bootstrapError != null;

    // MediaQuery.of(context) 는 IME / 시스템 인셋 / orientation 등 모든 변경에
    // 의존성이 걸려 매 키보드 토글마다 build 가 재실행된다. 우리가 실제로 쓰는
    // size / padding.bottom 만 의존성으로 등록되도록 sizeOf / paddingOf 사용.
    final screenSize = MediaQuery.sizeOf(context);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final compactWidth = screenSize.width < 390;
    final compactHeight = screenSize.height < 740;
    // Layer 4(채팅) ↔ Layer 3(거점 바) ↔ Layer 5/6(액션/스킬) 순서로 위로 쌓인다.
    final maxChatSheetHeight = (screenSize.height * 0.5)
        .clamp(_chatSheetMin, math.max(_chatSheetMin, screenSize.height - 220))
        .toDouble();
    final chatSheetHeight =
        _chatSheetHeight.clamp(_chatSheetMin, maxChatSheetHeight).toDouble();
    // 거점 칩 한 줄(5개) 의 고정 높이. 상세 카드는 칩 위로 별도 펼쳐지므로 여기엔
    // 포함되지 않는다. 칩만 차지하는 영역을 작게 유지해야 지도 드래그/줌 제스처가
    // 화면 대부분에서 잘 동작한다.
    final double cpBarHeight = compactHeight ? 52.0 : 56.0;
    final chatBottomBase = bottomSafe + (compactHeight ? 6 : 8);
    final cpBarBottom = chatBottomBase + chatSheetHeight + 4;
    final dockBottom = cpBarBottom + cpBarHeight + 8;
    final skillOffset = dockBottom;
    final myLocationOffset = dockBottom + (compactHeight ? 82 : 98);
    final initialMapTarget = _resolveInitialMapTarget(mapState);
    final nearestControlPoint = _nearestControlPoint(fwState, mapState, myId);
    final nearestControlPointDistance = nearestControlPoint == null
        ? null
        : _distanceToControlPoint(nearestControlPoint, mapState, myId);
    final duelCandidateIds = _candidateMemberIds(
      mapState: mapState,
      fwState: fwState,
      myId: myId,
      enemy: true,
      nearbyOnly: true,
    );

    // 거리/생존/결투 기본 게이트. 점령 시작과 disrupt 의 공통 전제.
    final isAliveAndFree = fwState.myState.isAlive && !fwState.myState.inDuel;
    final isInCaptureRange = nearestControlPoint != null &&
        (nearestControlPointDistance ?? double.infinity) <=
            _captureRadiusMeters;

    // 점령 "시작": 우리 길드 점령지에선 무의미하므로 capturedBy != myGuild 만 허용.
    // isInCaptureRange 가 true 면 nearestControlPoint 는 보장 non-null
    // (analyzer 가 short-circuit promotion 으로 추론).
    final canReachCapture = isAliveAndFree &&
        isInCaptureRange &&
        nearestControlPoint.capturedBy != fwState.myState.guildId;
    final capturePoint = canReachCapture ? nearestControlPoint : null;
    final captureCrew = capturePoint == null
        ? null
        : _captureCrewStatus(capturePoint, fwState, mapState, myId);
    final isCancellingCapture = canReachCapture &&
        fwState.myState.captureZone == capturePoint?.id &&
        capturePoint?.capturingGuild == fwState.myState.guildId;

    // disrupt 는 capturedBy 와 무관 — 우리 길드 점령지에서 적이 점령 중이면
    // 방어 동작이 가장 중요하다. capturingGuild != myGuild 만으로 결정.
    final canDisruptCapture = isAliveAndFree &&
        isInCaptureRange &&
        nearestControlPoint.capturingGuild != null &&
        nearestControlPoint.capturingGuild != fwState.myState.guildId;
    final canUseCaptureButton = canDisruptCapture ||
        isCancellingCapture ||
        (capturePoint != null &&
            captureCrew != null &&
            captureCrew.count >= captureCrew.required);

    // captureLabel/dungeonLabel은 신규 FwActionDock 내부에서 라벨을 자체 결정하므로 빌드 단계에선 별도 변수가 필요 없다.
    // 점령 진행 중에는 결투 요청이 백엔드에서 차단되므로 버튼을 숨긴다.
    // 점령을 먼저 취소하면 같은 자리에서 결투 버튼이 다시 노출된다.
    final isOutsideBattlefield = _isOutsideBattlefield(fwState, mapState, myId);
    final duelLabel = fwState.myState.isAlive &&
            !fwState.myState.inDuel &&
            fwState.myState.captureZone == null &&
            fwState.duel.phase == 'idle' &&
            duelCandidateIds.isNotEmpty
        ? '결투 신청'
        : null;

    final memberLabels = <String, String>{
      for (final entry in mapState.members.entries)
        entry.key: entry.value.nickname,
    };
    final isHost = mapState.myRole == 'host';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmLeaveClean();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // FwAiChatSheet already consumes viewInsets.bottom. Letting Scaffold
        // resize too causes duplicate viewport metric churn while IME opens.
        resizeToAvoidBottomInset: false,
        // 분기 제거: showBootstrapView 전환 때 NaverMap이 unmount되어
        // SurfaceTexture DISCONNECTED가 발생하던 문제를 막기 위해
        // body는 항상 Stack으로 빌드한다. 부트스트랩 화면은 위에 얹는 오버레이로 처리한다.
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 0. 항상 살아 있는 NaverMap 레이어
            // LayoutBuilder + SizedBox.expand로 명시적 제약을 강제하고,
            // 부모 제약이 순간적으로 0,0이 되는 첫 measure 사이클을 피한다.
            _stableMapLayer(initialMapTarget),

            // 1. 게임 HUD/액션 레이어
            // 부트스트랩 중에도 트리는 유지하되 보이지 않게 한다.
            // 입력은 IgnorePointer로 차단해 잘못된 탭이 흘러가지 않도록 한다.
            Visibility(
              visible: !showBootstrapView,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              maintainInteractivity: false,
              child: IgnorePointer(
                ignoring: showBootstrapView,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ─── Layer 1: 상단 HUD (길드/HP/직업/생존자/상태효과) ────
                    FwTopHud(
                      myState: fwState.myState,
                      guilds: fwState.guilds,
                      aliveCount: fwState.alivePlayerIds.length,
                    ),

                    if (isOutsideBattlefield)
                      FwCleanBattlefieldWarningButton(
                        onPressed: () => unawaited(
                          _handleBattlefieldWarningClean(fwState),
                        ),
                      ),

                    // ─── 우상단 utility rail (Layer 2/Voice/Log/Leave/AI/BLE) ─
                    // 이전에는 4개 Positioned 가 같은 우측 영역을 두고 충돌해
                    // FwTopHud(left=8, right=64) 와도 겹쳤다. 단일 rail Column
                    // 으로 통합해 FwTopHud 카드 아래(topInset+132) 에서 시작
                    // 시키고, 폭은 220 으로 clamp(작은 화면에서는 화면-24 가
                    // 더 작으면 그쪽). compactWidth 에서는 AI/BLE 행을 숨겨
                    // FwBattlePanel 안으로 흡수되게 한다.
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 132,
                      right: FwSpace.x8,
                      bottom: dockBottom + 8,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.min(220.0, screenSize.width - 24.0),
                        ),
                        // utility rail 은 자체적으로 그림자/Border 가 많고, 다른
                        // HUD 변경(점령 진행률 / chat 스크롤 등) 과 독립적으로 변하므로
                        // RepaintBoundary 로 raster 캐시 분리.
                        child: RepaintBoundary(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // 1) 호스트 Log + 나가기 — utility 그룹.
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isHost) ...[
                                      TextButton.icon(
                                        onPressed: () =>
                                            unawaited(_openHostDebugSheet(
                                          fwState: fwState,
                                          mapState: mapState,
                                          memberLabels: memberLabels,
                                          duelCandidateIds: duelCandidateIds,
                                          myId: myId,
                                        )),
                                        style: TextButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xCC0F766E),
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(
                                          Icons.admin_panel_settings_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Log',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: FwSpace.x8),
                                    ],
                                    TextButton(
                                      onPressed: _confirmLeaveClean,
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.black54,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 32),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        '나가기',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: FwSpace.x8),
                                // 2) 전장 정보 패널 (이전에는 자체 Positioned).
                                FwBattlePanel(
                                  expanded: _battlePanelExpanded,
                                  onToggle: () {
                                    if (!mounted) return;
                                    setState(
                                      () => _battlePanelExpanded =
                                          !_battlePanelExpanded,
                                    );
                                  },
                                  dungeonLabel: _dungeonStatusLabel(fwState),
                                  relicHolderLabel:
                                      _relicHolderLabel(fwState, mapState),
                                  trackedTargetLabel: _trackedTargetLabel(
                                      fwState, memberLabels),
                                  bleSummary: _bleSummaryClean(
                                    mapState,
                                    duelCandidateIds.length,
                                  ),
                                  telemetryLabel: _telemetryLabel(mapState),
                                  recentDuelLogs: fwState.recentEvents
                                      .where((e) => e.kind == 'duel')
                                      .take(3)
                                      .map((e) => e.message)
                                      .toList(),
                                  maxExpandedHeight: math.max(
                                    160.0,
                                    screenSize.height * 0.5,
                                  ),
                                  gameExpiresAtMs:
                                      gameExpiresAt?.millisecondsSinceEpoch,
                                ),
                                const SizedBox(height: FwSpace.x8),
                                // 3) Voice chip.
                                FwVoiceChip(
                                  isMuted: _isMicMuted,
                                  isSelfSpeaking: _isSelfSpeaking,
                                  isReady: MediaSoupAudioService().isReady,
                                  channelLabel: _voiceChannelLabel(fwState),
                                  channelColor: _voiceChannelColor(fwState),
                                  onTap: () {
                                    unawaited(
                                        MediaSoupAudioService().toggleMute());
                                  },
                                ),
                                // 4) AI / BLE — compact 에서는 숨김(전장 정보 안의
                                // BLE 요약/배지가 대체).
                                if (!compactWidth) ...[
                                  const SizedBox(height: FwSpace.x8),
                                  AiMasterStatusWidget(
                                      sessionId: widget.sessionId),
                                  const SizedBox(height: FwSpace.x4),
                                  const BleStatusWidget(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ─── Layer 3: 점령지 5개를 한 줄에 모두 노출 + 탭 시 상세 ───
                    // RepaintBoundary 는 위젯 내부 Positioned 안쪽에서 적용되어
                    // Stack 의 ParentDataWidget 계약을 깨지 않게 한다.
                    FwControlPointBar(
                      controlPoints: fwState.controlPoints,
                      myGuildId: fwState.myState.guildId,
                      guilds: fwState.guilds,
                      bottomOffset: cpBarBottom,
                      barHeight: cpBarHeight,
                      selectedControlPointId: _selectedControlPointId,
                      onFocusChanged: (cp) {
                        _setSelection(controlPointId: cp.id);
                        if (cp.lat != null && cp.lng != null) {
                          unawaited(_focusMapTarget(
                            lat: cp.lat!,
                            lng: cp.lng!,
                            zoom: 16.4,
                          ));
                        }
                      },
                      onDismiss: () => _setSelection(controlPointId: null),
                    ),

                    // ─── Layer 5: 좌측 하단 액션 도크 (점령/결투/던전 항상 표시) ───
                    FwActionDock(
                      bottomOffset: dockBottom,
                      captureEnabled: canUseCaptureButton,
                      duelEnabled: duelLabel != null,
                      dungeonEnabled: !fwState.myState.isAlive &&
                          !fwState.myState.dungeonEntered,
                      captureLabel: canDisruptCapture
                          ? '점령 방해'
                          : (canUseCaptureButton
                              ? (isCancellingCapture ? '점령 취소' : '점령')
                              : '점령'),
                      captureDisabledReason: _captureDisabledReason(
                        fwState: fwState,
                        nearestControlPoint: nearestControlPoint,
                        nearestControlPointDistance:
                            nearestControlPointDistance,
                        captureCrew: captureCrew,
                        isOutsideBattlefield: isOutsideBattlefield,
                      ),
                      duelDisabledReason: _duelDisabledReason(
                        fwState: fwState,
                        duelCandidateIds: duelCandidateIds,
                      ),
                      dungeonDisabledReason: _dungeonDisabledReason(fwState),
                      onCapture: () => unawaited(
                          _handleCaptureActionClean(fwState, mapState, myId)),
                      onDuel: () => unawaited(
                          _handleDuelActionClean(fwState, mapState, myId)),
                      onDungeon: () => unawaited(_runAck(() {
                        return ref
                            .read(
                              fantasyWarsProvider(widget.sessionId).notifier,
                            )
                            .enterDungeon();
                      })),
                      onShowDisabledReason: _showInfoToast,
                    ),

                    // ─── Layer 6: 우측 하단 직업 스킬 버튼 ─────────────────
                    if (fwState.myState.isAlive && !fwState.myState.inDuel)
                      FwSkillButton(
                        job: fwState.myState.job,
                        skillUsedAt: fwState.myState.skillUsedAt,
                        bottomOffset: skillOffset,
                        onPressed: () => unawaited(
                          _handleSkillActionClean(fwState, mapState, myId),
                        ),
                      ),

                    // 내 위치 버튼 (기존)
                    Positioned(
                      right: compactWidth ? 14 : 24,
                      bottom: myLocationOffset,
                      child: FwMapRoundButton(
                        icon: Icons.my_location_rounded,
                        tooltip: '내 위치',
                        onPressed: () =>
                            unawaited(_focusMyLocationClean(mapState)),
                      ),
                    ),

                    // ─── Layer 4: 하단 AI 채팅 시트 (드래그 확장) ──────────
                    // FwAiChatSheet 는 Positioned 를 직접 반환하므로 RepaintBoundary
                    // 로 감싸면 Stack 의 ParentDataWidget 계약이 깨진다. raster 캐시
                    // 분리는 FwAiChatSheet 내부 Positioned.child 자리에서 적용.
                    ValueListenableBuilder<List<_FwAiChatLine>>(
                      valueListenable: _aiChatLinesNotifier,
                      builder: (context, aiChatLines, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _aiChatSendingNotifier,
                          builder: (context, aiChatSending, _) {
                            return FwAiChatSheet(
                              controller: _aiChatController,
                              focusNode: _aiChatFocusNode,
                              messages: _composeChatMessages(
                                fwState,
                                aiChatLines,
                              ),
                              sending: aiChatSending,
                              currentHeight: chatSheetHeight,
                              minHeight: _chatSheetMin,
                              expandedHeight: _chatSheetExpanded,
                              maxHeight: maxChatSheetHeight,
                              onHeightChanged: (h) {
                                if (!mounted) return;
                                setState(() => _chatSheetHeight = h);
                              },
                              onSubmit: () => unawaited(_sendAiChatMessage()),
                            );
                          },
                        );
                      },
                    ),

                    // ─── Layer 6.5: 결투/부활 타이머 배지 (84x84 우측 하단) ──
                    if (fwState.myState.inDuel &&
                        fwState.myState.duelExpiresAt != null)
                      FwTimerBadge(
                        expiresAtMs: fwState.myState.duelExpiresAt!,
                        totalMs: 30000,
                        icon: Icons.sports_martial_arts_rounded,
                        bottomOffset: dockBottom + 8,
                      )
                    else if (!fwState.myState.isAlive &&
                        fwState.myState.dungeonEntered &&
                        fwState.myState.reviveReady)
                      FwReviveButton(
                        bottomOffset: dockBottom + 8,
                        chance: fwState.myState.nextReviveChance ?? 0.3,
                        onTap: () => unawaited(_runAck(() {
                          return ref
                              .read(fantasyWarsProvider(widget.sessionId)
                                  .notifier)
                              .attemptRevive();
                        })),
                      )
                    else if (!fwState.myState.isAlive &&
                        fwState.myState.dungeonEntered &&
                        fwState.myState.nextReviveAt != null)
                      FwTimerBadge(
                        expiresAtMs: fwState.myState.nextReviveAt!,
                        totalMs: 60000,
                        icon: Icons.favorite_rounded,
                        bottomOffset: dockBottom + 8,
                      ),

                    // ─── Layer 7: 토스트 (시스템 이벤트, fade in/out 2초) ──
                    if (_toastMessage != null)
                      FwToastOverlay(
                        message: _toastMessage!,
                        kind: _toastKind ?? 'system',
                      ),

                    // ─── Layer 7.5: 점령 진행 HUD ─────────────────────
                    // 내 길드가 점령을 시작했고 아직 진행 중일 때만 노출. 결투 중이면
                    // 그쪽이 풀스크린을 점유하므로 점령 HUD 는 보이지 않는다.
                    () {
                      final myGuildId = fwState.myState.guildId;
                      if (myGuildId == null) return const SizedBox.shrink();
                      if (fwState.duel.phase != 'idle') {
                        return const SizedBox.shrink();
                      }
                      FwControlPoint? activeCp;
                      for (final cp in fwState.controlPoints) {
                        if (cp.capturingGuild == myGuildId &&
                            cp.captureStartedAt != null) {
                          activeCp = cp;
                          break;
                        }
                      }
                      if (activeCp == null) return const SizedBox.shrink();
                      return Positioned(
                        left: 16,
                        right: 16,
                        bottom: 96,
                        child: FwCaptureProgressOverlay(controlPoint: activeCp),
                      );
                    }(),

                    // ─── Layer 8: 결투 오버레이 (4-페이즈 통합) ───────────
                    if (_resolveDuelPhase(fwState.duel.phase) !=
                        FwDuelPhase.none)
                      FwDuelOverlay(
                        phase: _resolveDuelPhase(fwState.duel.phase),
                        opponentLabel:
                            _resolveOpponentLabel(fwState, memberLabels),
                        duelResult: fwState.duel.duelResult,
                        minigameType: fwState.duel.minigameType,
                        myId: myId,
                        myJob: fwState.myState.job,
                        myName:
                            (myId != null ? memberLabels[myId] : null) ?? '나',
                        onCancel: () => unawaited(_runAck(() {
                          return ref
                              .read(fantasyWarsProvider(widget.sessionId)
                                  .notifier)
                              .cancelDuel();
                        })),
                        onAccept: () => unawaited(_runAck(() async {
                          final opponentId = fwState.duel.opponentId;
                          final proximity = opponentId == null
                              ? null
                              : _duelProximityForUser(
                                  opponentId,
                                  mapState,
                                  myId,
                                );
                          if (opponentId != null && proximity == null) {
                            return {
                              'ok': false,
                              'error': 'BLE_PROXIMITY_REQUIRED',
                            };
                          }
                          if (myId != null) {
                            unawaited(
                              ref.read(bleDuelProvider.notifier).startForDuel(
                                    sessionId: widget.sessionId,
                                    userId: myId,
                                    memberUserIds:
                                        _bleMemberIds(mapState, myId),
                                  ),
                            );
                          }
                          return ref
                              .read(fantasyWarsProvider(widget.sessionId)
                                  .notifier)
                              .acceptDuel(
                                fwState.duel.duelId!,
                                proximity: proximity?.toMap(),
                              );
                        })),
                        onReject: () => unawaited(_runAck(() {
                          return ref
                              .read(fantasyWarsProvider(widget.sessionId)
                                  .notifier)
                              .rejectDuel(fwState.duel.duelId!);
                        })),
                        onCloseResult: () => ref
                            .read(
                                fantasyWarsProvider(widget.sessionId).notifier)
                            .clearDuelResult(),
                        miniGame: fwState.duel.phase == 'in_game'
                            ? FwDuelScreen(
                                sessionId: widget.sessionId,
                                duel: fwState.duel,
                                myJob: fwState.myState.job,
                                myName: (myId != null
                                        ? memberLabels[myId]
                                        : null) ??
                                    '나',
                                opponentName: _resolveOpponentLabel(
                                        fwState, memberLabels) ??
                                    '상대',
                                myId: myId ?? '',
                                opponentId: fwState.duel.opponentId,
                              )
                            : null,
                      ),

                    // 결투 종료 시 BLE 정리 (기존 사이드 이펙트)
                    if (fwState.duel.phase == 'result')
                      Builder(builder: (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ref.read(bleDuelProvider.notifier).stopAfterDuel();
                        });
                        return const SizedBox.shrink();
                      }),

                    // 게임 종료 — 종합 결과 화면 (길드 점수/점령지/멤버 생존)
                    if (fwState.isFinished && fwState.winCondition != null)
                      FwGameResultScreen(
                        winCondition: fwState.winCondition!,
                        myGuildId: fwState.myState.guildId,
                        guilds: fwState.guilds,
                        controlPoints: fwState.controlPoints,
                        alivePlayerIds: fwState.alivePlayerIds,
                        eliminatedPlayerIds: fwState.eliminatedPlayerIds,
                        memberLabels: memberLabels,
                        onLeave: _confirmLeaveClean,
                      ),
                  ],
                ),
              ),
            ),

            // 2. 부트스트랩 오버레이
            // NaverMap 위에 얹어서 표시한다. NaverMap은 unmount되지 않는다.
            if (showBootstrapView)
              Positioned.fill(
                child: _buildLoadingViewClean(
                  context,
                  fwState: fwState,
                  mapState: mapState,
                ),
              ),

            // 3. 지도 로딩/오류 오버레이 (onMapReady 전)
            if (!_naverMapWidgetReady)
              Positioned.fill(child: _buildMapLoadingOverlayClean()),
          ],
        ),
      ),
    );
  }
}

class _TargetChoice<T> {
  const _TargetChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.trailing,
    this.badge,
    this.helper,
    this.accentColor,
    this.icon = Icons.person_outline_rounded,
    this.isHighlighted = false,
  });

  final T value;
  final String label;
  final String? subtitle;
  final String? trailing;
  final String? badge;
  final String? helper;
  final Color? accentColor;
  final IconData icon;
  final bool isHighlighted;
}

class _FwAiChatLine {
  const _FwAiChatLine({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String role;
  final String text;
  final DateTime createdAt;
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;
}

// 플레이어 마커 아이콘 사이즈. ring 까지 포함한 전체 박스를 동일하게 유지해
// speaking 토글 시 anchor (0.5, 0.5) 기준의 시각적 jitter 가 없도록 한다.
const double _kFwPlayerMarkerBoxSize = 48.0;
const double _kFwPlayerMarkerInnerSize = 28.0;

class _FwPlayerMarkerIcon extends StatelessWidget {
  const _FwPlayerMarkerIcon({
    required this.color,
    required this.isSpeaking,
  });

  final Color color;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kFwPlayerMarkerBoxSize,
      height: _kFwPlayerMarkerBoxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isSpeaking)
            Container(
              width: _kFwPlayerMarkerBoxSize - 4,
              height: _kFwPlayerMarkerBoxSize - 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.95),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          Container(
            width: _kFwPlayerMarkerInnerSize,
            height: _kFwPlayerMarkerInnerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: Colors.white,
                width: 2.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
