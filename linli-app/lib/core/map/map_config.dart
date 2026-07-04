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

  /// 地图默认中心点（成都）。
  /// 无轨迹数据时地图定位到这里。
  static const double defaultCenterLng = 104.0668;
  static const double defaultCenterLat = 30.6634;
  static const double defaultZoom = 11.0;
}
