import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/local_db.dart';
import '../../../core/location/location_service.dart';
import '../models/activity_models.dart';

enum RecordingState { idle, ready, recording, paused, stopped }

class TrackingState {
  final RecordingState state;
  final SportType sportType;
  final List<GpsPoint> gpsPoints;
  final int distanceMeters;
  final int durationSeconds;
  final int movingTimeSeconds; // 移动时间（剔除静止/红绿灯），用于真实平均配速
  final double currentSpeedKmh;
  final double currentPaceMinPerKm;
  final double elevationGain;
  final double maxSpeedKmh;
  /// 本次录制对应的本地活动 ID（客户端生成的 UUID v4）。
  /// 录制开始时生成，同步本地 DB + buildSummary，作为云端活动 ID。
  final String? localActivityId;
  /// 定位错误提示（权限拒绝、服务关闭等），null 表示无错误
  final String? locationError;

  const TrackingState({
    this.state = RecordingState.idle,
    this.sportType = SportType.run,
    this.gpsPoints = const [],
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.movingTimeSeconds = 0,
    this.currentSpeedKmh = 0,
    this.currentPaceMinPerKm = 0,
    this.elevationGain = 0,
    this.maxSpeedKmh = 0,
    this.localActivityId,
    this.locationError,
  });

  TrackingState copyWith({
    RecordingState? state,
    SportType? sportType,
    List<GpsPoint>? gpsPoints,
    int? distanceMeters,
    int? durationSeconds,
    int? movingTimeSeconds,
    double? currentSpeedKmh,
    double? currentPaceMinPerKm,
    double? elevationGain,
    double? maxSpeedKmh,
    String? localActivityId,
    String? locationError,
  }) {
    return TrackingState(
      state: state ?? this.state,
      sportType: sportType ?? this.sportType,
      gpsPoints: gpsPoints ?? this.gpsPoints,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      movingTimeSeconds: movingTimeSeconds ?? this.movingTimeSeconds,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      currentPaceMinPerKm: currentPaceMinPerKm ?? this.currentPaceMinPerKm,
      elevationGain: elevationGain ?? this.elevationGain,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      localActivityId: localActivityId ?? this.localActivityId,
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

  // ===== 漂移过滤 & 移动判定阈值（问题2/问题3）=====
  /// 定位精度差于此值的点直接丢弃（GPS 漂移主要来源）。
  static const _maxAccuracy = 25.0; // 米
  /// 相邻点距离小于此值不累计距离（视为静止抖动），但点仍保留以维持轨迹形状。
  static const _minMoveMeters = 3.0; // 米
  /// 速度低于此值视为静止，对应时间段不计入移动时间（剔除等红灯、休息）。
  /// 0.7 m/s ≈ 2.5 km/h，比慢走略慢，跑步场景合理。
  static const _movingSpeedThreshold = 0.7; // m/s

  /// 上一个"有效"点（用于距离/速度计算）。与 state.gpsPoints 解耦：
  /// 被精度过滤丢弃的点不更新此字段，避免用差定位算距离。
  GpsPoint? _lastValidPoint;
  /// 上一个有效点的 wall clock（用于计算时间差判定移动时间）。
  DateTime? _lastValidTime;
  /// 移动时间累计（秒）。
  int _movingSeconds = 0;

  GpsTrackerNotifier() : super(const TrackingState());

  void selectSport(SportType type) {
    // 选完运动类型进入"准备"状态，等用户点"开始"才真正录制
    state = state.copyWith(sportType: type, state: RecordingState.ready);
  }

  /// 用户点了"开始"按钮，真正开始录制。
  /// 会先检查定位权限，失败时把错误写入 [TrackingState.locationError]。
  ///
  /// 关键：先把第一个 GPS 点拿到，再把 state 切到 recording——
  /// 这样地图一出现就已经有定位点，直接定位到那里，不会先跳默认视野（北京）。
  ///
  /// 离线防丢：开始时在本地 DB 创建活动行（sync_status=0 待同步），
  /// 之后每个 GPS 点实时写入 activity_points 表，App 被杀也不丢。
  Future<void> beginRecording() async {
    // 只允许从 ready 态开始（避免重复触发）
    if (state.state != RecordingState.ready) return;

    try {
      await LocationService.ensureReady();
    } on LocationException catch (e) {
      state = state.copyWith(locationError: e.message);
      return;
    }

    _startTime = DateTime.now();

    // 生成活动 UUID（本地 ID = 云端 ID），并在本地 DB 建活动行
    final activityId = const Uuid().v4();
    await LocalDb.instance.insertActivity({
      'id': activityId,
      'type': state.sportType.name,
      'start_time': _startTime!.toUtc().toIso8601String(),
      'created_at': _startTime!.toUtc().toIso8601String(),
    });
    state = state.copyWith(localActivityId: activityId);

    // 先拿一次当前位置（不切 state，页面还在准备态）
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

  /// 停止录制：停定时器/定位流，切到 stopped 态（触发保存页显示）。
  /// 数据保留，等保存页点"保存"后由 provider 的 saveActivity + reset 处理。
  void stop() {
    _timer?.cancel();
    _positionSub?.cancel();
    state = state.copyWith(state: RecordingState.stopped);
  }

  /// 放弃本次录制（保存页点"放弃"用）：清空一切回 idle。
  void discard() {
    reset();
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
    // ===== 问题3：精度过滤 =====
    // accuracy 过大的点定位质量差，是 GPS 漂移的主要来源，直接丢弃。
    // 丢弃的点不进入 state.gpsPoints，也不更新 _lastValidPoint。
    if (p.accuracy > _maxAccuracy) {
      return;
    }

    final newPoint = GpsPoint(
      latLng: LatLng(p.latitude, p.longitude),
      altitude: p.altitude,
      speed: p.speed,
      accuracy: p.accuracy,
      timestamp: p.timestamp.toUtc(),
    );
    final now = DateTime.now();

    int newDistance = state.distanceMeters;
    double newElevationGain = state.elevationGain;
    int newMovingSeconds = _movingSeconds;

    if (_lastValidPoint != null) {
      final segMeters = _distance(_lastValidPoint!.latLng, newPoint.latLng);
      final segTimeSec = _lastValidTime != null
          ? now.difference(_lastValidTime!).inSeconds
          : 0;

      // ===== 问题3：距离过滤 =====
      // 相邻距离 < _minMoveMeters 视为静止抖动，不累计距离。
      // 点仍加入轨迹（保形状），但不算"移动"。
      if (segMeters >= _minMoveMeters) {
        newDistance += segMeters.round();

        // ===== 问题2：移动时间累计（速度阈值法）=====
        // 用本段平均速度判定：位移/时间。低于阈值（如等红灯）不计入 movingTime。
        if (segTimeSec > 0) {
          final avgSpeed = segMeters / segTimeSec; // m/s
          if (avgSpeed >= _movingSpeedThreshold) {
            newMovingSeconds += segTimeSec;
          }
        }
      }

      // 海拔爬升按有效点累计
      if (newPoint.altitude > _lastValidPoint!.altitude) {
        newElevationGain += newPoint.altitude - _lastValidPoint!.altitude;
      }
    }

    // 更新"上一个有效点"状态
    _lastValidPoint = newPoint;
    _lastValidTime = now;
    _movingSeconds = newMovingSeconds;

    // ===== 离线防丢：把该点实时写入本地 DB =====
    // 即使 App 被杀，下次启动也能从本地恢复已录的轨迹。
    final activityId = state.localActivityId;
    if (activityId != null) {
      final seq = state.gpsPoints.length; // 本点在轨迹中的序号
      LocalDb.instance.appendPoint(
        activityId,
        seq,
        p.latitude,
        p.longitude,
        ele: p.altitude,
        speed: p.speed,
        recordedAt: p.timestamp.toUtc().toIso8601String(),
      );
    }

    final speedKmh = newPoint.speed > 0 ? newPoint.speed * 3.6 : 0.0;
    final paceMinPerKm = speedKmh > 0 ? 60.0 / speedKmh : 0.0;

    state = state.copyWith(
      gpsPoints: [...state.gpsPoints, newPoint],
      distanceMeters: newDistance,
      movingTimeSeconds: newMovingSeconds,
      currentSpeedKmh: speedKmh,
      currentPaceMinPerKm: paceMinPerKm,
      elevationGain: newElevationGain,
      maxSpeedKmh: state.maxSpeedKmh < speedKmh ? speedKmh : state.maxSpeedKmh,
    );
  }

  /// 结束录制，构建汇总并写回本地活动行的最终统计。
  /// 返回 null 表示没有有效数据（无点或无开始时间）。
  Future<ActivitySummary?> buildSummary() async {
    if (state.gpsPoints.isEmpty || _startTime == null) return null;

    final endTime = DateTime.now();
    // 平均速度/配速用移动时间（movingTimeSeconds）算，剔除等红灯/休息，
    // 得到真实的运动配速（而非含静止的"表观配速"）。
    final movingSecs = state.movingTimeSeconds > 0
        ? state.movingTimeSeconds
        : state.durationSeconds;
    final avgSpeed = state.distanceMeters > 0
        ? (state.distanceMeters / 1000) / (movingSecs / 3600)
        : 0.0;
    final avgPace = state.distanceMeters > 0
        ? (movingSecs / (state.distanceMeters / 1000)).round()
        : 0;
    final calories = (state.distanceMeters * 0.06).round();

    // 把最终统计写回本地活动行（录制期间只有 start_time，现在补全）
    final activityId = state.localActivityId;
    if (activityId != null) {
      await LocalDb.instance.updateActivityStats(activityId, {
        'distance_m': state.distanceMeters,
        'duration_s': state.durationSeconds,
        'moving_time_s': movingSecs,
        'avg_pace_s_per_km': avgPace,
        'avg_speed_kmh': avgSpeed,
        'max_speed_kmh': state.maxSpeedKmh,
        'elevation_gain_m': state.elevationGain,
        'elevation_loss_m': 0,
        'calories': calories,
        'end_time': endTime.toUtc().toIso8601String(),
      });
    }

    return ActivitySummary(
      type: state.sportType,
      localActivityId: activityId,
      distanceMeters: state.distanceMeters,
      durationSeconds: state.durationSeconds,
      movingTimeSeconds: movingSecs,
      avgPaceSecondsPerKm: avgPace,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: state.maxSpeedKmh,
      elevationGain: state.elevationGain,
      elevationLoss: 0,
      calories: calories,
      startTime: _startTime!,
      endTime: endTime,
      gpsPoints: state.gpsPoints,
    );
  }

  void reset() {
    _timer?.cancel();
    _positionSub?.cancel();
    _startTime = null;
    _lastValidPoint = null;
    _lastValidTime = null;
    _movingSeconds = 0;
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
