// 本地数据库核心行为的回归测试（P0-1 账号隔离 / P0-2 状态机）。
//
// 运行：flutter test test/local_db_test.dart
// 桌面端用 sqflite_common_ffi 提供真实的 SQLite 实现（非 mock），
// 验证的是真实 SQL 行为，包括 owner 过滤与生命周期过滤。
import 'package:flutter_test/flutter_test.dart';
import 'package:linli/core/db/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // 每个用例用全新的数据库文件（独立文件名，避免与其他并行测试文件互踩）
    const dbName = 'linli_test_local.db';
    LocalDb.testDbFileName = dbName;
    final dbPath = await getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dbPath, dbName));
    await LocalDb.instance.closeForTest();
    await LocalDb.instance.init();
  });

  tearDown(() async {
    await LocalDb.instance.closeForTest();
  });

  Map<String, dynamic> activity(String id) => {
        'id': id,
        'type': 'run',
        'start_time': '2026-08-19T02:00:00Z',
        'created_at': '2026-08-19T02:00:00Z',
      };

  group('P0-1 账号隔离', () {
    test('B 登录后看不到、删不掉、也同步不到 A 的本地活动', () async {
      const userA = '11111111-1111-1111-1111-111111111111';
      const userB = '22222222-2222-2222-2222-222222222222';
      const activityId = 'aaaaaaaa-0000-0000-0000-000000000001';

      await LocalDb.instance.setActiveUser(userA);
      await LocalDb.instance.insertActivity(activity(activityId));
      await LocalDb.instance.appendPoint(activityId, 0, 39.9, 116.4,
          recordedAt: '2026-08-19T02:00:01Z');
      await LocalDb.instance.appendPoint(activityId, 1, 39.901, 116.401,
          recordedAt: '2026-08-19T02:00:03Z');
      // 用户已保存（markSaved）：模拟真实场景——只有保存过的活动
      // 才会在重启/切换账号后继续存在（recording 会被僵尸清理，见 P0-2 组）
      await LocalDb.instance.markSaved(activityId, isPrivate: true);

      // 切换到 B：一切对 A 数据的访问都不可见
      await LocalDb.instance.setActiveUser(userB);
      expect(await LocalDb.instance.listActivities(), isEmpty);
      expect(await LocalDb.instance.getActivity(activityId), isNull);
      expect(await LocalDb.instance.getPoints(activityId), isEmpty);
      expect(await LocalDb.instance.getUnsyncedActivities(), isEmpty);
      expect(await LocalDb.instance.countActivities(), 0);

      // B 的删除不能影响 A 的数据（owner 过滤）
      await LocalDb.instance.deleteActivity(activityId);

      // A 重新登录，数据原封不动
      await LocalDb.instance.setActiveUser(userA);
      final list = await LocalDb.instance.listActivities();
      expect(list, hasLength(1));
      expect(list.first['id'], activityId);
      expect(await LocalDb.instance.getPoints(activityId), hasLength(2));
    });

    test('未登录（无活跃账号）时禁止写入、查询返回空', () async {
      await LocalDb.instance.setActiveUser(null);
      expect(
        () => LocalDb.instance.insertActivity(activity('x-1')),
        throwsStateError,
      );
      expect(await LocalDb.instance.listActivities(), isEmpty);
      expect(await LocalDb.instance.getMyProfile(), isNull);
    });

    test('资料缓存按账号分开，互不串读', () async {
      const userA = '11111111-1111-1111-1111-111111111111';
      const userB = '22222222-2222-2222-2222-222222222222';

      await LocalDb.instance.setActiveUser(userA);
      await LocalDb.instance
          .saveMyProfile({'email': 'a@x.com', 'nickname': 'A'});

      await LocalDb.instance.setActiveUser(userB);
      expect(await LocalDb.instance.getMyProfile(), isNull);
      await LocalDb.instance
          .saveMyProfile({'email': 'b@x.com', 'nickname': 'B'});

      await LocalDb.instance.setActiveUser(userA);
      final a = await LocalDb.instance.getMyProfile();
      expect(a?['nickname'], 'A');
      expect(a?['id'], userA);
    });
  });

  group('P0-2 生命周期', () {
    test('只有用户保存过（saved）且未同步的活动才进入待同步队列', () async {
      const user = '11111111-1111-1111-1111-111111111111';
      const id = 'bbbbbbbb-0000-0000-0000-000000000002';
      await LocalDb.instance.setActiveUser(user);

      // 录制中：不进入待同步（防止被放弃的活动上传）
      await LocalDb.instance.insertActivity(activity(id));
      expect(await LocalDb.instance.getUnsyncedActivities(), isEmpty);

      // 用户点了保存：进入待同步
      await LocalDb.instance.markSaved(id, isPrivate: true);
      final pending = await LocalDb.instance.getUnsyncedActivities();
      expect(pending, hasLength(1));
      expect(pending.first['is_private'], 1);

      // 同步成功后出队
      await LocalDb.instance.markSynced(id);
      expect(await LocalDb.instance.getUnsyncedActivities(), isEmpty);
    });

    test('重启清理僵尸录制：lifecycle=recording 的行被删除', () async {
      const user = '11111111-1111-1111-1111-111111111111';
      const zombie = 'cccccccc-0000-0000-0000-000000000003';
      const saved = 'dddddddd-0000-0000-0000-000000000004';

      await LocalDb.instance.setActiveUser(user);
      await LocalDb.instance.insertActivity(activity(zombie));
      await LocalDb.instance.insertActivity(activity(saved));
      await LocalDb.instance.markSaved(saved, isPrivate: true);

      // 模拟 App 重启：再次设置同一账号触发清理
      await LocalDb.instance.setActiveUser(user);

      expect(await LocalDb.instance.getActivity(zombie), isNull,
          reason: '僵尸录制行应被清理');
      expect(await LocalDb.instance.getActivity(saved), isNotNull,
          reason: '已保存的活动必须保留');
    });

    test('deleteActivity（放弃路径）原子删除活动行与轨迹点', () async {
      const user = '11111111-1111-1111-1111-111111111111';
      const id = 'eeeeeeee-0000-0000-0000-000000000005';
      await LocalDb.instance.setActiveUser(user);
      await LocalDb.instance.insertActivity(activity(id));
      await LocalDb.instance.appendPoint(id, 0, 39.9, 116.4);
      await LocalDb.instance.appendPoint(id, 1, 39.901, 116.401);

      await LocalDb.instance.deleteActivity(id);

      expect(await LocalDb.instance.getActivity(id), isNull);
      expect(await LocalDb.instance.getPoints(id), isEmpty);
      // 点表里也不留孤儿（直接查库验证）
      final orphans = await LocalDb.instance
          .rawQuery('SELECT COUNT(*) AS c FROM activity_points');
      expect(orphans.first['c'], 0);
    });
  });
}
