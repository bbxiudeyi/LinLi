import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/db/local_db.dart';
import 'core/network/api_client.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 网络客户端初始化（dio + JWT 拦截器）
  await ApiClient.instance.init();

  // 本地数据库初始化（离线存储）
  await LocalDb.instance.init();

  // 注：MapLibre 自建瓦片无需 token，不需要全局初始化

  runApp(const ProviderScope(child: TujiApp()));
}
