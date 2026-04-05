// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart'; // FlutterFire CLI로 생성되는 파일
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'core/services/background_service.dart'; // 백그라운드 서비스 임포트 추가
import 'package:permission_handler/permission_handler.dart';
import 'core/services/fcm_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> requestPermissions() async {
  await Permission.notification.request();
  await Permission.locationAlways.request(); // 백그라운드 알림을 위해 '항상 허용' 필요
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // Firebase 초기화 — 실패해도 앱은 계속 실행
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[Firebase] 초기화 실패: $e');
  }
  // 2. FCM 백그라운드 핸들러 등록 (가장 중요)
  try {
    FirebaseMessaging.onBackgroundMessage(
      FcmService.onBackgroundMessage
    );
  } catch(e){
    debugPrint('FCM 백그라운드 핸들러 등록 실패: $e');
  }
  await requestPermissions(); // 권한 요청
  await FcmService().init();
  // 네이버 맵 초기화 — 실패해도 앱은 계속 실행 ;
  try {
  await FlutterNaverMap().init(
    clientId: 'ir4goe1vir', // 따옴표 필수
    onAuthFailed: (ex) {
      debugPrint("네이버맵 인증 실패 사유: $ex");
    },
  );
  } catch (e) {
    debugPrint('네이버 맵 초기화 에러: $e');
  }
  // 3. 백그라운드 서비스 초기화
  try {
    await initializeBackgroundService();
  } catch (e) {
    debugPrint('백그라운드 서비스 초기화 실패: $e');
  }

  runApp(
    const ProviderScope(
      child: LocationApp(),
    ),
  );
}
