// 临时诊断：模拟手机上已存在的 v2 旧数据库，验证 v2→v3 迁移是否抛异常。
// （用户报告手机端 App 打不开；LocalDb.init() 在 main() 里，迁移失败 = 启动失败）
import 'package:flutter_test/flutter_test.dart';
import 'package:linli/core/db/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v2 旧库升级到 v3 不应抛异常', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 独立文件名，避免与其他并行测试文件共用 linli.db 互踩
    const dbName = 'linli_test_migration.db';
    LocalDb.testDbFileName = dbName;
    final dbPath = await getDatabasesPath();
    final file = p.join(dbPath, dbName);
    await databaseFactory.deleteDatabase(file);

    // ===== 1. 手工构造 v2 旧库（老代码的 schema + 真实数据形状）=====
    final old = await sqflite.openDatabase(
      file,
      version: 2,
      onCreate: (db, v) async {
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
      },
    );
    // 塞两条活动（一条已同步、一条未同步）+ 点 + 一条 profile 缓存
    await old.insert('activities', {
      'id': 'old-synced',
      'type': 'run',
      'start_time': '2026-07-01T02:00:00Z',
      'created_at': '2026-07-01T02:00:00Z',
      'sync_status': 1,
    });
    await old.insert('activities', {
      'id': 'old-unsynced',
      'type': 'ride',
      'start_time': '2026-07-02T02:00:00Z',
      'created_at': '2026-07-02T02:00:00Z',
      'sync_status': 0,
    });
    await old.insert('activity_points',
        {'activity_id': 'old-synced', 'seq': 0, 'lat': 39.9, 'lng': 116.4});
    await old.insert('my_profile',
        {'id': 1, 'user_id': 'u-1', 'email': 'a@x.com', 'cached_at': 'now'});
    // v2 升级路径：给 my_profile 补 height_cm（老代码的 v2 迁移）
    await old.execute('ALTER TABLE my_profile ADD COLUMN height_cm REAL');
    await old.close();

    // ===== 2. 用新代码打开（version 3）触发迁移 =====
    await LocalDb.instance.closeForTest();
    try {
      await LocalDb.instance.init();
    } catch (e, st) {
      fail('迁移抛异常（这就是手机端打不开的原因）：$e\n$st');
    }

    // ===== 3. 迁移后的不变量 =====
    // 旧数据被隔离为 legacy：任何账号都看不到
    await LocalDb.instance.setActiveUser('u-1');
    expect(await LocalDb.instance.listActivities(), isEmpty,
        reason: '旧无归属数据应不可见');
    // legacy 行确实还在（隔离而非删除），且 owner=__legacy__
    final legacy = await LocalDb.instance.rawQuery(
        "SELECT COUNT(*) AS c FROM activities WHERE owner_user_id = '__legacy__'");
    expect(legacy.first['c'], 2, reason: '旧数据应被隔离保留');
    // profile 缓存按 user_id 迁移成功
    final profile = await LocalDb.instance.getMyProfile();
    expect(profile?['email'], 'a@x.com');
    // 点表结构仍在
    final pts = await LocalDb.instance
        .rawQuery('SELECT COUNT(*) AS c FROM activity_points');
    expect(pts.first['c'], 1);

    await LocalDb.instance.closeForTest();
  });
}
