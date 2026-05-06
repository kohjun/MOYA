import 'dart:async';

import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class ObservabilityService {
  ObservabilityService._internal();

  static final ObservabilityService _instance =
      ObservabilityService._internal();

  factory ObservabilityService() => _instance;

  static const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static const _sentryTraceSampleRateEnv = String.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_RATE',
    defaultValue: '0.2',
  );
  static const _firebasePerfEnabled = bool.fromEnvironment(
    'FIREBASE_PERFORMANCE_ENABLED',
    defaultValue: true,
  );

  bool _sentryReady = false;
  bool _firebasePerformanceReady = false;

  bool get isSentryReady => _sentryReady;
  bool get isFirebasePerformanceReady => _firebasePerformanceReady;

  Future<void> initSentry() async {
    if (_sentryReady || _sentryDsn.isEmpty) {
      return;
    }

    const isDev = kDebugMode || _appEnv == 'dev' || _appEnv == 'development';

    await SentryFlutter.init((options) {
      options.dsn = _sentryDsn;
      options.environment = _appEnv;
      options.tracesSampleRate = double.tryParse(_sentryTraceSampleRateEnv) ??
          (isDev ? 0.05 : 0.2);
      options.enableAutoSessionTracking = true;
      options.attachScreenshot = false;
      // Sentry SDK 자체 디버그 로그를 끈다. (debug 모드 기본값이 true 라 logcat 을
      // "Unable to find scroll/click target" 같은 라인으로 가득 채운다.)
      options.debug = false;
      options.diagnosticLevel = SentryLevel.warning;
      // dev 빌드에서는 사용자 인터랙션 자동 추적도 끈다. 게임 화면 위 GestureDetector
      // 가 많아 매 탭마다 클릭 타겟을 찾지 못해 디버그 로그가 누적되고
      // 메인 스레드 마이크로 jank 의 원인이 된다.
      if (isDev) {
        options.enableUserInteractionTracing = false;
        options.enableUserInteractionBreadcrumbs = false;
        options.enableAutoPerformanceTracing = false;
      }
    });
    _sentryReady = true;
  }

  Future<void> initFirebasePerformance() async {
    try {
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(
        _firebasePerfEnabled,
      );
      _firebasePerformanceReady = _firebasePerfEnabled;
    } catch (error) {
      _firebasePerformanceReady = false;
      debugPrint('[APM] Firebase Performance init skipped: $error');
    }
  }

  Future<void> captureException(
    Object error,
    StackTrace stackTrace, {
    String? source,
    Map<String, String> tags = const {},
  }) async {
    if (!_sentryReady) {
      return;
    }

    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (source != null) {
          scope.setTag('source', _sanitizeValue(source));
        }
        for (final entry in tags.entries) {
          scope.setTag(_sanitizeKey(entry.key), _sanitizeValue(entry.value));
        }
      },
    );
  }

  Future<T> traceAsync<T>(
    String name,
    Future<T> Function() action, {
    String operation = 'task',
    Map<String, String> attributes = const {},
    Map<String, int> metrics = const {},
    bool captureErrors = true,
  }) async {
    final sanitizedName = _sanitizeTraceName(name);
    final stopwatch = Stopwatch()..start();
    final sentrySpan =
        _sentryReady ? Sentry.startTransaction(sanitizedName, operation) : null;
    final firebaseTrace = _firebasePerformanceReady
        ? FirebasePerformance.instance.newTrace(sanitizedName)
        : null;

    try {
      if (firebaseTrace != null) {
        for (final entry in attributes.entries) {
          firebaseTrace.putAttribute(
            _sanitizeKey(entry.key),
            _sanitizeValue(entry.value),
          );
        }
        await firebaseTrace.start();
      }

      final result = await action();
      firebaseTrace?.putAttribute('ok', 'true');
      return result;
    } catch (error, stackTrace) {
      firebaseTrace?.putAttribute('ok', 'false');
      firebaseTrace?.putAttribute('error_type', error.runtimeType.toString());
      if (captureErrors) {
        unawaited(captureException(error, stackTrace, source: sanitizedName));
      }
      rethrow;
    } finally {
      stopwatch.stop();
      firebaseTrace?.setMetric('duration_ms', stopwatch.elapsedMilliseconds);
      for (final entry in metrics.entries) {
        firebaseTrace?.setMetric(_sanitizeKey(entry.key), entry.value);
      }
      await firebaseTrace?.stop();
      await sentrySpan?.finish();
    }
  }

  String socketTraceName(String event) {
    final normalized =
        event.replaceAll(':', '_').replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return 'socket.$normalized';
  }

  String _sanitizeTraceName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (sanitized.isEmpty) {
      return 'trace';
    }
    return sanitized.length <= 100 ? sanitized : sanitized.substring(0, 100);
  }

  String _sanitizeKey(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (sanitized.isEmpty) {
      return 'key';
    }
    return sanitized.length <= 40 ? sanitized : sanitized.substring(0, 40);
  }

  String _sanitizeValue(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    return sanitized.length <= 100 ? sanitized : sanitized.substring(0, 100);
  }
}
