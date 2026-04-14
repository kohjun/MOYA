import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'socket_service.dart';

// VAD 설정
const _kVadIntervalMs = 200;      // stats 폴링 주기 (ms)
const _kSpeakingThreshold = 0.01; // 이 레벨 이상이면 말하는 중으로 판단
const _kSpeakingDebounceMs = 600; // speaking→silent 전환 대기시간 (ms)

class MediaSoupAudioService {
  MediaSoupAudioService._internal() {
    _bindSocketStreams();
  }

  static final MediaSoupAudioService _instance =
      MediaSoupAudioService._internal();

  factory MediaSoupAudioService() => _instance;

  final SocketService _socketService = SocketService();

  Device? _device;
  Transport? _sendTransport;
  Transport? _recvTransport;
  Producer? _micProducer;
  MediaStream? _localAudioStream;

  String? _currentSessionId;
  bool _shouldAutoReconnect = false;
  Future<void>? _joinFuture;

  final Map<String, Consumer> _consumersByPeerId = {};
  final Map<String, Completer<void>> _pendingConsumerCompleters = {};

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _newProducerSub;
  StreamSubscription<Map<String, dynamic>>? _producerClosedSub;

  // ── 음소거 상태 ──────────────────────────────────────────────────────────
  bool _isMuted = false;
  final _mutedController = StreamController<bool>.broadcast();

  // ── VAD (Voice Activity Detection) ──────────────────────────────────────
  bool _isSpeaking = false;
  DateTime? _lastSpeakingAt;
  Timer? _vadTimer;
  final _speakingController = StreamController<bool>.broadcast();

  bool get isMuted => _isMuted;
  bool get isSpeaking => _isSpeaking;
  Stream<bool> get isMutedStream => _mutedController.stream;
  Stream<bool> get isSpeakingStream => _speakingController.stream;

  bool get isReady =>
      _device != null && _recvTransport != null && _currentSessionId != null;

  String? get currentSessionId => _currentSessionId;

  Future<void> ensureJoined(String sessionId) {
    if (_currentSessionId == sessionId && isReady) {
      return Future.value();
    }

    if (_joinFuture != null) {
      return _joinFuture!;
    }

    _shouldAutoReconnect = true;
    _joinFuture = _joinSession(sessionId).whenComplete(() {
      _joinFuture = null;
    });

    return _joinFuture!;
  }

  Future<void> leaveSession() async {
    _shouldAutoReconnect = false;
    await _closeMediaState(clearSession: true);
  }

  Future<void> _joinSession(String sessionId) async {
    if (_currentSessionId != null && _currentSessionId != sessionId) {
      await _closeMediaState(clearSession: false);
    }

    _currentSessionId = sessionId;

    if (!_socketService.isConnected) {
      return;
    }

    if (_recvTransport != null && _device != null) {
      return;
    }

    try {
      final routerCapsResponse = await _request(
        SocketEvents.mediaGetRouterRtpCapabilities,
        {'sessionId': sessionId},
      );

      final routerRtpCapabilities = RtpCapabilities.fromMap(
        Map<String, dynamic>.from(
          routerCapsResponse['rtpCapabilities'] as Map<dynamic, dynamic>,
        ),
      );

      final device = Device();
      await device.load(routerRtpCapabilities: routerRtpCapabilities);
      _device = device;

      await _createRecvTransport(sessionId);
      await _createSendTransport(sessionId);
      await _publishMicrophone();
      await _consumeExistingProducers(sessionId);
    } catch (error, stackTrace) {
      debugPrint('[MediaSoup] join failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _closeMediaState(clearSession: false);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    String event,
    Map<String, dynamic> payload, {
    bool allowJoinRetry = true,
  }) async {
    final response = await _socketService.emitWithAck(event, payload);
    if (response['ok'] == true) {
      return response;
    }

    final errorCode = response['error'] as String? ?? 'UNKNOWN_MEDIA_ERROR';
    if (allowJoinRetry &&
        (errorCode == 'JOIN_SESSION_REQUIRED' ||
            errorCode == 'MISSING_SESSION_ID')) {
      await Future.delayed(const Duration(milliseconds: 250));
      return _request(event, payload, allowJoinRetry: false);
    }

    throw StateError('[$event] $errorCode');
  }

  Future<void> _createRecvTransport(String sessionId) async {
    final device = _device;
    if (device == null) {
      throw StateError('MEDIASOUP_DEVICE_NOT_READY');
    }

    final response = await _request(
      SocketEvents.mediaCreateWebRtcTransport,
      {
        'sessionId': sessionId,
        'direction': 'recv',
      },
    );

    final transport = device.createRecvTransportFromMap(
      _transportPayload(response),
      consumerCallback: _handleNewConsumer,
    );

    _wireConnectHandler(
      transport: transport,
      sessionId: sessionId,
      direction: 'recv',
    );
    _wireConnectionStateLogger(transport, 'recv');

    _recvTransport = transport;
  }

  Future<void> _createSendTransport(String sessionId) async {
    final device = _device;
    if (device == null ||
        !device.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio)) {
      return;
    }

    final response = await _request(
      SocketEvents.mediaCreateWebRtcTransport,
      {
        'sessionId': sessionId,
        'direction': 'send',
      },
    );

    final transport = device.createSendTransportFromMap(
      _transportPayload(response),
      producerCallback: _handleLocalProducer,
    );

    _wireConnectHandler(
      transport: transport,
      sessionId: sessionId,
      direction: 'send',
    );
    _wireProduceHandler(transport, sessionId);
    _wireConnectionStateLogger(transport, 'send');

    _sendTransport = transport;
  }

  void _wireConnectHandler({
    required Transport transport,
    required String sessionId,
    required String direction,
  }) {
    transport.on('connect', (Map<dynamic, dynamic> data) {
      _request(
        SocketEvents.mediaConnectWebRtcTransport,
        {
          'sessionId': sessionId,
          'direction': direction,
          'dtlsParameters':
              (data['dtlsParameters'] as DtlsParameters).toMap(),
        },
      ).then((_) {
        (data['callback'] as Function).call();
      }).catchError((Object error) {
        (data['errback'] as Function).call(error);
      });
    });
  }

  void _wireProduceHandler(Transport transport, String sessionId) {
    transport.on('produce', (Map<dynamic, dynamic> data) async {
      try {
        final response = await _request(
          SocketEvents.mediaProduce,
          {
            'sessionId': sessionId,
            'kind': data['kind'],
            'rtpParameters':
                (data['rtpParameters'] as RtpParameters).toMap(),
          },
        );

        (data['callback'] as Function).call(response['producerId']);
      } catch (error) {
        (data['errback'] as Function).call(error);
      }
    });
  }

  void _wireConnectionStateLogger(Transport transport, String label) {
    transport.on('connectionstatechange', (dynamic state) {
      debugPrint('[MediaSoup] $label transport state: $state');
    });
  }

  Future<void> _publishMicrophone() async {
    if (_sendTransport == null || _micProducer != null) {
      return;
    }

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint('[MediaSoup] microphone permission denied');
      return;
    }

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': false,
    };

    MediaStream? stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw StateError('MIC_TRACK_NOT_FOUND');
      }
      final audioTrack = audioTracks.first;

      _localAudioStream = stream;
      _sendTransport!.produce(
        track: audioTrack,
        stream: stream,
        source: 'mic',
        appData: const {'source': 'mic'},
        codecOptions: ProducerCodecOptions(
          opusStereo: 1,
          opusDtx: 1,
        ),
      );
      _startVad();
    } catch (error) {
      debugPrint('[MediaSoup] failed to publish mic: $error');
      if (stream != null) {
        await Future.sync(stream.dispose);
      }
    }
  }

  // ── 음소거 토글 ──────────────────────────────────────────────────────────
  Future<void> toggleMute() async {
    final producer = _micProducer;
    if (producer == null) return;

    _isMuted = !_isMuted;

    if (_isMuted) {
      producer.pause();
      // 음소거 시 speaking 상태 즉시 해제
      if (_isSpeaking) {
        _isSpeaking = false;
        _speakingController.add(false);
        _socketService.emitVoiceSpeaking(
          _currentSessionId ?? '',
          isSpeaking: false,
        );
      }
    } else {
      producer.resume();
    }

    _mutedController.add(_isMuted);
  }

  // ── VAD: 주기적으로 send transport stats를 폴링해 오디오 레벨 확인 ──────
  void _startVad() {
    _vadTimer?.cancel();
    _vadTimer = Timer.periodic(
      const Duration(milliseconds: _kVadIntervalMs),
      (_) => _checkAudioLevel(),
    );
  }

  void _stopVad() {
    _vadTimer?.cancel();
    _vadTimer = null;
    if (_isSpeaking) {
      _isSpeaking = false;
      _speakingController.add(false);
    }
  }

  Future<void> _checkAudioLevel() async {
    if (_isMuted || _sendTransport == null) return;

    try {
      final stats = await _sendTransport!.getState();
      double? level;
      for (final report in stats) {
        final raw = report.values['audioLevel'];
        if (raw != null) {
          level = (raw as num).toDouble();
          break;
        }
      }

      if (level == null) return;

      final nowSpeaking = level >= _kSpeakingThreshold;
      final now = DateTime.now();

      if (nowSpeaking) {
        _lastSpeakingAt = now;
        if (!_isSpeaking) {
          _isSpeaking = true;
          _speakingController.add(true);
          final sessionId = _currentSessionId;
          if (sessionId != null && sessionId.isNotEmpty) {
            _socketService.emitVoiceSpeaking(sessionId, isSpeaking: true);
          }
        }
      } else if (_isSpeaking) {
        final elapsed = _lastSpeakingAt == null
            ? _kSpeakingDebounceMs + 1
            : now.difference(_lastSpeakingAt!).inMilliseconds;
        if (elapsed >= _kSpeakingDebounceMs) {
          _isSpeaking = false;
          _speakingController.add(false);
          final sessionId = _currentSessionId;
          if (sessionId != null && sessionId.isNotEmpty) {
            _socketService.emitVoiceSpeaking(sessionId, isSpeaking: false);
          }
        }
      }
    } catch (_) {
      // transport가 닫혔거나 stats 미지원 시 조용히 무시
    }
  }

  void _handleLocalProducer(Producer producer) {
    _micProducer = producer;

    producer.on('trackended', () {
      debugPrint('[MediaSoup] local mic track ended');
    });

    producer.on('transportclose', () {
      if (_micProducer?.id == producer.id) {
        _micProducer = null;
      }
    });

    producer.on('close', () {
      if (_micProducer?.id == producer.id) {
        _micProducer = null;
      }
    });
  }

  void _handleNewConsumer(Consumer consumer, [dynamic accept]) {
    final producerPeerId = consumer.peerId;
    if (producerPeerId != null) {
      _consumersByPeerId[producerPeerId] = consumer;
      final completer = _pendingConsumerCompleters.remove(producerPeerId);
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }

    if (accept is Function) {
      accept(<String, dynamic>{});
    }

    consumer.on('trackended', () {
      if (producerPeerId != null) {
        unawaited(_removeConsumer(producerPeerId));
      }
    });

    consumer.on('transportclose', () {
      if (producerPeerId != null) {
        unawaited(_removeConsumer(producerPeerId));
      }
    });

    consumer.on('close', () {
      if (producerPeerId != null) {
        _consumersByPeerId.remove(producerPeerId);
      }
    });
  }

  Future<void> _consumeExistingProducers(String sessionId) async {
    final response = await _request(
      SocketEvents.mediaGetProducers,
      {'sessionId': sessionId},
    );

    final producerPeerIds =
        (response['producerPeerIds'] as List<dynamic>? ?? const [])
            .whereType<String>();

    for (final producerPeerId in producerPeerIds) {
      await _consumePeer(producerPeerId);
    }
  }

  Future<void> _consumePeer(String producerPeerId) async {
    final sessionId = _currentSessionId;
    final device = _device;
    final recvTransport = _recvTransport;

    if (sessionId == null || device == null || recvTransport == null) {
      return;
    }

    if (_consumersByPeerId.containsKey(producerPeerId) ||
        _pendingConsumerCompleters.containsKey(producerPeerId)) {
      return;
    }

    final completer = Completer<void>();
    _pendingConsumerCompleters[producerPeerId] = completer;

    try {
      final response = await _request(
        SocketEvents.mediaConsume,
        {
          'sessionId': sessionId,
          'producerPeerId': producerPeerId,
          'rtpCapabilities': device.rtpCapabilities.toMap(),
        },
      );

      final consumerPayload = Map<String, dynamic>.from(
        response['consumer'] as Map<dynamic, dynamic>,
      );

      recvTransport.consume(
        id: consumerPayload['id'] as String,
        producerId: consumerPayload['producerId'] as String,
        peerId: consumerPayload['producerPeerId'] as String,
        kind: RTCRtpMediaTypeExtension.fromString(
          consumerPayload['kind'] as String,
        ),
        rtpParameters: RtpParameters.fromMap(
          Map<String, dynamic>.from(
            consumerPayload['rtpParameters'] as Map<dynamic, dynamic>,
          ),
        ),
        appData: const {'source': 'remote-audio'},
      );

      await completer.future.timeout(const Duration(seconds: 5));
    } catch (error) {
      _pendingConsumerCompleters.remove(producerPeerId);
      debugPrint('[MediaSoup] failed to consume $producerPeerId: $error');
    }
  }

  Future<void> _removeConsumer(String producerPeerId) async {
    _pendingConsumerCompleters.remove(producerPeerId);
    final consumer = _consumersByPeerId.remove(producerPeerId);
    if (consumer == null) {
      return;
    }

    await Future.sync(consumer.close);
  }

  void _bindSocketStreams() {
    _connectionSub ??=
        _socketService.onConnectionChange.listen((bool connected) {
      if (!connected) {
        unawaited(_closeMediaState(clearSession: false));
        return;
      }

      final sessionId = _currentSessionId;
      if (_shouldAutoReconnect && sessionId != null) {
        unawaited(ensureJoined(sessionId));
      }
    });

    _newProducerSub ??=
        _socketService.onMediaNewProducer.listen((Map<String, dynamic> data) {
      final producerPeerId = data['producerPeerId'] as String?;
      if (producerPeerId == null || _currentSessionId == null) {
        return;
      }

      unawaited(_consumePeer(producerPeerId));
    });

    _producerClosedSub ??= _socketService.onMediaProducerClosed
        .listen((Map<String, dynamic> data) {
      final producerPeerId = data['producerPeerId'] as String?;
      if (producerPeerId == null) {
        return;
      }

      unawaited(_removeConsumer(producerPeerId));
    });
  }

  Map<String, dynamic> _transportPayload(Map<String, dynamic> response) {
    return <String, dynamic>{
      'id': response['id'],
      'iceParameters': response['iceParameters'],
      'iceCandidates': response['iceCandidates'],
      'dtlsParameters': response['dtlsParameters'],
      if (response['sctpParameters'] != null)
        'sctpParameters': response['sctpParameters'],
    };
  }

  Future<void> _closeMediaState({required bool clearSession}) async {
    _stopVad();

    for (final completer in _pendingConsumerCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingConsumerCompleters.clear();

    for (final consumer in _consumersByPeerId.values) {
      await Future.sync(consumer.close);
    }
    _consumersByPeerId.clear();

    final micProducer = _micProducer;
    _micProducer = null;
    if (micProducer != null) {
      await Future.sync(micProducer.close);
    }

    final localAudioStream = _localAudioStream;
    _localAudioStream = null;
    if (localAudioStream != null) {
      await Future.sync(localAudioStream.dispose);
    }

    final sendTransport = _sendTransport;
    _sendTransport = null;
    if (sendTransport != null) {
      await sendTransport.close();
    }

    final recvTransport = _recvTransport;
    _recvTransport = null;
    if (recvTransport != null) {
      await recvTransport.close();
    }

    _device = null;

    if (clearSession) {
      _currentSessionId = null;
    }
  }

  Future<void> dispose() async {
    await leaveSession();
    await _connectionSub?.cancel();
    await _newProducerSub?.cancel();
    await _producerClosedSub?.cancel();
    _connectionSub = null;
    _newProducerSub = null;
    _producerClosedSub = null;
    await _mutedController.close();
    await _speakingController.close();
  }
}
