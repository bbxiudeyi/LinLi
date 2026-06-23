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

  /// 内存中的 token 副本。
  /// [init] 时从磁盘加载，[saveToken]/[clearToken] 同步维护，
  /// 供 GoRouter 的 redirect（同步、不能 await）判断登录态。
  String? _token;
  bool _initialized = false;

  /// 当前是否持有 token（同步，供路由守卫使用）。
  /// 必须在 [init] 完成后调用，否则恒为 false。
  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;

    dio = Dio(BaseOptions(
      baseUrl: _kBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // 启动时把磁盘上的 token 读到内存（路由守卫同步判断要用）
    _token = await _loadToken();
    _initialized = true;

    // 请求拦截器：直接用内存 token，避免每次请求都读磁盘
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && _token!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
    ));

    // 响应拦截器：401 表示 token 失效（过期 / 被撤销），清掉本地态。
    // 不在这里跳转，交给路由守卫在下次导航时把用户导回登录页。
    dio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) {
        if (e.response?.statusCode == 401) {
          _token = null;
          // 清磁盘是 fire-and-forget，不阻塞错误传播
          SharedPreferences.getInstance()
              .then((prefs) => prefs.remove(_kTokenKey));
        }
        handler.next(e);
      },
    ));
  }

  Future<String?> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  Future<void> saveToken(String token) async {
    _token = token; // 同步更新内存，保证守卫立刻可见
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
  }

  Future<void> clearToken() async {
    _token = null; // 同步更新内存
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }
}
