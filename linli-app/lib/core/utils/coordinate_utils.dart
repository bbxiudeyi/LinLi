import 'dart:math';

/// WGS-84 → GCJ-02 (国测局坐标)
/// 高德地图使用 GCJ-02 坐标系
class CoordinateUtils {
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  static bool _outOfChina(double lat, double lng) {
    return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret +=
        (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret =
        300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret +=
        (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }

  /// WGS-84 转 GCJ-02
  static (double lat, double lng) wgs84ToGcj02(
      double wgsLat, double wgsLng) {
    if (_outOfChina(wgsLat, wgsLng)) return (wgsLat, wgsLng);

    var dLat = _transformLat(wgsLng - 105.0, wgsLat - 35.0);
    var dLng = _transformLng(wgsLng - 105.0, wgsLat - 35.0);
    final radLat = wgsLat / 180.0 * pi;
    var magic = sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * pi);
    return (wgsLat + dLat, wgsLng + dLng);
  }
}
