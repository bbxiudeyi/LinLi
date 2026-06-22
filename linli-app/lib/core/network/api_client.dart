import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后端 API 基础地址。
/// - Android 模拟器访问本机后端用 `10.0.2.2`（模拟器的 host loopback）
/// - 真机调试用电脑局域网 IP，如 `http://192.168.x.x:8080`
/// - 生产环境改为正式域名
const String _kBaseUrl = kReleaseMode
    ? 'https://www.bbtech.com/api/v1'
    : 'http://10.0.2.2:8080/api/v1';

const String _kTokenKey = 'linli_jwt_token';

/// 全局 dio 实例（单例）。
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio dio;

  Future<void> init() async {
    dio = Dio(BaseOptions(
      baseUrl: _kBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // 请求拦截器：自动带 JWT
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _loadToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<String?> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }
}
