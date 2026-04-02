// lib/core/services/fcm_service.dart
//
// ════════════════════════════════════════════════════════════════
// Firebase Cloud Messaging (FCM) 서비스
//
// [초기 설정 가이드]
// 1. Firebase 콘솔(https://console.firebase.google.com) 접속
// 2. 프로젝트 만들기 → 앱 추가 → Android 선택
// 3. 패키지 이름: com.example.location_sharing_app 입력
// 4. google-services.json 다운로드 → android/app/ 폴더에 복사
// 5. 콘솔 → 프로젝트 설정 → 서비스 계정 → Firebase Admin SDK
//    → 새 비공개 키 생성 → serviceAccountKey.json 다운로드
//    → backend/ 폴더에 복사 (절대 git에 올리지 말 것!)
// ════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/material.dart' show Color;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Android 고우선순위 알림 채널 (SOS용)
  static const _sosChannelId = 'sos_channel';
  static const _sosChannelName = 'SOS 긴급 알림';

  // 일반 알림 채널
  static const _defaultChannelId = 'default_channel';
  static const _defaultChannelName = '위치 공유 알림';

  // ── 초기화 ────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    // 알림 권한 요청
    await _requestPermission();

    // 로컬 알림 초기화 (포그라운드 알림 표시용)
    await _initLocalNotifications();

    // 포그라운드 메시지 수신 처리
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 알림 탭으로 앱 열린 경우 처리
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 앱이 종료된 상태에서 알림으로 열린 경우
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // FCM 토큰 발급 및 서버 등록
    await _registerToken();

    // 토큰 갱신 시 자동 재등록
    _messaging.onTokenRefresh.listen((newToken) {
      _uploadToken(newToken);
    });
  }

  // ── 알림 권한 요청 ────────────────────────────────────────────────────────
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // iOS 방해 금지 모드 무시 (긴급)
    );

    // Android 13+ 는 permission_handler로 POST_NOTIFICATIONS 권한 요청 필요
    // (AndroidManifest.xml에 선언 후 런타임 요청)
    if (Platform.isAndroid) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  // ── 로컬 알림 초기화 ──────────────────────────────────────────────────────
  Future<void> _initLocalNotifications() async {
    // Android 알림 채널 생성
    const androidSosChannel = AndroidNotificationChannel(
      _sosChannelId,
      _sosChannelName,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const androidDefaultChannel = AndroidNotificationChannel(
      _defaultChannelId,
      _defaultChannelName,
      importance: Importance.high,
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidSosChannel);
    await androidPlugin?.createNotificationChannel(androidDefaultChannel);

    // 플러그인 초기화
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // 알림 탭 처리 (필요 시 라우팅 추가)
      },
    );
  }

  // ── 포그라운드 메시지 처리 ────────────────────────────────────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];

    // SOS 알림: 고우선순위로 표시
    if (type == 'sos_alert') {
      await _showSosNotification(
        title: message.notification?.title ?? 'SOS 긴급 알림',
        body: message.notification?.body ?? '멤버가 긴급 상황을 알렸습니다.',
        data: data,
      );
      return;
    }

    // 일반 알림
    if (message.notification != null) {
      await _showDefaultNotification(
        title: message.notification!.title ?? '위치 공유',
        body: message.notification!.body ?? '',
        data: data,
      );
    }
  }

  // ── 알림 탭 처리 ─────────────────────────────────────────────────────────
  void _handleNotificationTap(RemoteMessage message) {
    // 필요 시 GoRouter로 특정 화면으로 이동
    // 예: SOS 알림 탭 → 지도 화면으로 이동
  }

  // ── SOS 알림 표시 ────────────────────────────────────────────────────────
  Future<void> _showSosNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _sosChannelId,
      _sosChannelName,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,  // 화면 잠금 상태에서도 표시
      playSound: true,
      enableVibration: true,
      color: Color(0xFFFF0000), // 빨간색
    );

    await _localNotifications.show(
      0,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  // ── 일반 알림 표시 ───────────────────────────────────────────────────────
  Future<void> _showDefaultNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _defaultChannelId,
      _defaultChannelName,
      importance: Importance.high,
      priority: Priority.high,
    );

    await _localNotifications.show(
      1,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  // ── FCM 토큰 발급 및 서버 등록 ──────────────────────────────────────────
  Future<void> _registerToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _uploadToken(token);
    }
  }

  // POST /auth/fcm-token → 서버에 토큰 저장
  Future<void> _uploadToken(String token) async {
    try {
      final client = ApiClient();
      await client.post('/auth/fcm-token', data: {'fcm_token': token});
    } catch (_) {
      // 토큰 등록 실패는 조용히 무시 (다음 앱 시작 시 재시도)
    }
  }
}
