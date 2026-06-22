import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'core/database/local_db.dart';
import 'core/map/mapbox_config.dart';
import 'core/network/api_client.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 本地数据库初始化（保留作为离线缓存）
  await LocalDb.initialize();

  // 网络客户端初始化（dio + JWT 拦截器）
  await ApiClient.instance.init();

  // Mapbox：必须在任何 MapWidget 创建前设置 access token
  if (MapboxConfig.isConfigured) {
    MapboxOptions.setAccessToken(MapboxConfig.publicToken);
  }

  runApp(const ProviderScope(child: TujiApp()));
}
