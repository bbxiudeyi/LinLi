import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// 基于 geolocator 的定位服务封装。
///
/// 统一处理权限申请、服务检测、位置流获取，
/// 把平台差异收口在这里，上层 [GpsTrackerNotifier] 只关心业务。
class LocationService {
  LocationService._();

  /// 确保定位所需的前置条件满足：
  /// 1. 定位服务已开启
  /// 2. 拥有精确定位权限
  ///
  /// 不满足会抛 [LocationException]，调用方应 catch 并向用户提示。
  static Future<void> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException('定位服务未开启，请在系统设置中打开定位');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('定位权限被拒绝');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('定位权限被永久拒绝，请在系统设置中手动授予');
    }
  }

  /// 主动获取一次当前位置（不等流）。
  /// 用于进入录制页时立即定位，避免显示默认初始视野。
  static Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  /// 返回运动场景的位置流。
  ///
  /// - [distanceFilterMeters]：移动超过该距离才回调，省电。0 = 尽可能频繁。
  /// - [intervalMs]：Android 上两次定位的最小间隔。
  static Stream<Position> getPositionStream({
    int distanceFilterMeters = 3,
    int intervalMs = 2000,
  }) {
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}

/// 定位相关异常，携带可直接展示给用户的中文提示。
class LocationException implements Exception {
  final String message;
  const LocationException(this.message);

  @override
  String toString() => message;
}
