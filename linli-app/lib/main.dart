import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'core/database/local_db.dart';
import 'core/map/mapbox_config.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 本地数据库初始化（sqflite，替代 Supabase）
  await LocalDb.initialize();

  // Mapbox：必须在任何 MapWidget 创建前设置 access token
  if (MapboxConfig.isConfigured) {
    MapboxOptions.setAccessToken(MapboxConfig.publicToken);
  }

  runApp(const ProviderScope(child: TujiApp()));
}
