// lib/main.dart

import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

void _logUnhandledError(
  String source,
  Object error,
  StackTrace stackTrace,
) {
  debugPrint('[$source] $error');
  debugPrintStack(label: '[$source] stack', stackTrace: stackTrace);
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logUnhandledError(
      'FlutterError',
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _logUnhandledError('PlatformDispatcher', error, stackTrace);
    return false;
  };

  ErrorWidget.builder = (details) {
    _logUnhandledError(
      'ErrorWidget',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    return Material(
      color: Colors.red.shade50,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'A rendering error occurred.\n${details.exception}',
            style: const TextStyle(color: Colors.black87),
          ),
        ),
      ),
    );
  };


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

  // 앱 시작 시 bg_active 플래그 초기화
  // (크래시로 종료된 이전 세션의 stale true 값을 정리)
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_active', false);
  } catch (e) {
    debugPrint('bg_active 초기화 실패: $e');
  }

    runApp(
      const ProviderScope(
        child: LocationApp(),
      ),
    );
  }, (error, stackTrace) {
    _logUnhandledError('runZonedGuarded', error, stackTrace);
  });
}
