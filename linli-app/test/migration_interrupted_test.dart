// 诊断：模拟"迁移执行了一半被中断"的数据库（v3 列已加但版本号还是 2），
// 验证新代码打开它会不会崩（用户报告：脱离 flutter run 直接打开 App 闪退）。
import 'package:flutter_test/flutter_test.dart';
import 'package:linli/core/db/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('半迁移（中断）数据库升级 v3 不应抛异常', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const dbName = 'linli_test_interrupted.db';
    LocalDb.testDbFileName = dbName;
    final dbPath = await getDatabasesPath();
    final file = p.join(dbPath, dbName);
    await databaseFactory.deleteDatabase(file);

    // 构造 v2 库
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
            height_cm REAL,
            created_at TEXT,
            cached_at TEXT NOT NULL
          )
        ''');
      },
    );
    // 模拟 v3 迁移执行到一半被杀：列加上了，但版本号仍是 2
    await old.execute('ALTER TABLE activities ADD COLUMN owner_user_id TEXT');
    await old.insert('activities', {
      'id': 'half-migrated-row',
      'type': 'run',
      'start_time': '2026-07-01T02:00:00Z',
      'created_at': '2026-07-01T02:00:00Z',
      'sync_status': 1,
    });
    await old.close();

    // 用新代码打开：预期【不抛异常】（迁移语句可重入）
    await LocalDb.instance.closeForTest();
    try {
      await LocalDb.instance.init();
    } catch (e, st) {
      fail('半迁移库导致启动失败（这就是闪退原因）：$e\n$st');
    }
    await LocalDb.instance.closeForTest();
  });
}
