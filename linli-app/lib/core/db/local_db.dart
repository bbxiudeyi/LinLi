import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地活动行的生命周期（P0-2 状态机）。
///
/// recording →（用户点保存）saved →（上传成功）synced（sync_status=1）
/// recording/saved →（用户点放弃）discarded（随即物理删除）
///
/// 只有 `saved` 的活动才有资格上传（与"放弃"互斥）；
/// 启动时清理残留的 `recording` 行（进程被杀留下的僵尸录制）。
const _kLifecycleRecording = 'recording';
const _kLifecycleSaved = 'saved';

/// 无归属历史数据的 owner 标记（P0-1 迁移隔离）。
/// 任何真实账号的 UUID 都不会等于它，因此永不可见、永不可同步。
const kLegacyOwner = '__legacy__';

/// 本地 SQLite 数据库（离线存储 + 云端同步）。
///
/// 离线策略（详见设计文档）：
/// - 我的活动：本地 DB 是权威源。录制中每点实时写入，防 App 被杀丢失；
///   结束即上传，失败标记 sync_status=0 待重试。
/// - 个人资料：本地缓存，启动秒读 + 后台刷新。
/// - 活动 ID 由客户端生成（UUID v4），本地 ID = 云端 ID，无需映射。
///
/// 账号隔离（P0-1，整改方案二：单库 + owner_user_id）：
/// - 所有活动/资料行的读写都带 `owner_user_id` 过滤，等于当前登录用户；
/// - v3 之前的无归属存量数据被隔离为 [kLegacyOwner]，不展示、不上传，
///   可用 [purgeLegacyData] 物理清除；
/// - 未登录（无活跃账号）时查询返回空、写入抛错。
///
/// 所有方法均为 async；调用方（provider）在 build/init 时调用。
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  String? _activeUserId;

  /// 测试用：覆盖数据库文件名（flutter test 并行跑多个测试文件时
  /// 各自独立建库，避免共用 linli.db 互相干扰）。生产代码不设此值。
  @visibleForTesting
  static String? testDbFileName;

  /// 初始化数据库（main 启动时调用一次）。
  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, testDbFileName ?? 'linli.db'),
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 关闭数据库并重置单例状态（仅测试用）。
  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
    _activeUserId = null;
  }

  /// 当前活跃账号 ID（登录/恢复登录态时设置，登出时置 null）。
  String? get activeUserId => _activeUserId;

  /// 切换活跃账号（登录成功 / 启动恢复登录态 / 登出时调用）。
  ///
  /// - 切换后所有读写只作用于该账号自己的数据；
  /// - 每次切换清理该账号残留的 `recording` 行（上次进程被杀的僵尸录制），
  ///   避免它出现在列表或被当作待同步上传。
  Future<void> setActiveUser(String? userId) async {
    _activeUserId = userId;
    if (userId == null) return;
    await _deleteZombieRecordings(userId);
  }

  /// 数据属主过滤条件（内部用）。返回 null 表示当前无活跃账号。
  (String, List<Object?>)? get _ownerWhere {
    final uid = _activeUserId;
    if (uid == null) return null;
    return ('owner_user_id = ?', [uid]);
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalDb 未初始化，请先调用 LocalDb.instance.init()');
    }
    return db;
  }

  /// 写操作前置校验：必须已登录（有活跃账号）。
  String get _requireOwner {
    final uid = _activeUserId;
    if (uid == null) {
      throw StateError('未登录（无活跃账号），禁止写入本地活动数据');
    }
    return uid;
  }

  Future<void> _onCreate(Database db, int version) async {
    // 本地活动表。id 由客户端生成（与云端一致）。
    // sync_status: 0=待同步, 1=已同步
    // lifecycle: recording=录制中, saved=已保存（含待同步）
    // owner_user_id: 数据归属账号（P0-1 账号隔离）
    // is_private 默认 1（私密，P0-3）：未明确选择可见范围时绝不公开
    await db.execute('''
      CREATE TABLE activities (
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
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
        is_private INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0,
        lifecycle TEXT NOT NULL DEFAULT 'recording',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_activities_start_time ON activities(start_time DESC)');
    await db.execute(
        'CREATE INDEX idx_activities_owner ON activities(owner_user_id)');

    // 本地轨迹点表（录制中每点实时写，防丢失）。
    // 点的归属随所属活动（activity_id 是 UUID，跨账号不可能碰撞）。
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

    // 个人资料缓存（按账号一行，user_id 为主键）
    await db.execute('''
      CREATE TABLE my_profile (
        user_id TEXT PRIMARY KEY,
        email TEXT,
        nickname TEXT,
        avatar_url TEXT,
        bio TEXT,
        gender TEXT,
        birthday TEXT,
        weight_kg REAL,
        height_cm REAL,
        created_at TEXT,
        cached_at TEXT NOT NULL
      )
    ''');
  }

  /// 数据库升级回调（老用户已装 App 升级时调用）。
  ///
  /// 迁移必须可重入：若上次升级中途被杀（列已加、版本号未提交），
  /// 下次打开会重跑同一段迁移——重复的 ALTER 要跳过而不是抛错，
  /// 否则 LocalDb.init() 在 main() 里失败 = App 启动即闪退。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: my_profile 表加 height_cm 列
      await _tryExecute(db, 'ALTER TABLE my_profile ADD COLUMN height_cm REAL');
    }
    if (oldVersion < 3) {
      // v3: 账号隔离 + 生命周期 + 默认私密
      await _tryExecute(db, 'ALTER TABLE activities ADD COLUMN owner_user_id TEXT');
      await _tryExecute(
          db, "ALTER TABLE activities ADD COLUMN lifecycle TEXT NOT NULL DEFAULT 'recording'");
      // 存量无归属数据（v2 及更早）绝不能自动归给之后登录的任何账号：
      // 统一标记为 legacy，查询永远过滤不到，也不进入待同步队列。
      await db.execute(
          'UPDATE activities SET owner_user_id = ? WHERE owner_user_id IS NULL',
          [kLegacyOwner]);
      // 已同步过的存量行视为 saved，其余视为 recording（下次启动会被清理）
      await db.execute(
          "UPDATE activities SET lifecycle = 'saved' WHERE sync_status = 1");
      // 存量活动默认转私密（P0-3）
      await db.execute('UPDATE activities SET is_private = 1');

      // my_profile 重建为按 user_id 主键（仅当还是旧结构时才重建）
      final cols = await db.rawQuery('PRAGMA table_info(my_profile)');
      final hasOldIdCol = cols.any((c) => c['name'] == 'id');
      if (hasOldIdCol) {
        await db.execute('''
          CREATE TABLE my_profile_v3 (
            user_id TEXT PRIMARY KEY,
            email TEXT,
            nickname TEXT,
            avatar_url TEXT,
            bio TEXT,
            gender TEXT,
            birthday TEXT,
            weight_kg REAL,
            height_cm REAL,
            created_at TEXT,
            cached_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          INSERT INTO my_profile_v3
            (user_id, email, nickname, avatar_url, bio, gender, birthday,
             weight_kg, height_cm, created_at, cached_at)
          SELECT user_id, email, nickname, avatar_url, bio, gender, birthday,
                 weight_kg, height_cm, created_at, cached_at
          FROM my_profile WHERE user_id IS NOT NULL
        ''');
        await db.execute('DROP TABLE my_profile');
        await db.execute('ALTER TABLE my_profile_v3 RENAME TO my_profile');
      }
    }
  }

  /// 可重入执行迁移 DDL：目标列/表已存在（上次迁移被中断）时跳过而不抛错。
  Future<void> _tryExecute(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (e) {
      debugPrint('迁移语句跳过（可能上次已应用）: $e');
    }
  }

  /// 物理清除被隔离的无归属历史数据（P0-1 迁移产物）。
  /// 确认不再需要后可调用（例如发布前清理内测数据）。
  Future<void> purgeLegacyData() async {
    await _database.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM activity_points WHERE activity_id IN '
        '(SELECT id FROM activities WHERE owner_user_id = ?)',
        [kLegacyOwner],
      );
      await txn.delete(
        'activities',
        where: 'owner_user_id = ?',
        whereArgs: [kLegacyOwner],
      );
    });
  }

  /// 清理某账号残留的 recording 行（进程被杀的僵尸录制）及其轨迹点。
  Future<void> _deleteZombieRecordings(String userId) async {
    await _database.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM activity_points WHERE activity_id IN '
        "(SELECT id FROM activities WHERE owner_user_id = ? AND lifecycle = 'recording')",
        [userId],
      );
      await txn.rawDelete(
        "DELETE FROM activities WHERE owner_user_id = ? AND lifecycle = 'recording'",
        [userId],
      );
    });
  }

  // ==================== 活动 ====================

  /// 创建一条本地活动（录制开始时调用）。
  /// lifecycle=recording、sync_status=0（待同步）；必须已登录。
  Future<void> insertActivity(Map<String, dynamic> a) async {
    final owner = _requireOwner;
    await _database.insert(
      'activities',
      {
        'id': a['id'],
        'owner_user_id': owner,
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
        'is_private': (a['is_private'] as bool?) == false ? 0 : 1,
        'sync_status': 0,
        'lifecycle': _kLifecycleRecording,
        'created_at': a['created_at'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新活动统计字段（录制中/结束时，统计值会变化）。仅限当前账号。
  Future<void> updateActivityStats(
    String id,
    Map<String, dynamic> stats,
  ) async {
    final owner = _requireOwner;
    await _database.update(
      'activities',
      stats,
      where: 'id = ? AND owner_user_id = ?',
      whereArgs: [id, owner],
    );
  }

  /// 标记活动为"已保存"（用户在保存页点了保存）。
  /// 只有 saved 状态的活动才会被上传（与"放弃"互斥，P0-2）。
  Future<void> markSaved(String id, {required bool isPrivate}) async {
    final owner = _requireOwner;
    await _database.update(
      'activities',
      {'lifecycle': _kLifecycleSaved, 'is_private': isPrivate ? 1 : 0},
      where: 'id = ? AND owner_user_id = ?',
      whereArgs: [id, owner],
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
  /// 仅当活动属于当前账号时返回，否则空（防跨账号读点）。
  Future<List<Map<String, dynamic>>> getPoints(String activityId) async {
    final owned = await _database.query(
      'activities',
      columns: ['id'],
      where: 'id = ? AND owner_user_id = ?',
      whereArgs: [activityId, _activeUserId],
      limit: 1,
    );
    if (owned.isEmpty) return const [];
    return _database.query(
      'activity_points',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'seq ASC',
    );
  }

  /// 列出当前账号的活动（按 start_time 降序），供列表/Profile 展示。
  Future<List<Map<String, dynamic>>> listActivities({int? limit}) async {
    final owner = _ownerWhere;
    if (owner == null) return const [];
    return _database.query(
      'activities',
      where: owner.$1,
      whereArgs: owner.$2,
      orderBy: 'start_time DESC',
      limit: limit,
    );
  }

  /// 统计当前账号活动总数（用于 Profile 统计展示）。
  Future<int> countActivities() async {
    final owner = _ownerWhere;
    if (owner == null) return 0;
    final rows = await _database.rawQuery(
        'SELECT COUNT(*) AS c FROM activities WHERE ${owner.$1}', owner.$2);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// 执行原始 SQL 查询（供统计聚合等场景使用）。
  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<Object?>? args]) {
    return _database.rawQuery(sql, args);
  }

  /// 读取单条活动（仅当前账号的）。
  Future<Map<String, dynamic>?> getActivity(String id) async {
    final owner = _ownerWhere;
    if (owner == null) return null;
    final rows = await _database.query(
      'activities',
      where: 'id = ? AND ${owner.$1}',
      whereArgs: [id, ...owner.$2],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 标记某活动为已同步（仅当前账号的）。
  /// 同时落 lifecycle='saved'：云端合并回来的行走这条路，
  /// 不落的话下次启动会被当僵尸录制误删。
  Future<void> markSynced(String id) async {
    final owner = _ownerWhere;
    if (owner == null) return;
    await _database.update(
      'activities',
      {'sync_status': 1, 'lifecycle': _kLifecycleSaved},
      where: 'id = ? AND ${owner.$1}',
      whereArgs: [id, ...owner.$2],
    );
  }

  /// 删除一个活动及其全部轨迹点（仅当前账号的）。
  /// 两表无外键约束，手动删 activity_points 避免孤儿点；用事务保证原子性。
  Future<void> deleteActivity(String id) async {
    final owner = _requireOwner;
    await _database.transaction((txn) async {
      await txn.delete(
        'activity_points',
        where: 'activity_id IN (SELECT id FROM activities '
            'WHERE id = ? AND owner_user_id = ?)',
        whereArgs: [id, owner],
      );
      await txn.delete(
        'activities',
        where: 'id = ? AND owner_user_id = ?',
        whereArgs: [id, owner],
      );
    });
  }

  /// 获取当前账号所有待同步的活动（saved 且 sync_status=0），供重试用。
  /// 只有用户明确保存过的活动才会上传（P0-2：与放弃互斥）。
  Future<List<Map<String, dynamic>>> getUnsyncedActivities() async {
    final owner = _ownerWhere;
    if (owner == null) return const [];
    return _database.query(
      'activities',
      where: '${owner.$1} AND sync_status = ? AND lifecycle = ?',
      whereArgs: [...owner.$2, 0, _kLifecycleSaved],
      orderBy: 'created_at ASC',
    );
  }

  // ==================== 个人资料缓存 ====================

  /// 保存/更新当前账号的个人资料缓存（按 user_id 一行）。
  Future<void> saveMyProfile(Map<String, dynamic> profile) async {
    final uid = _requireOwner;
    await _database.insert(
      'my_profile',
      {
        'user_id': uid,
        'email': profile['email'],
        'nickname': profile['nickname'],
        'avatar_url': profile['avatar_url'],
        'bio': profile['bio'],
        'gender': profile['gender'],
        'birthday': profile['birthday'],
        'weight_kg': (profile['weight_kg'] as num?)?.toDouble(),
        'height_cm': (profile['height_cm'] as num?)?.toDouble(),
        'created_at': profile['created_at'],
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取当前账号缓存的个人资料（无缓存返回 null）。
  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = _activeUserId;
    if (uid == null) return null;
    final rows = await _database.query(
      'my_profile',
      where: 'user_id = ?',
      whereArgs: [uid],
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
      'height_cm': r['height_cm'],
      'created_at': r['created_at'],
    };
  }
}
