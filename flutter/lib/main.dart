import 'dart:async';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/app_initialization_service.dart';
import 'core/services/background_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/observability_service.dart';
import 'features/game/presentation/game_ui_plugin.dart';
import 'features/game/presentation/plugins/color_chaser/color_chaser_ui_plugin.dart';
import 'features/game/presentation/plugins/fantasy_wars/fantasy_wars_ui_plugin.dart';

void _logUnhandledError(
  String source,
  Object error,
  StackTrace stackTrace,
) {
  debugPrint('[$source] $error');
  debugPrintStack(label: '[$source] stack', stackTrace: stackTrace);
  unawaited(
    ObservabilityService().captureException(
      error,
      stackTrace,
      source: source,
    ),
  );
}

void _registerGamePlugins() {
  GameUiPluginRegistry.register(const FantasyWarsUiPlugin());
  GameUiPluginRegistry.register(const ColorChaserUiPlugin());
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await ObservabilityService().initSentry();
    _registerGamePlugins();

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

    // 좀비 백그라운드 서비스 정리는 *직전 세션이 활성이었던 경우에만* 수행한다.
    // 매 부팅마다 200ms+ 를 소비하면 첫 프레임이 늦어진다 (Choreographer skip 원인).
    // bg_active 플래그를 빠르게 읽어 흔적이 있을 때만 비동기로 정리.
    SharedPreferences? warmPrefs;
    try {
      warmPrefs = await SharedPreferences.getInstance();
    } catch (e, stackTrace) {
      _logUnhandledError('Prefs warmup', e, stackTrace);
    }
    final mayHaveZombieService = warmPrefs?.getBool('bg_active') == true;

    // 첫 프레임 차단을 최소화하기 위해 Sentry 만 동기로 await.
    // (Firebase / NaverMap / Notification / shutdownBg 는 첫 프레임 이후로 미룬다)
    try {
      await ObservabilityService().initSentry();
    } catch (e, stackTrace) {
      _logUnhandledError('Sentry init', e, stackTrace);
    }

    runApp(
      const ProviderScope(
        child: LocationApp(),
      ),
    );

    // 첫 프레임 이후 무거운 초기화를 순차 실행해 메인 스레드 점유를 분산시킨다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initAfterFirstFrame(
        cleanupZombieService: mayHaveZombieService,
      ));
    });
  }, (error, stackTrace) {
    _logUnhandledError('runZonedGuarded', error, stackTrace);
  });
}

/// 첫 프레임이 그려진 뒤 실행되는 무거운 초기화.
/// 각 단계 사이에 마이크로태스크 양보를 주어 UI 프레임이 굶지 않도록 한다.
Future<void> _initAfterFirstFrame({
  required bool cleanupZombieService,
}) async {
  // 1. (필요 시) 좀비 백그라운드 서비스 정리. 흔적이 있을 때만 200ms 소비.
  if (cleanupZombieService) {
    try {
      await shutdownBackgroundService();
    } catch (e, stackTrace) {
      _logUnhandledError('shutdownBackgroundService', e, stackTrace);
    }
  }

  // 각 phase 사이에 한 frame(16ms) 양보 — Firebase/NaverMap/Notification 이
  // 게임 화면 첫 프레임 직후 직렬 await 로 메인 스레드를 점유하면 Davey 가
  // 발생한다. endOfFrame + 짧은 delay 로 분산.
  Future<void> yieldFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  // 2. Firebase: FCM 백그라운드 핸들러 등록 및 Performance 모니터링.
  await yieldFrame();
  try {
    await AppInitializationService().ensureFirebaseInitialized();
  } catch (e, stackTrace) {
    _logUnhandledError('Firebase init', e, stackTrace);
  }
  await yieldFrame();
  try {
    await ObservabilityService().initFirebasePerformance();
  } catch (e, stackTrace) {
    _logUnhandledError('Firebase performance init', e, stackTrace);
  }
  await yieldFrame();
  try {
    FirebaseMessaging.onBackgroundMessage(FcmService.onBackgroundMessage);
    debugPrint('[Startup] FCM background handler registered');
  } catch (e, stackTrace) {
    _logUnhandledError('FCM background handler', e, stackTrace);
  }

  // 3. NaverMap SDK 초기화 — 가장 무거우므로 분리. 캐시되어 있어 맵 화면이
  //    이 함수보다 먼저 ensureNaverMapInitialized() 를 호출해도 동일 future 를 공유.
  await yieldFrame();
  try {
    await AppInitializationService().ensureNaverMapInitialized();
  } catch (e, stackTrace) {
    _logUnhandledError('NaverMap init', e, stackTrace);
  }

  // 4. 알림 채널 생성 (background isolate 의 첫 push 전에 준비).
  await yieldFrame();
  try {
    await NotificationService().initForMainIsolate();
  } catch (e, stackTrace) {
    _logUnhandledError('NotificationService init', e, stackTrace);
  }

  unawaited(AppInitializationService().getPrefs());
}
