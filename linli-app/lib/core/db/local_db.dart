import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地 SQLite 数据库（离线存储 + 云端同步）。
///
/// 离线策略（详见设计文档）：
/// - 我的活动：本地 DB 是权威源。录制中每点实时写入，防 App 被杀丢失；
///   结束即上传，失败标记 sync_status=0 待重试。
/// - 个人资料：本地缓存，启动秒读 + 后台刷新。
/// - 活动 ID 由客户端生成（UUID v4），本地 ID = 云端 ID，无需映射。
///
/// 所有方法均为 async；调用方（provider）在 build/init 时调用。
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  /// 初始化数据库（main 启动时调用一次）。
  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'linli.db'),
      version: 1,
      onCreate: _onCreate,
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalDb 未初始化，请先调用 LocalDb.instance.init()');
    }
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    // 本地活动表。id 由客户端生成（与云端一致）。
    // sync_status: 0=待同步, 1=已同步
    await db.execute('''
      CREATE TABLE activities (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        distance_m INTEGER NOT NULL DEFAULT 0,
        duration_s INTEGER NOT NULL DEFAULT 0,
        moving_time_s INTEGER NOT NULL DEFAULT 0,
        avg_pace_s_per_km INTEGER NOT NULL DEFAULT 0,
        avg_speed_kmh REAL NOT NULL DEFAULT 0,
        max_speed_kmh REAL NOT NULL DEFAULT 0,
        elevation_gain_m REAL NOT NULL DEFAULT 0,
        elevation_loss_m REAL NOT NULL DEFAULT 0,
        calories INTEGER NOT NULL DEFAULT 0,
        start_time TEXT NOT NULL,
        end_time TEXT,
        title TEXT,
        description TEXT,
        is_private INTEGER NOT NULL DEFAULT 0,
        sync_status INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_activities_start_time ON activities(start_time DESC)');

    // 本地轨迹点表（录制中每点实时写，防丢失）
    await db.execute('''
      CREATE TABLE activity_points (
        activity_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        ele REAL,
        speed REAL,
        recorded_at TEXT,
        PRIMARY KEY (activity_id, seq)
      )
    ''');

    // 个人资料缓存（单行，固定 id=1）
    await db.execute('''
      CREATE TABLE my_profile (
        id INTEGER PRIMARY KEY DEFAULT 1,
        user_id TEXT,
        email TEXT,
        nickname TEXT,
        avatar_url TEXT,
        bio TEXT,
        gender TEXT,
        birthday TEXT,
        weight_kg REAL,
        created_at TEXT,
        cached_at TEXT NOT NULL
      )
    ''');
  }

  // ==================== 活动 ====================

  /// 创建一条本地活动（录制开始时调用）。sync_status 默认 0（待同步）。
  Future<void> insertActivity(Map<String, dynamic> a) async {
    await _database.insert(
      'activities',
      {
        'id': a['id'],
        'type': a['type'],
        'distance_m': (a['distance_m'] as num?)?.toInt() ?? 0,
        'duration_s': (a['duration_s'] as num?)?.toInt() ?? 0,
        'moving_time_s': (a['moving_time_s'] as num?)?.toInt() ?? 0,
        'avg_pace_s_per_km': (a['avg_pace_s_per_km'] as num?)?.toInt() ?? 0,
        'avg_speed_kmh': (a['avg_speed_kmh'] as num?)?.toDouble() ?? 0,
        'max_speed_kmh': (a['max_speed_kmh'] as num?)?.toDouble() ?? 0,
        'elevation_gain_m': (a['elevation_gain_m'] as num?)?.toDouble() ?? 0,
        'elevation_loss_m': (a['elevation_loss_m'] as num?)?.toDouble() ?? 0,
        'calories': (a['calories'] as num?)?.toInt() ?? 0,
        'start_time': a['start_time'],
        'end_time': a['end_time'],
        'title': a['title'],
        'description': a['description'],
        'is_private': (a['is_private'] as bool?) == true ? 1 : 0,
        'sync_status': 0,
        'created_at': a['created_at'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新活动统计字段（录制中/结束时，统计值会变化）。
  Future<void> updateActivityStats(
    String id,
    Map<String, dynamic> stats,
  ) async {
    await _database.update(
      'activities',
      stats,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 流式写入单个轨迹点（录制中每点调用，防丢失）。
  Future<void> appendPoint(
    String activityId,
    int seq,
    double lat,
    double lng, {
    double? ele,
    double? speed,
    String? recordedAt,
  }) async {
    await _database.insert(
      'activity_points',
      {
        'activity_id': activityId,
        'seq': seq,
        'lat': lat,
        'lng': lng,
        'ele': ele,
        'speed': speed,
        'recorded_at': recordedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取某活动的所有轨迹点（按 seq 升序）。
  Future<List<Map<String, dynamic>>> getPoints(String activityId) async {
    return _database.query(
      'activity_points',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'seq ASC',
    );
  }

  /// 列出本地所有活动（按 start_time 降序），供列表/Profile 展示。
  Future<List<Map<String, dynamic>>> listActivities({int? limit}) async {
    return _database.query(
      'activities',
      orderBy: 'start_time DESC',
      limit: limit,
    );
  }

  /// 读取单条活动。
  Future<Map<String, dynamic>?> getActivity(String id) async {
    final rows = await _database.query(
      'activities',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 标记某活动为已同步。
  Future<void> markSynced(String id) async {
    await _database.update(
      'activities',
      {'sync_status': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取所有待同步（sync_status=0）的活动，供重试用。
  Future<List<Map<String, dynamic>>> getUnsyncedActivities() async {
    return _database.query(
      'activities',
      where: 'sync_status = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
  }

  // ==================== 个人资料缓存 ====================

  /// 保存/更新个人资料缓存（单行，覆盖）。
  Future<void> saveMyProfile(Map<String, dynamic> profile) async {
    await _database.insert(
      'my_profile',
      {
        'id': 1,
        'user_id': profile['id'] ?? profile['user_id'],
        'email': profile['email'],
        'nickname': profile['nickname'],
        'avatar_url': profile['avatar_url'],
        'bio': profile['bio'],
        'gender': profile['gender'],
        'birthday': profile['birthday'],
        'weight_kg': (profile['weight_kg'] as num?)?.toDouble(),
        'created_at': profile['created_at'],
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取缓存的个人资料（无缓存返回 null）。
  Future<Map<String, dynamic>?> getMyProfile() async {
    final rows = await _database.query(
      'my_profile',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    // 把本地行转成与后端一致的 key（user_id → id）
    final r = rows.first;
    return {
      'id': r['user_id'],
      'email': r['email'],
      'nickname': r['nickname'],
      'avatar_url': r['avatar_url'],
      'bio': r['bio'],
      'gender': r['gender'],
      'birthday': r['birthday'],
      'weight_kg': r['weight_kg'],
      'created_at': r['created_at'],
    };
  }
}
