import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'permission_lock.dart';

enum BlePresenceLifecycleState {
  idle,
  unsupported,
  requestingPermission,
  permissionDenied,
  bluetoothUnavailable,
  starting,
  running,
  error,
}

class BlePresenceStatus {
  const BlePresenceStatus({
    required this.state,
    this.message,
  });

  final BlePresenceLifecycleState state;
  final String? message;
}

class BlePresenceSighting {
  const BlePresenceSighting({
    required this.userId,
    required this.rssi,
    required this.seenAtMs,
    required this.deviceId,
  });

  final String userId;
  final int rssi;
  final int seenAtMs;
  final String deviceId;
}

class FantasyWarsBlePresenceService {
  FantasyWarsBlePresenceService._internal();

  static final FantasyWarsBlePresenceService _instance =
      FantasyWarsBlePresenceService._internal();

  factory FantasyWarsBlePresenceService() => _instance;

  static const String serviceUuid =
      '6e65d2f6-8bb5-42fb-9a66-1c4f1b9f4e11';
  static const int _manufacturerId = 0x0FFF;
  static const int _payloadVersion = 1;

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final _sightingsController = StreamController<BlePresenceSighting>.broadcast();
  final _statusController = StreamController<BlePresenceStatus>.broadcast();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<BleStatus>? _statusSub;

  String? _sessionId;
  String? _userId;
  bool _shouldRun = false;
  bool _isRunning = false;
  // hardware error → adapter restart 폭주 차단용.
  DateTime? _lastRestartAt;
  int _consecutiveFailures = 0;
  bool _circuitBroken = false;
  Map<String, String> _tokenToUserId = const {};
  BlePresenceStatus _status =
      const BlePresenceStatus(state: BlePresenceLifecycleState.idle);

  Stream<BlePresenceSighting> get sightings => _sightingsController.stream;
  Stream<BlePresenceStatus> get statuses => _statusController.stream;
  bool get isRunning => _isRunning;
  BlePresenceStatus get status => _status;

  static Future<bool> _isAndroidEmulator() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return !info.isPhysicalDevice;
    } catch (_) {
      return false;
    }
  }

  Future<void> start({
    required String sessionId,
    required String userId,
    required Iterable<String> memberUserIds,
  }) async {
    if (!Platform.isAndroid) {
      _emitStatus(
        BlePresenceLifecycleState.unsupported,
        message: 'Android BLE scanning is only enabled on supported devices.',
      );
      return;
    }

    if (await _isAndroidEmulator()) {
      debugPrint('[FW-BLE] emulator detected — BLE disabled');
      _emitStatus(
        BlePresenceLifecycleState.unsupported,
        message: '에뮬레이터 환경 — BLE 비활성화',
      );
      return;
    }

    final sameIdentity = _sessionId == sessionId && _userId == userId;
    _sessionId = sessionId;
    _userId = userId;
    _tokenToUserId = {
      for (final memberUserId in memberUserIds)
        _tokenFor(sessionId, memberUserId): memberUserId,
    };
    _shouldRun = true;

    if (sameIdentity && _isRunning) {
      return;
    }

    _ensureStatusSubscription();
    _emitStatus(BlePresenceLifecycleState.requestingPermission);
    final granted = await _ensurePermissions();
    if (!granted) {
      _isRunning = false;
      debugPrint('[FW-BLE] permissions denied, BLE presence disabled');
      _emitStatus(
        BlePresenceLifecycleState.permissionDenied,
        message: 'Bluetooth and location permissions are required.',
      );
      return;
    }

    _emitStatus(BlePresenceLifecycleState.starting);
    await _restartIfReady();
  }

  Future<void> stop() async {
    _shouldRun = false;
    _isRunning = false;
    _sessionId = null;
    _userId = null;
    _tokenToUserId = const {};

    await _scanSub?.cancel();
    _scanSub = null;

    try {
      await _peripheral.stop();
    } catch (_) {}

    await _statusSub?.cancel();
    _statusSub = null;
    _emitStatus(BlePresenceLifecycleState.idle);
  }

  /// 권한이 거부된 후 사용자가 시스템 설정에서 권한을 허용한 뒤
  /// UI에서 재시도 버튼을 누를 때 호출. 마지막 start() 인자를 그대로 재사용한다.
  Future<void> retry() async {
    if (_status.state != BlePresenceLifecycleState.permissionDenied
        && _status.state != BlePresenceLifecycleState.bluetoothUnavailable
        && _status.state != BlePresenceLifecycleState.error) {
      return;
    }
    final sessionId = _sessionId;
    final userId = _userId;
    if (sessionId == null || userId == null) {
      return;
    }
    await start(
      sessionId: sessionId,
      userId: userId,
      memberUserIds: _tokenToUserId.values,
    );
  }

  void _ensureStatusSubscription() {
    _statusSub ??= _ble.statusStream.listen((status) {
      if (!_shouldRun || _circuitBroken) {
        return;
      }

      if (status == BleStatus.ready) {
        // adapter 재시작 시 ready 가 빠르게 토글되며 _restartIfReady 가 폭주.
        // 1초 미만 재호출은 무시.
        final now = DateTime.now();
        if (_lastRestartAt != null &&
            now.difference(_lastRestartAt!) < const Duration(seconds: 1)) {
          return;
        }
        _lastRestartAt = now;
        unawaited(_restartIfReady());
        return;
      }

      _isRunning = false;
      unawaited(_scanSub?.cancel() ?? Future<void>.value());
      _scanSub = null;
      _emitStatus(
        BlePresenceLifecycleState.bluetoothUnavailable,
        message: _availabilityMessage(status),
      );
    });
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ];
    // 다른 서비스(Audio, Geolocator)와 동시 요청 시 permission_handler 가
    // race 에러를 던지므로 전역 lock 으로 직렬화.
    return PermissionLock.run(() async {
      try {
        final results = await permissions.request();
        return results.values.every((status) => status.isGranted);
      } catch (e) {
        debugPrint('[BLE] permission request failed: $e');
        return false;
      }
    });
  }

  Future<void> _restartIfReady() async {
    if (!_shouldRun ||
        _circuitBroken ||
        _sessionId == null ||
        _userId == null) {
      return;
    }
    if (_ble.status != BleStatus.ready) {
      _emitStatus(
        BlePresenceLifecycleState.bluetoothUnavailable,
        message: _availabilityMessage(_ble.status),
      );
      return;
    }

    final advertisingReady = await _startAdvertising();
    final scanningReady = await _startScanning();
    _isRunning = advertisingReady && scanningReady;

    if (!_isRunning) {
      // 연속 실패 3회면 회로 차단 — 이 세션 동안 BLE 재시도 중단.
      // 에뮬레이터 / 어댑터 불안정 환경에서 Hardware Error 무한 루프 차단.
      _consecutiveFailures += 1;
      if (_consecutiveFailures >= 3) {
        _circuitBroken = true;
        debugPrint(
            '[FW-BLE] circuit broken after 3 failures — disabling BLE for this session');
        _emitStatus(
          BlePresenceLifecycleState.error,
          message: 'BLE 어댑터 불안정 — 이 세션에서 BLE 비활성화',
        );
        return;
      }
    } else {
      _consecutiveFailures = 0;
    }

    _emitStatus(
      _isRunning
          ? BlePresenceLifecycleState.running
          : BlePresenceLifecycleState.error,
      message: _isRunning
          ? 'BLE proximity scanning is active.'
          : 'BLE proximity could not be started cleanly.',
    );
  }

  Future<bool> _startAdvertising() async {
    final sessionId = _sessionId;
    final userId = _userId;
    if (sessionId == null || userId == null) {
      return false;
    }

    final AdvertiseData advertiseData;
    try {
      advertiseData = AdvertiseData(
        serviceUuid: serviceUuid,
        localName: _localNameFor(userId),
        manufacturerId: _manufacturerId,
        manufacturerData: Uint8List.fromList(
          _payloadBytesFor(sessionId, userId),
        ),
      );
    } catch (e) {
      // payload 생성 실패 시 advertising 자체 포기 (무한 재시도 방지).
      debugPrint('[FW-BLE] advertise data build failed: $e');
      return false;
    }

    final settings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
      timeout: 0,
    );

    try {
      await _peripheral.stop();
    } catch (_) {}

    try {
      // hardware error / adapter restart 시 native 측이 응답 없이 hang 되는 경우
      // 가 있어 5초 timeout 으로 강제 cut. 다음 status 변동에서 재시도된다 (백오프 적용).
      await _peripheral
          .start(
            advertiseData: advertiseData,
            advertiseSettings: settings,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('BLE advertise start timeout');
            },
          );
      return true;
    } catch (error) {
      debugPrint('[FW-BLE] advertise start failed: $error');
      _emitStatus(
        BlePresenceLifecycleState.error,
        message: 'BLE advertising could not be started.',
      );
      return false;
    }
  }

  Future<bool> _startScanning() async {
    await _scanSub?.cancel();
    try {
      _scanSub = _ble
          .scanForDevices(
            withServices: [Uuid.parse(serviceUuid)],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled: true,
          )
          .listen(
            _handleScanResult,
            onError: (Object error) {
              _isRunning = false;
              debugPrint('[FW-BLE] scan failed: $error');
              _emitStatus(
                BlePresenceLifecycleState.error,
                message: 'BLE scanning failed while running.',
              );
            },
          );
      return true;
    } catch (error) {
      debugPrint('[FW-BLE] scan start failed: $error');
      _emitStatus(
        BlePresenceLifecycleState.error,
        message: 'BLE scanning could not be started.',
      );
      return false;
    }
  }

  void _handleScanResult(DiscoveredDevice device) {
    final userId = _resolveUserId(device);
    if (userId == null || userId == _userId) {
      return;
    }

    _sightingsController.add(
      BlePresenceSighting(
        userId: userId,
        rssi: device.rssi,
        seenAtMs: DateTime.now().millisecondsSinceEpoch,
        deviceId: device.id,
      ),
    );
  }

  String? _resolveUserId(DiscoveredDevice device) {
    if (device.manufacturerData.length < 11) {
      return null;
    }

    final payload = device.manufacturerData.sublist(2);
    if (payload.length < 9 ||
        payload[0] != 0x46 ||
        payload[1] != 0x57 ||
        payload[2] != _payloadVersion) {
      return null;
    }

    final tokenHex = _bytesToHex(payload.sublist(3));
    return _tokenToUserId[tokenHex];
  }

  String _localNameFor(String userId) {
    final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final suffix = safeUserId.length <= 8
        ? safeUserId
        : safeUserId.substring(safeUserId.length - 8);
    return 'FW$suffix';
  }

  List<int> _payloadBytesFor(String sessionId, String userId) {
    return <int>[
      0x46,
      0x57,
      _payloadVersion,
      ..._hexToBytes(_tokenFor(sessionId, userId)),
    ];
  }

  String _tokenFor(String sessionId, String userId) {
    final input = '$sessionId:$userId';
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;

    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & mask;
    }

    // Dart int 은 64-bit signed 라 mask 후에도 음수가 될 수 있음.
    // toRadixString(16) 이 음수면 "-..." 접두사를 붙여 잘못된 hex 가 되므로
    // 항상 unsigned 로 변환.
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  List<int> _hexToBytes(String value) {
    // 비-hex 문자 (음수 부호 등) 가 들어와도 robust 하게: 정규식으로 제거.
    // 홀수 길이 시 앞에 0 패딩 (substring RangeError 방지).
    final cleaned = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final normalized = cleaned.length.isOdd ? '0$cleaned' : cleaned;
    final bytes = <int>[];
    for (var index = 0; index + 2 <= normalized.length; index += 2) {
      bytes.add(int.parse(normalized.substring(index, index + 2), radix: 16));
    }
    return bytes;
  }

  String _bytesToHex(List<int> value) {
    final buffer = StringBuffer();
    for (final byte in value) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  void _emitStatus(
    BlePresenceLifecycleState state, {
    String? message,
  }) {
    final next = BlePresenceStatus(state: state, message: message);
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  String _availabilityMessage(BleStatus status) {
    switch (status.name) {
      case 'unauthorized':
        return 'Bluetooth permission is not granted.';
      case 'poweredOff':
        return 'Bluetooth is turned off.';
      case 'locationServicesDisabled':
        return 'Location services are turned off.';
      case 'unsupported':
        return 'BLE is not supported on this device.';
      default:
        return 'Bluetooth availability needs attention.';
    }
  }
}
