/// Mapbox 配置集中管理。
///
/// Public Token 通过 `--dart-define=MAPBOX_PUBLIC_TOKEN=pk.xxx` 传入，
/// 避免硬编码进源码。
class MapboxConfig {
  MapboxConfig._();

  /// Mapbox Public Access Token（pk. 开头）。
  /// 优先用 --dart-define=MAPBOX_PUBLIC_TOKEN 传入；未传时用下方默认值。
  static const String publicToken =
      String.fromEnvironment(
        'MAPBOX_PUBLIC_TOKEN',
        defaultValue: 'pk.YOUR_MAPBOX_PUBLIC_TOKEN_HERE',
      );

  /// 默认地图样式 URL（Mapbox Streets，适合运动轨迹展示）。
  static const String defaultStyleUri =
      'mapbox://styles/mapbox/streets-v12';

  /// 是否已配置有效 token。
  static bool get isConfigured => publicToken.isNotEmpty;
}
