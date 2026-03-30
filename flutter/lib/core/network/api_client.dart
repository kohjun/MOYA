// lib/core/network/api_client.dart

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _baseUrl = 'http://localhost:3000';  // 개발 서버 (배포 시 변경)

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    // ── 인터셉터 등록 ─────────────────────────────────────────────────
    _dio.interceptors.add(InterceptorsWrapper(
      // 요청 시: 저장된 Access Token 자동 주입
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },

      // 에러 시: 401이면 토큰 갱신 후 재요청
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final errorCode = error.response?.data?['error'];

          // 토큰 만료 → 자동 갱신 시도
          if (errorCode == 'TOKEN_EXPIRED') {
            try {
              await _refreshAccessToken();

              // 갱신된 토큰으로 원래 요청 재시도
              final retryOptions = error.requestOptions;
              final newToken = await _storage.read(key: 'access_token');
              retryOptions.headers['Authorization'] = 'Bearer $newToken';

              final retryResponse = await _dio.fetch(retryOptions);
              return handler.resolve(retryResponse);
            } catch (refreshError) {
              // 갱신 실패 → 로그아웃 처리
              await clearTokens();
              return handler.reject(error);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HTTP 메서드 래퍼
  // ─────────────────────────────────────────────────────────────────────────
  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) =>
      _dio.get(path, queryParameters: queryParams);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);

  // ─────────────────────────────────────────────────────────────────────────
  // 토큰 관리
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> saveTokens({required String accessToken}) async {
    await _storage.write(key: 'access_token', value: accessToken);
  }

  Future<void> clearTokens() async {
    await _storage.deleteAll();
  }

  Future<String?> getAccessToken() => _storage.read(key: 'access_token');

  // Refresh Token으로 Access Token 갱신
  // Refresh Token은 HttpOnly 쿠키로 서버가 관리 → 클라이언트는 /auth/refresh만 호출
  Future<void> _refreshAccessToken() async {
    // withCredentials: true → 쿠키 자동 전송
    final response = await Dio(BaseOptions(baseUrl: _baseUrl))
        .post('/auth/refresh', options: Options(extra: {'withCredentials': true}));

    final newAccessToken = response.data['accessToken'] as String;
    await saveTokens(accessToken: newAccessToken);
  }
}
