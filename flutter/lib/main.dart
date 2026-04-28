import 'dart:async';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/app_initialization_service.dart';
import 'core/services/background_service.dart';
import 'core/services/fcm_service.dart';
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
}

void _registerGamePlugins() {
  GameUiPluginRegistry.register(const FantasyWarsUiPlugin());
  GameUiPluginRegistry.register(const ColorChaserUiPlugin());
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
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

    // 이전 세션이 비정상 종료되어 sticky foreground service가 부활한 경우,
    // 새 엔진이 메인 부팅과 동시에 돌면서 main isolate 전용 플러그인 등록이 실패하고
    // 프레임이 100+ 개 스킵된다. 어떤 초기화보다 먼저 좀비 서비스를 정리한다.
    try {
      await shutdownBackgroundService();
    } catch (e, stackTrace) {
      _logUnhandledError('shutdownBackgroundService', e, stackTrace);
    }

    // Firebase 초기화 — FCM 백그라운드 핸들러 등록 및 모든 Firebase API 사용 전 필수
    try {
      await AppInitializationService().ensureFirebaseInitialized();
    } catch (e, stackTrace) {
      _logUnhandledError('Firebase init', e, stackTrace);
    }

    try {
      FirebaseMessaging.onBackgroundMessage(FcmService.onBackgroundMessage);
      debugPrint('[Startup] FCM background handler registered');
    } catch (e, stackTrace) {
      _logUnhandledError('FCM background handler', e, stackTrace);
    }

    // NaverMap SDK 초기화 (NaverMap 위젯 렌더링 전에 반드시 완료되어야 함)
    try {
      await AppInitializationService().ensureNaverMapInitialized();
    } catch (e, stackTrace) {
      _logUnhandledError('NaverMap init', e, stackTrace);
    }

    // SharedPreferences를 첫 프레임 전에 미리 warm-up합니다.
    unawaited(() async {
      try {
        await AppInitializationService().getPrefs();
      } catch (error, stackTrace) {
        _logUnhandledError('PrefsWarmup', error, stackTrace);
      }
    }());

    runApp(
      const ProviderScope(
        child: LocationApp(),
      ),
    );
  }, (error, stackTrace) {
    _logUnhandledError('runZonedGuarded', error, stackTrace);
  });
}
