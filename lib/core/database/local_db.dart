import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'local_user.dart';

/// 本地 SQLite 数据库（sqflite）单例 + DAO。
///
/// 替代 Supabase 云数据库，所有数据存手机本地，离线可用。
/// 表结构参照 supabase/migrations/00001_initial_schema.sql 简化：
/// - POINT 类型拆成 lat/lng 两列
/// - UUID 用 Dart uuid 包生成
/// - 去掉外键约束（sqflite 默认不支持，用业务逻辑保证一致性）
class LocalDb {
  LocalDb._();

  static Database? _database;

  static const _dbName = 'linli.db';
  static const _dbVersion = 1;

  /// 初始化数据库（main.dart 启动时调用一次）。
  static Future<void> initialize() async {
    _database ??= await _open();
  }

  static Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 用户表
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        phone TEXT UNIQUE,
        nickname TEXT NOT NULL DEFAULT '运动爱好者',
        avatar_url TEXT,
        bio TEXT,
        gender TEXT,
        birthday TEXT,
        weight_kg REAL,
        created_at TEXT NOT NULL
      )
    ''');

    // 运动活动表
    await db.execute('''
      CREATE TABLE activities (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        distance_m INTEGER DEFAULT 0,
        duration_s INTEGER DEFAULT 0,
        moving_time_s INTEGER DEFAULT 0,
        avg_pace_s_per_km INTEGER DEFAULT 0,
        avg_speed_kmh REAL DEFAULT 0,
        max_speed_kmh REAL DEFAULT 0,
        elevation_gain_m REAL DEFAULT 0,
        elevation_loss_m REAL DEFAULT 0,
        calories INTEGER DEFAULT 0,
        start_time TEXT NOT NULL,
        end_time TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // GPS 轨迹点表（修复原 Supabase 版轨迹丢失问题）
    await db.execute('''
      CREATE TABLE activity_points (
        id TEXT PRIMARY KEY,
        activity_id TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        altitude REAL,
        speed REAL,
        accuracy REAL,
        timestamp TEXT NOT NULL,
        seq INTEGER NOT NULL
      )
    ''');

    // 点赞表（单用户：给自己点赞）
    await db.execute('''
      CREATE TABLE kudos (
        id TEXT PRIMARY KEY,
        activity_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 索引
    await db.execute('CREATE INDEX idx_activities_start_time ON activities(start_time DESC)');
    await db.execute('CREATE INDEX idx_activity_points_activity_id ON activity_points(activity_id, seq)');
    await db.execute('CREATE INDEX idx_kudos_activity ON kudos(activity_id)');
  }

  static Database get _db {
    final db = _database;
    if (db == null) {
      throw StateError('LocalDb 未初始化，请先调用 LocalDb.initialize()');
    }
    return db;
  }

  // ==================== 通用 ====================

  static const _uuid = Uuid();

  // ==================== Auth / User ====================

  /// 按 phone 查用户（登录用）。
  static Future<LocalUser?> findUserByPhone(String phone) async {
    final rows = await _db.query('users', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (rows.isEmpty) return null;
    return LocalUser.fromRow(rows.first);
  }

  /// 创建新用户（注册用）。
  static Future<LocalUser> createUser({required String phone, required String nickname}) async {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _db.insert('users', {
      'id': id,
      'phone': phone,
      'nickname': nickname,
      'created_at': now,
    });
    return LocalUser(id: id, phone: phone, nickname: nickname);
  }

  /// 取单个用户行（profile 页用）。
  static Future<Map<String, dynamic>?> getUser(String id) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// 更新用户资料。
  static Future<void> updateUser(String id, Map<String, dynamic> fields) async {
    await _db.update('users', fields, where: 'id = ?', whereArgs: [id]);
  }

  // ==================== Activity ====================

  /// 插入运动活动，返回新行 id。
  static Future<String> insertActivity(Map<String, dynamic> row) async {
    final id = row['id'] as String? ?? _uuid.v4();
    final full = {
      'id': id,
      'created_at': DateTime.now().toIso8601String(),
      ...row,
    };
    await _db.insert('activities', full);
    return id;
  }

  /// 批量插入轨迹点（一个事务，性能优）。
  static Future<void> insertPoints(String activityId, List<Map<String, dynamic>> points) async {
    if (points.isEmpty) return;
    final batch = _db.batch();
    for (final pt in points) {
      batch.insert('activity_points', {
        'id': _uuid.v4(),
        'activity_id': activityId,
        ...pt,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 查所有活动（按开始时间降序）。
  static Future<List<Map<String, dynamic>>> queryActivities({int limit = 50}) async {
    return _db.query('activities', orderBy: 'start_time DESC', limit: limit);
  }

  /// 查单个活动。
  static Future<Map<String, dynamic>?> getActivity(String id) async {
    final rows = await _db.query('activities', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// 查某活动的所有轨迹点（按 seq 升序）。
  static Future<List<Map<String, dynamic>>> getPoints(String activityId) async {
    return _db.query(
      'activity_points',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'seq ASC',
    );
  }

  // ==================== Kudos ====================

  /// 是否已点赞。
  static Future<bool> hasKudo(String activityId) async {
    final rows = await _db.query('kudos',
        where: 'activity_id = ?', whereArgs: [activityId], limit: 1);
    return rows.isNotEmpty;
  }

  /// 点赞。
  static Future<void> addKudo(String activityId) async {
    await _db.insert('kudos', {
      'id': _uuid.v4(),
      'activity_id': activityId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 取消点赞。
  static Future<void> removeKudo(String activityId) async {
    await _db.delete('kudos', where: 'activity_id = ?', whereArgs: [activityId]);
  }

  /// 统计某活动的点赞数。
  static Future<int> countKudos(String activityId) async {
    final rows = await _db.query('kudos',
        columns: ['id'],
        where: 'activity_id = ?',
        whereArgs: [activityId]);
    return rows.length;
  }
}
