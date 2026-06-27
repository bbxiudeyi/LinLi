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

  // 注：地图使用 MapLibre 开源 SDK + 自托管 pixelmap 服务，
  // 不需要像 Mapbox 那样在启动时设置 access token。

  runApp(const ProviderScope(child: TujiApp()));
}
