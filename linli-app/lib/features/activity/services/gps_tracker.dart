import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/location/location_service.dart';
import '../models/activity_models.dart';

enum RecordingState { idle, recording, paused }

class TrackingState {
  final RecordingState state;
  final SportType sportType;
  final List<GpsPoint> gpsPoints;
  final int distanceMeters;
  final int durationSeconds;
  final double currentSpeedKmh;
  final double currentPaceMinPerKm;
  final double elevationGain;
  final double maxSpeedKmh;
  /// 定位错误提示（权限拒绝、服务关闭等），null 表示无错误
  final String? locationError;

  const TrackingState({
    this.state = RecordingState.idle,
    this.sportType = SportType.run,
    this.gpsPoints = const [],
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.currentSpeedKmh = 0,
    this.currentPaceMinPerKm = 0,
    this.elevationGain = 0,
    this.maxSpeedKmh = 0,
    this.locationError,
  });

  TrackingState copyWith({
    RecordingState? state,
    SportType? sportType,
    List<GpsPoint>? gpsPoints,
    int? distanceMeters,
    int? durationSeconds,
    double? currentSpeedKmh,
    double? currentPaceMinPerKm,
    double? elevationGain,
    double? maxSpeedKmh,
    String? locationError,
  }) {
    return TrackingState(
      state: state ?? this.state,
      sportType: sportType ?? this.sportType,
      gpsPoints: gpsPoints ?? this.gpsPoints,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      currentPaceMinPerKm: currentPaceMinPerKm ?? this.currentPaceMinPerKm,
      elevationGain: elevationGain ?? this.elevationGain,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      locationError: locationError ?? this.locationError,
    );
  }

  /// 清除定位错误（用户看完提示后调用）
  TrackingState clearError() => copyWith(locationError: null);

  String get distanceDisplay {
    if (distanceMeters >= 1000) {
      return (distanceMeters / 1000).toStringAsFixed(2);
    }
    return '$distanceMeters';
  }

  String get durationDisplay {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get avgPaceDisplay {
    if (distanceMeters < 100) return '--:--';
    final totalSeconds = durationSeconds;
    final avgPaceSeconds = (totalSeconds / (distanceMeters / 1000)).round();
    final m = avgPaceSeconds ~/ 60;
    final s = avgPaceSeconds % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }
}

/// 运动录制控制器。
///
/// 数据源：真实 GPS（[LocationService] + geolocator）。
/// 状态机：idle → recording ⇄ paused → idle。
/// 距离用 [Distance]（球面距离）累计，爬升按正向海拔差累计。
class GpsTrackerNotifier extends StateNotifier<TrackingState> {
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  DateTime? _startTime;
  static const _distance = Distance();

  GpsTrackerNotifier() : super(const TrackingState());

  void selectSport(SportType type) {
    state = state.copyWith(sportType: type);
  }

  /// 开始录制。会先检查定位权限，失败时把错误写入 [TrackingState.locationError]。
  ///
  /// 关键：先把第一个 GPS 点拿到，再把 state 切到 recording——
  /// 这样地图一出现就已经有定位点，直接定位到那里，不会先跳默认视野（北京）。
  Future<void> start() async {
    try {
      await LocationService.ensureReady();
    } on LocationException catch (e) {
      state = state.copyWith(locationError: e.message);
      return;
    }

    _startTime = DateTime.now();

    // 先拿一次当前位置（不切 state，页面还停在运动选择页）
    Position? initial;
    try {
      initial = await LocationService.getCurrentPosition();
    } catch (_) {
      // 获取当前位置失败不阻塞，继续订阅流，后续会补上
    }

    // 拿到点后再切到 recording，并把点加入 state
    if (initial != null) {
      _onPosition(initial); // 先累积点（此时页面还不知道，但 state 已有点）
    }

    // 现在 state 已有定位点，切到 recording 触发页面渲染地图
    state = state.copyWith(
      state: RecordingState.recording,
      locationError: null,
    );

    _startTimer();
    _startLocationStream();
  }

  void pause() {
    _timer?.cancel();
    _positionSub?.cancel();
    state = state.copyWith(state: RecordingState.paused);
  }

  Future<void> resume() async {
    // 暂停后恢复，定位可能被系统回收，重新检查
    try {
      await LocationService.ensureReady();
    } on LocationException catch (e) {
      state = state.copyWith(locationError: e.message);
      return;
    }
    state = state.copyWith(state: RecordingState.recording);
    _startTimer();
    _startLocationStream();
  }

  void stop() {
    _timer?.cancel();
    _positionSub?.cancel();
    state = state.copyWith(state: RecordingState.idle);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });
  }

  /// 订阅真实 GPS 流，每来一个点就累积进 state。
  void _startLocationStream() {
    _positionSub?.cancel();
    _positionSub = LocationService.getPositionStream().listen(
      _onPosition,
      onError: (Object e) {
        state = state.copyWith(locationError: '定位异常：$e');
      },
    );
  }

  void _onPosition(Position p) {
    final lastPoint =
        state.gpsPoints.isNotEmpty ? state.gpsPoints.last : null;

    final newPoint = GpsPoint(
      latLng: LatLng(p.latitude, p.longitude),
      altitude: p.altitude,
      speed: p.speed,
      accuracy: p.accuracy,
      timestamp: p.timestamp.toUtc(),
    );

    final newPoints = [...state.gpsPoints, newPoint];
    int newDistance = state.distanceMeters;
    double newElevationGain = state.elevationGain;

    if (lastPoint != null) {
      newDistance += _distance(lastPoint.latLng, newPoint.latLng).round();
      if (newPoint.altitude > lastPoint.altitude) {
        newElevationGain += newPoint.altitude - lastPoint.altitude;
      }
    }

    final speedKmh = newPoint.speed > 0 ? newPoint.speed * 3.6 : 0.0;
    final paceMinPerKm = speedKmh > 0 ? 60.0 / speedKmh : 0.0;

    state = state.copyWith(
      gpsPoints: newPoints,
      distanceMeters: newDistance,
      currentSpeedKmh: speedKmh,
      currentPaceMinPerKm: paceMinPerKm,
      elevationGain: newElevationGain,
      maxSpeedKmh: state.maxSpeedKmh < speedKmh ? speedKmh : state.maxSpeedKmh,
    );
  }

  ActivitySummary? buildSummary() {
    if (state.gpsPoints.isEmpty || _startTime == null) return null;

    final endTime = DateTime.now();
    final avgSpeed = state.distanceMeters > 0
        ? (state.distanceMeters / 1000) / (state.durationSeconds / 3600)
        : 0.0;
    final avgPace = state.distanceMeters > 0
        ? (state.durationSeconds / (state.distanceMeters / 1000)).round()
        : 0;

    return ActivitySummary(
      type: state.sportType,
      distanceMeters: state.distanceMeters,
      durationSeconds: state.durationSeconds,
      movingTimeSeconds: state.durationSeconds,
      avgPaceSecondsPerKm: avgPace,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: state.maxSpeedKmh,
      elevationGain: state.elevationGain,
      elevationLoss: 0,
      calories: (state.distanceMeters * 0.06).round(),
      startTime: _startTime!,
      endTime: endTime,
      gpsPoints: state.gpsPoints,
    );
  }

  void reset() {
    _timer?.cancel();
    _positionSub?.cancel();
    _startTime = null;
    state = const TrackingState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}

final gpsTrackerProvider =
    StateNotifierProvider<GpsTrackerNotifier, TrackingState>(
  (ref) => GpsTrackerNotifier(),
);
