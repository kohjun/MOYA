const String APP_NAME = 'mediasoup-client';

typedef void LoggerDebug(dynamic message);

// debug 로그를 활성화하려면 true로 변경
const bool _kDebugLogging = false;

class Logger {
  final String? _prefix;

  late LoggerDebug debug;
  late LoggerDebug warn;
  late LoggerDebug error;

  Logger(this._prefix) {
    if (_prefix != null) {
      debug = _kDebugLogging
          ? (dynamic message) => print('$APP_NAME:$_prefix $message')
          : (_) {};
      warn = (dynamic message) {
        print('$APP_NAME:WARN:$_prefix $message');
      };
      error = (dynamic message) {
        print('$APP_NAME:ERROR:$_prefix $message');
      };
    } else {
      debug = _kDebugLogging
          ? (dynamic message) => print('$APP_NAME $message')
          : (_) {};
      warn = (dynamic message) {
        print('$APP_NAME:WARN $message');
      };
      error = (dynamic message) {
        print('$APP_NAME:ERROR $message');
      };
    }
  }
}
