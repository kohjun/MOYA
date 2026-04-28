// 모든 permission_handler 호출을 직렬화하는 in-process mutex.
//
// permission_handler 패키지는 권한 요청이 동시 진행 중일 때 다음 호출을
// `A request for permissions is already running` 에러로 거부한다.
// 앱에는 BLE / 마이크 / 위치 등 여러 권한 요청이 거의 동시에 발생하므로,
// 모든 호출을 단일 lock 으로 감싸 race 를 차단한다.

import 'dart:async';

class PermissionLock {
  static Future<dynamic>? _chain;

  /// permission_handler 호출을 직렬화한다.
  /// 이전 작업의 성공/실패와 무관하게 다음 작업이 실행된다.
  static Future<T> run<T>(Future<T> Function() task) {
    final previous = _chain ?? Future<void>.value();
    final result = previous.then<T>((_) => task(), onError: (_) => task());
    _chain = result;
    return result;
  }
}
