/// 自建地图服务配置（MapLibre + 自建瓦片，无需 token）。
///
/// 服务地址：map.bbtech.top（已上线，HTTPS 公网可访问）。
/// 客户端只需加载 [styleUri]，瓦片 / 字体会自动从服务端拉取。
class MapConfig {
  MapConfig._();

  /// 自建 outdoor 底图样式。
  static const String styleUri =
      'https://map.bbtech.top/styles/outdoor/style.json';

  /// 自建服务永久可用，视为已配置。
  static const bool isConfigured = true;
}
