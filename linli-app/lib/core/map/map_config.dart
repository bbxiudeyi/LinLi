/// 地图服务配置集中管理。
///
/// 已从 Mapbox 云服务迁移到自托管的 pixelmap 地图服务（基于 MapLibre + tileserver-gl）。
/// 不再需要 access token，地图数据完全来自自有服务器。
class MapConfig {
  MapConfig._();

  /// pixelmap 自托管地图服务的样式 URL。
  ///
  /// - 模拟器：用 127.0.0.1 + adb reverse tcp:8080 tcp:8080 转发
  /// - 真机：用电脑局域网 IP（如 http://192.168.x.x:8080/...）
  /// - 生产：改为公网域名
  static const String styleUrl =
      'http://127.0.0.1:8080/styles/pixel/style.json';

  /// 地图默认中心点（摩纳哥，测试数据范围）。
  /// 切换到中国数据后应改为目标城市坐标，如北京 [116.4074, 39.9042]。
  static const double defaultCenterLng = 7.42;
  static const double defaultCenterLat = 43.74;
  static const double defaultZoom = 13.0;
}
