// lib/core/services/background_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// 방금 만든 알림 서비스 임포트

const notificationChannelId = 'location_tracking_channel';
const notificationId = 888;
bool _backgroundServiceInitialized = false;
const _backgroundPreferenceKeys = <String>[
  'bg_token',
  'bg_refresh_token',
  'bg_session_id',
  'bg_server_url',
  'bg_foreground_active',
  'bg_wakeup_requested',
];

Future<void> initializeBackgroundService() async {
  if (_backgroundServiceInitialized) {
    debugPrint('[Background] Service configuration already initialized');
    return;
  }

  final stopwatch = Stopwatch()..start();
  final service = FlutterBackgroundService();

  // 안드로이드 알림 채널 설정
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    '실시간 위치 공유', // title
    description: '세션이 유지되는 동안 위치를 공유합니다.', // description
    importance: Importance.low, // low로 해야 알림 소리가 계속 나지 않음
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // 앱 켜지자마자가 아니라 세션 방 들어갈 때 켤 예정
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: '위치 공유 중',
      initialNotificationContent: '백그라운드에서 위치를 업데이트하고 있습니다',
      foregroundServiceNotificationId: notificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  _backgroundServiceInitialized = true;
  debugPrint(
    '[Background] Service configured in ${stopwatch.elapsedMilliseconds}ms',
  );
}

Future<void> shutdownBackgroundService() async {
  try {
    final service = FlutterBackgroundService();
    bool wasRunning = false;
    try {
      wasRunning = await service.isRunning();
    } catch (e) {
      debugPrint('[Background] isRunning 조회 실패: $e');
    }

    if (wasRunning) {
      try {
        service.invoke('stopService');
      } catch (e) {
        debugPrint('[Background] stopService invoke 실패: $e');
      }

      // stopService 가 background isolate 에 도달할 시간을 준다.
      // 짧은 지연(200ms)으로는 sticky foreground service 가 살아있어
      // "Service already running" 로그가 다음 부팅에 또 뜬다.
      // 최대 ~1초까지 100ms 단위로 isRunning 폴링.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          if (!await service.isRunning()) break;
        } catch (_) {
          break;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_active', false);
    for (final key in _backgroundPreferenceKeys) {
      await prefs.remove(key);
    }
  } catch (e) {
    debugPrint('[Background] Failed to shut down service cleanly: $e');
  }
}

// iOS 전용 백그라운드 핸들러
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// 백그라운드 서비스가 시작될 때 실행되는 메인 진입점
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // DartPluginRegistrant.ensureInitialized() 는 background isolate 에서 사용되는
  // 플러그인(geolocator, shared_preferences, battery_plus 등)을 일괄 등록한다.
  // 이 과정에서 flutter_background_service_android 자체가 "main isolate only"
  // 예외를 던지는데(자기 자신은 background isolate 에 등록되면 안 되기 때문),
  // 이는 정상 동작이며 다른 플러그인 등록은 정상적으로 완료된다. 무시하고 진행.
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (error) {
    debugPrint(
        '[Background] plugin registrant warning (safe to ignore): $error');
  }
  // background isolate 전용 init — 콜백 등록 / 채널 생성 없이 show() 만 가능.
  // 채널은 main isolate 의 initForMainIsolate() 가 미리 만들어 둔다.
  // Keep background isolate free of UI/local-notification plugin init.
  // Main isolate creates channels and owns notification tap callbacks.
  await _BackgroundGeofenceNotifier().init();

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('bg_token');
  final sessionId = prefs.getString('bg_session_id');
  final serverUrl = prefs.getString('bg_server_url') ?? 'http://10.0.2.2:3000';

  if (token == null || sessionId == null) {
    service.stopSelf();
    return;
  }

  // 상태 관리 변수
  io.Socket? socket;
  StreamSubscription<Position>? positionSub;
  Timer? idleTimer;
  Timer? wakeupPollTimer;
  bool isIdle = false;
  bool foregroundActive = prefs.getBool('bg_foreground_active') ?? false;
  Position? prevPos;
  final Set<String> insideGeofences = {};
  final battery = Battery();
  String currentToken = token;

  // 토큰 갱신: /auth/refresh 호출 → 새 accessToken·refreshToken 저장
  Future<bool> refreshAccessToken() async {
    try {
      final uri = Uri.parse('$serverUrl/auth/refresh');
      final client = HttpClient();
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      // 저장된 refresh_token이 있으면 body에 실어 전송 (쿠키 없는 환경 대응)
      final storedRefreshToken = prefs.getString('bg_refresh_token');
      if (storedRefreshToken != null) {
        final bodyBytes =
            utf8.encode(jsonEncode({'refreshToken': storedRefreshToken}));
        req.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length);
        req.add(bodyBytes);
      }

      final resp = await req.close();
      if (resp.statusCode != 200) {
        client.close(force: true);
        return false;
      }
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      final Map<String, dynamic> data =
          jsonDecode(body) as Map<String, dynamic>;

      final newAccessToken = data['accessToken'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;
      if (newAccessToken == null) return false;

      await prefs.setString('bg_token', newAccessToken);
      currentToken = newAccessToken;
      if (newRefreshToken != null) {
        await prefs.setString('bg_refresh_token', newRefreshToken);
      }
      return true;
    } catch (e) {
      debugPrint('[Background] 토큰 갱신 실패: $e');
      return false;
    }
  }

  // 1. 소켓 연결 함수
  void connectSocket() {
    if (socket?.connected == true) return;
    socket?.dispose();
    socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $currentToken'})
          .enableForceNew() // 새로운 연결 강제
          .build(),
    );
    socket!.onConnect((_) => debugPrint('[Background] 소켓 연결됨'));
    socket!.onConnectError((err) async {
      debugPrint('[Background] 소켓 연결 에러: $err');
      try {
        if (err != null && err.toString().contains('AUTH_FAILED')) {
          final ok = await refreshAccessToken();
          if (ok) {
            connectSocket();
          } else {
            debugPrint('[Background] 토큰 갱신 실패 → 서비스 종료');
            service.stopSelf();
          }
        }
      } catch (e) {
        debugPrint('[Background] onConnectError 처리 중 예외: $e');
        service.stopSelf();
      }
    });
  }

  // ★ 에러 해결: late 키워드 사용으로 forward reference 해결
  // 2. 정지 감지 타이머 (5분간 큰 이동 없으면 절전 모드 진입)
  late Function({required bool idle}) startTracking;

  void resetIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(const Duration(minutes: 5), () {
      debugPrint('[Background] 5분간 정지. 절전 모드 진입');
      socket?.disconnect(); // 소켓 연결 끊어 배터리 절약
      startTracking(idle: true); // GPS 주기 완화
    });
  }

  // 3. 위치 추적 시작 함수 (동적 설정)
  startTracking = ({required bool idle}) {
    positionSub?.cancel();
    isIdle = idle;

    if (foregroundActive) {
      positionSub?.cancel();
      positionSub = null;
      socket?.disconnect();
      debugPrint('[Background] foreground active: location stream paused');
      return;
    }

    final settings = idle
        ? AndroidSettings(
            accuracy: LocationAccuracy.low,
            distanceFilter: 75,
            intervalDuration: const Duration(seconds: 60),
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 15,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: "실시간 위치 공유 중",
              notificationText: "백그라운드 위치 추적 모드 활성화",
            ),
          );

    positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
      // 1. 정지 타이머 초기화 (움직임 감지)
      resetIdleTimer();

      // 2. 절전 모드 해제: 현재 리스너가 끝난 뒤 startTracking 호출
      if (isIdle) {
        debugPrint('[Background] 이동 감지! 절전 모드 해제');
        connectSocket();
        Future.microtask(() => startTracking(idle: false));
        return;
      }

      // 2-1. 포그라운드 UI가 활성 상태면 백그라운드 송신은 건너뛴다
      // (UI 소켓이 이미 같은 위치를 전송하므로 중복 방지)
      try {
        await prefs.reload();
      } catch (_) {}
      foregroundActive = prefs.getBool('bg_foreground_active') ?? false;
      if (foregroundActive) {
        prevPos = pos;
        socket?.disconnect();
        return;
      }

      // 3. 배터리 레벨 읽기
      int? batteryLevel;
      try {
        batteryLevel = await battery.batteryLevel;
      } catch (e) {
        debugPrint('[Background] 배터리 레벨 읽기 실패: $e');
        batteryLevel = null;
      }

      // 3-1. 이전 위치와 비교해 실제 이동 여부 판정
      String moveStatus = 'moving';
      if (prevPos != null) {
        final d = Geolocator.distanceBetween(
          prevPos!.latitude,
          prevPos!.longitude,
          pos.latitude,
          pos.longitude,
        );
        moveStatus = d < 2 ? 'stopped' : 'moving';
      }

      // 4. 소켓 전송
      if (socket?.connected == true) {
        socket!.emit('location:update', {
          'sessionId': sessionId,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'speed': pos.speed.isNaN ? null : pos.speed,
          'heading': pos.heading.isNaN ? null : pos.heading,
          'battery': batteryLevel,
          'status': moveStatus,
        });
      }
      prevPos = pos;

      // 5. 지오펜스 판정
      _checkGeofencesInBg(pos, sessionId, prefs, insideGeofences);
    }, onError: (Object error, StackTrace stackTrace) {
      debugPrint('[Background] 위치 스트림 에러: $error');
      positionSub?.cancel();
      idleTimer?.cancel();
      socket?.dispose();
      service.stopSelf();
    }, cancelOnError: true);
  };

  // 외부(FCM)로부터 기상 명령 수신 — service.invoke() 경로 (메인 Isolate용)
  service.on('wakeUp').listen((event) {
    debugPrint('[Background] 기상 명령 수신 (invoke 경로)! 소켓 재연결');
    foregroundActive = false;
    connectSocket();
    startTracking(idle: false);
  });

  service.on('setForegroundActive').listen((event) async {
    final active = event?['active'] == true;
    foregroundActive = active;
    try {
      await prefs.setBool('bg_foreground_active', active);
    } catch (_) {}

    if (active) {
      positionSub?.cancel();
      positionSub = null;
      idleTimer?.cancel();
      socket?.disconnect();
      debugPrint('[Background] foreground handoff: paused background work');
      return;
    }

    debugPrint('[Background] background handoff: resumed tracking');
    connectSocket();
    startTracking(idle: false);
  });

  // SharedPreferences 플래그 폴링 — FCM 백그라운드 핸들러에서 오는 기상 명령용
  // (FCM 핸들러는 별도 Isolate에서 실행되므로 invoke() 대신 플래그를 사용합니다)
  wakeupPollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      await prefs.reload(); // 외부 변경 사항 반영
      final wakeupRequested = prefs.getBool('bg_wakeup_requested') ?? false;
      if (wakeupRequested) {
        await prefs.setBool('bg_wakeup_requested', false); // 플래그 즉시 초기화
        debugPrint('[Background] FCM wakeUp 플래그 감지! 소켓 재연결 및 추적 재개');
        foregroundActive = false;
        await prefs.setBool('bg_foreground_active', false);
        connectSocket();
        startTracking(idle: false);
      }
    } catch (e) {
      debugPrint('[Background] wakeUp 플래그 체크 실패: $e');
    }
  });

  // 서비스 중지 명령이 들어오면 전부 정리하고 종료
  service.on('stopService').listen((event) {
    positionSub?.cancel();
    idleTimer?.cancel();
    wakeupPollTimer?.cancel();
    socket?.dispose();
    service.stopSelf();
    debugPrint('[Background] 서비스 및 소켓 정상 종료');
  });

  // 초기 실행
  if (!foregroundActive) {
    connectSocket();
    startTracking(idle: false);
  } else {
    debugPrint('[Background] started while foreground active; staying paused');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 지오펜스 판정 헬퍼 함수 (Top-level)
// ─────────────────────────────────────────────────────────────────────────────
void _checkGeofencesInBg(Position pos, String sessionId,
    SharedPreferences prefs, Set<String> insideGeofences) {
  final geofenceString = prefs.getString('geofences_$sessionId');
  if (geofenceString != null) {
    try {
      final List<dynamic> geofences = jsonDecode(geofenceString);

      for (final gf in geofences) {
        final double gfLat = gf['lat'] ?? 0.0;
        final double gfLng = gf['lng'] ?? 0.0;
        final double gfRadius = (gf['radius'] ?? 0.0).toDouble();
        final String gfId = gf['id']?.toString() ?? '';
        final String gfName = gf['name']?.toString() ?? '목표 지역';

        double distance = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          gfLat,
          gfLng,
        );

        bool isCurrentlyInside = distance <= gfRadius;
        bool wasInside = insideGeofences.contains(gfId);

        if (isCurrentlyInside && !wasInside) {
          insideGeofences.add(gfId);
          unawaited(_BackgroundGeofenceNotifier()
              .showNotification('지오펜스 진입', '$gfName 영역에 들어왔습니다!'));
        } else if (!isCurrentlyInside && wasInside) {
          insideGeofences.remove(gfId);
          unawaited(_BackgroundGeofenceNotifier()
              .showNotification('지오펜스 이탈', '$gfName 영역을 벗어났습니다.'));
        }
      }
    } catch (e) {
      debugPrint('[Background] 지오펜스 파싱 에러: $e');
    }
  }
}

// background isolate 에서 지오펜스 진입/이탈 시스템 알림을 띄우는 헬퍼.
// NotificationService 는 _isMainIsolate 가드 때문에 background 에서 동작하지
// 않으므로(설계상 main isolate 의 채널 생성/탭 콜백과 분리), 여기서는 채널은
// main isolate (initializeBackgroundService / NotificationService.initForMainIsolate)
// 가 만들어 둔 'geofence_channel' 을 그대로 재사용하고 show() 만 호출한다.
// 탭 콜백은 등록하지 않아 Navigator/Riverpod 등 main-only API 와 충돌하지 않는다.
class _BackgroundGeofenceNotifier {
  _BackgroundGeofenceNotifier._internal();
  static final _BackgroundGeofenceNotifier _instance =
      _BackgroundGeofenceNotifier._internal();
  factory _BackgroundGeofenceNotifier() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[Background] geofence notifier init failed: $e');
    }
  }

  Future<void> showNotification(String title, String body) async {
    if (!_initialized) {
      await init();
    }
    if (!_initialized) {
      debugPrint(
        '[Background] notifier not initialized, dropping notification: $title',
      );
      return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.remainder(0x7fffffff);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'geofence_channel',
        '지오펜스 알림',
        channelDescription: '게임 지오펜스 진입/이탈 알림',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[Background] geofence show failed: $e');
    }
  }
}
