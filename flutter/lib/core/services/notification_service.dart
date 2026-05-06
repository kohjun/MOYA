// lib/core/services/notification_service.dart
//
// NotificationService 는 main isolate 와 background isolate 양쪽에서 호출된다.
// 두 isolate 의 메모리는 분리되어 있으므로 각각 별도로 init 해야 한다.
//
//   - main isolate  → initForMainIsolate(): 채널 생성 + (필요 시) 탭 콜백 등록
//   - background    → initForBackgroundIsolate(): show() 만 가능하도록 최소 init
//
// 두 init 모두 _initialized 플래그로 가드되어 같은 isolate 안에서 중복 호출되어도
// flutter_local_notifications 의 native 초기화는 한 번만 실행된다.
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // 같은 isolate 안에서의 중복 init 가드.
  // 다른 isolate 에서는 별도 인스턴스이므로 각자 자기 init 을 한 번씩 거친다.
  bool _initialized = false;
  bool get _isMainIsolate =>
      Isolate.current.debugName == 'main' ||
      PlatformDispatcher.instance.implicitView != null;

  /// main isolate 전용 init.
  /// - 알림 채널을 명시적으로 미리 생성
  /// - (필요 시) 탭 콜백을 여기서만 등록 — Navigator/Riverpod 같은 main-only API 사용 가능
  Future<void> initForMainIsolate() async {
    if (!_isMainIsolate) {
      debugPrint(
        '[NotificationService] initForMainIsolate skipped outside main isolate',
      );
      return;
    }
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      // 향후 알림 탭 → Navigator.push 가 필요하면 여기에 등록.
      // background isolate 와 달리 main 에서만 안전하게 동작한다.
      // onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // 채널 사전 생성 — 첫 push 호출 시 자동 생성에 의존하지 않는다.
    // (background isolate 에서 show() 가 호출되어도 채널이 이미 존재해야 한다.)
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'geofence_channel',
        '지오펜스 알림',
        description: '게임 지오펜스 진입/이탈 알림',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// background isolate 전용 init.
  /// - 콜백 등록 금지 (Navigator/Riverpod 등 main-only API 가 호출되면 안 됨)
  /// - 채널 생성도 하지 않음 (main isolate 가 이미 만들어 둠)
  /// - 오직 show() 호출만 가능하도록 최소 초기화
  Future<void> initForBackgroundIsolate() async {
    if (!_isMainIsolate) {
      debugPrint(
        '[NotificationService] background isolate local notification init skipped',
      );
      return;
    }
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// 기존 코드와의 호환을 위한 thin wrapper.
  /// 새 코드는 initForMainIsolate / initForBackgroundIsolate 를 직접 사용한다.
  @Deprecated('Use initForMainIsolate() or initForBackgroundIsolate() instead')
  Future<void> init() => initForBackgroundIsolate();

  Future<void> showNotification(String title, String body) async {
    if (!_isMainIsolate) {
      debugPrint(
        '[NotificationService] local notification skipped outside main isolate: $title',
      );
      return;
    }
    if (!_initialized) {
      await initForMainIsolate();
    }

    final notificationId =
        DateTime.now().microsecondsSinceEpoch.remainder(0x7fffffff);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'geofence_channel',
        '지오펜스 알림',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _notifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
