import 'package:latlong2/latlong.dart';

enum SportType { run, ride, hike, walk }

extension SportTypeX on SportType {
  String get label {
    switch (this) {
      case SportType.run:
        return '跑步';
      case SportType.ride:
        return '骑行';
      case SportType.hike:
        return '徒步';
      case SportType.walk:
        return '走路';
    }
  }

  String get icon {
    switch (this) {
      case SportType.run:
        return '🏃';
      case SportType.ride:
        return '🚴';
      case SportType.hike:
        return '🥾';
      case SportType.walk:
        return '🚶';
    }
  }
}

class GpsPoint {
  final LatLng latLng;
  final double altitude;
  final double speed;
  final double accuracy;
  final DateTime timestamp;

  const GpsPoint({
    required this.latLng,
    this.altitude = 0,
    this.speed = 0,
    this.accuracy = 0,
    required this.timestamp,
  });
}

class ActivitySummary {
  final SportType type;
  final int distanceMeters;
  final int durationSeconds;
  final int movingTimeSeconds;
  final int avgPaceSecondsPerKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double elevationGain;
  final double elevationLoss;
  final int calories;
  final DateTime startTime;
  final DateTime endTime;
  final List<GpsPoint> gpsPoints;

  const ActivitySummary({
    required this.type,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.movingTimeSeconds,
    required this.avgPaceSecondsPerKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.elevationGain,
    required this.elevationLoss,
    required this.calories,
    required this.startTime,
    required this.endTime,
    required this.gpsPoints,
  });

  String get distanceDisplay {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
    }
    return '$distanceMeters m';
  }

  String get durationDisplay {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get avgPaceDisplay {
    if (avgPaceSecondsPerKm == 0) return '--:--';
    final m = avgPaceSecondsPerKm ~/ 60;
    final s = avgPaceSecondsPerKm % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }
}
