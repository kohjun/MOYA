// lib/core/services/fcm_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  Future<void> init() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 알림 권한 요청
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // 토큰 획득 (서버 전송용)
    String? token = await messaging.getToken();
    debugPrint('[FCM] Token: $token');

    // 포그라운드 메시지 핸들링
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] 포그라운드 메시지 수신: ${message.data}');
    });
  }

  // ★ 백그라운드 메시지 핸들러 (최상단 함수여야 함)
  @pragma('vm:entry-point')
  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] 백그라운드 데이터 메시지 수신: ${message.data}');

    // 서버에서 {"type": "wakeUp"} 데이터를 보냈을 경우
    if (message.data['type'] == 'wakeUp') {
      // 실행 중인 백그라운드 서비스에 'wakeUp' 이벤트 전달
      FlutterBackgroundService().invoke('wakeUp');
    }
  }
}