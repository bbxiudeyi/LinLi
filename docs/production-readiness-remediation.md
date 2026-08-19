# 生产就绪整改清单

**复核日期：** 2026-07-13  
**范围：** `linli-app`、`linli-server`、`linli-web` 与相邻的 `linli_map`。  
**结论：** 当前版本仍是内测/MVP，不能开放真实用户的连续精确轨迹录制，也不能提交应用商店。技术栈可保留；先完成下列 P0，再继续社交、俱乐部和地图视觉功能。

本文件以当前工作区代码为准，而非历史审查路径。引用的“当前状态”是复核时观察到的事实；修复完成后应把验收证据（测试记录、真机记录、迁移结果）附到对应 PR。

## 2026-08-19 逐条核实与修复记录

**核实结论：** 上表 P0-1～P0-5、P1-1～P1-10 经代码逐条核实**全部属实**（P1-5 原本就是“部分修复”状态）。另发现一个上表未记录的 bug：`retryUnsynced` 把 SQLite 的 `is_private`（int 0/1）直接发给后端 `Option<bool>`，serde 反序列化失败——**离线补传路径一直是坏的**，已一并修复。

**已完成的代码修复**（均未提交，随本清单一起评审）：

| 编号 | 修复内容 | 主要文件 | 验证 |
| --- | --- | --- | --- |
| P0-1 | 本地库 schema v3：`activities` 加 `owner_user_id` + `lifecycle`，`my_profile` 改为按 `user_id` 主键；所有读写按当前账号过滤；登录/恢复/登出时切换活跃账号；存量无归属数据隔离为 `__legacy__`（不可见不可同步，提供 `purgeLegacyData()`）；未登录禁止写入 | `local_db.dart`、`auth_provider.dart` | `flutter test` 6/6（真实 SQLite：跨账号不可见/不可删、未登录禁写、资料分账号） |
| P0-2 | `lifecycle` 状态机（recording→saved→synced）；放弃= 事务删除，**失败不 reset 并提示重试**；待同步队列只收 `saved`；启动时清理僵尸 `recording` 行；保存页放弃后有明确反馈 | `local_db.dart`、`gps_tracker.dart`、`activity_provider.dart`、`activity_record_page.dart` | 同上（saved 过滤、僵尸清理、原子删除用例） |
| P0-3 | 服务端迁移 `2026081901_default_private.sql`：列默认改 `TRUE` + 存量公开活动全部转私密；`create_activity` 缺省私密；客户端保存页新增可见范围开关（默认私密），本地库 `is_private` 默认 1；修复 is_private int→bool 序列化 bug | `migrations/2026081901_default_private.sql`、`handlers/activity.rs`、`activity_provider.dart`、`activity_record_page.dart` | cargo 不可用，未编译验证（改动小，待 CI）；客户端随 flutter test |
| P0-4（代码部分） | geolocator `AndroidSettings.foregroundNotificationConfig`（常驻通知 + wake lock）；Android 补 FOREGROUND_SERVICE(_LOCATION)/POST_NOTIFICATIONS/WAKE_LOCK 权限；iOS 声明 `UIBackgroundModes: location` 并更新权限文案；计时真值改 `Stopwatch`（单调时钟），移动时间改 GPS 时间戳差 | `location_service.dart`、`AndroidManifest.xml`、`Info.plist`、`gps_tracker.dart` | **真机长时录制验证未做**（见下） |
| P0-5（结构部分） | `applicationId`/namespace 改为 `top.bbtech.linli`；release 签名从 `android/key.properties` 读取，**无 debug 回退**（缺配置产出未签名包）；新增 `key.properties.example` 与 .gitignore 规则（`*.jks`/`key.properties` 不入库） | `build.gradle.kts`、`key.properties.example`、`.gitignore` | **正式 keystore 未生成**（见下） |
| P1-1 | `TujiApp` 根部 watch `authProvider`：冷启动即恢复登录态、切换数据归属并触发 `retryUnsynced` | `app.dart` | flutter analyze/test |
| P1-2（最小版） | 云端删除失败时**不再物理删本地**，UI 提示重试；从未同步过的活动才允许直接删本地 | `activity_provider.dart`、`activity_detail_page.dart` | flutter analyze |
| P1-3 | 资料 PATCH 全字段 COALESCE：只传头像不再清空 bio/gender/birthday/weight_kg | `handlers/social.rs` | cargo 不可用，待 CI |
| P1-5（部分） | 服务端新增：经纬度范围/有限数、海拔、速度合理性校验；title/description 长度上限 | `handlers/activity.rs` | 同上 |
| P1-8（部分） | tileserver-gl 镜像从 `:latest` 固定为 `v5.6.0` | `linli_map/docker-compose.yml` | 需重新 `docker compose up -d` 生效 |
| P1-9 | 预览页开启 attributionControl；style.json 数据源加 OSM/ODbL 署名 | `linli_map/web/index.html`、`styles/style.json` | JSON 已校验；**生产 App 端 MapLibre 归因显示待核验** |
| P1-10（部分） | 删除占位 `widget_test.dart`；新增 `local_db_test.dart`（sqflite_common_ffi 真实 SQLite，覆盖 P0-1/P0-2 验收核心）；`flutter analyze` 存量 6 项告警清零（含 RadioListTile→RadioGroup 迁移） | `test/local_db_test.dart`、`edit_profile_page.dart`、`profile_provider.dart` | flutter analyze 0 issues；flutter test 6/6 通过 |

**2026-08-19 本地验证记录：**

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 通过，0 issues（清理了 2026-07-13 记录的 6 项存量告警） |
| `flutter test` | 6/6 通过（新增真实 SQLite 测试，替换占位测试） |
| Rust test/fmt/clippy | 未执行（本机无 cargo；CI 必须补） |
| Rust 改动 | `activity.rs`/`social.rs`/新迁移——改动小但**未经编译**，合入前需 CI 或本地 cargo check |
| Web build | 未执行（本次未改 Web 端） |

**修复后仍开放的事项（发布闸门未解除）：**

1. **P0-4 真机验收**：Android/iOS 各 8–12 小时锁屏/后台/弱网/低电量录制验证 + 权限降级场景；Android 13+ 还需运行时申请 POST_NOTIFICATIONS（当前仅声明）。
2. **P0-5 密钥与 CI**：按 `android/key.properties.example` 生成正式 keystore；iOS 签名证书配置；干净 CI 构建 AAB/IPA。
3. **P0-1/P1-4 加密**：本地库与 JWT 目前仍是明文（方案已选“单库+owner”，加密密钥存 Keychain/Keystore 属第二阶段）。
4. **P0-3 法务**：隐私政策、单独同意、数据导出/注销流程需法务确认；`visibility` 三档枚举、隐私区裁剪、共享轨迹抽稀仍在第二阶段。
5. **存量迁移验证**：v2→v3 迁移（legacy 隔离）需在装过旧版的真机上回归一次。
6. **部署生效**：服务端迁移与默认私密需随下次 `docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build` 生效；linli_map 镜像固定版本需重拉。


## 发布闸门

在以下条件全部满足前，版本只能用于隔离的内部测试账号，且不得导入真实用户轨迹：

1. P0-1 至 P0-5 完成，并由自动化测试和真机测试证明。
2. 所有遗留的无归属本地数据已清除或隔离，**绝不能**在登录后自动归给当前账号。
3. 隐私政策、单独同意、数据导出与注销流程经有资质的法务/合规人员确认。
4. Android 与 iOS 的正式签名包能从干净的 CI 环境构建、安装和升级。

## 本次复核结果

| 编号 | 优先级 | 当前状态与证据 | 处置结论 |
| --- | --- | --- | --- |
| P0-1 | P0 | SQLite `activities` 与 `activity_points` 无 `owner_user_id`，`my_profile` 固定为单行 `id=1`；退出只清 JWT。见 `linli-app/lib/core/db/local_db.dart` 与 `features/auth/providers/auth_provider.dart`。 | 未解决；同设备换账号会看到、上传或删除他人本地数据。 |
| P0-2 | P0 | 已有未提交的局部修复：`discard()` 会事务删除活动和点。见 `features/activity/services/gps_tracker.dart`。但删除失败仍会重置内存、没有持久化状态/重试，保存页也没有返回导航；缺少“放弃后绝不上传”的竞态测试。 | 部分修复，不能关闭风险。保留现有改动，按下文状态机重做收口。 |
| P0-3 | P0 | 服务端数据库默认 `is_private = FALSE`，客户端上传不传 `is_private`；公开活动详情向任意已登录用户返回完整点、时间与速度。见 `migrations/001_init.sql`、`handlers/activity.rs`、`activity_provider.dart`。 | 未解决；默认公开的精确轨迹不可发布。 |
| P0-4 | P0 | Android 仅请求前台定位，iOS 仅有 `NSLocationWhenInUseUsageDescription`；录制依赖 Dart `Timer` 和位置流。见 Android Manifest、`Info.plist`、`gps_tracker.dart`。 | 未解决；锁屏、Doze、低电量和进程回收均可能静默中断。 |
| P0-5 | P0 | Android 命名空间与 `applicationId` 仍是 `com.example.linli`，release 使用 debug 签名。见 `android/app/build.gradle.kts`。 | 未解决；不能形成可信的商店升级链。 |
| P1-1 | P1 | `authProvider` 未在应用根部监听；冷启动进入已登录页面时不保证调用 `retryUnsynced()`。`loadMyActivities()` 也没有正常入口。见 `app.dart`、`router.dart`、`activity_provider.dart`。 | 未解决；同步和云端历史恢复不可靠。 |
| P1-2 | P1 | 云端删除失败后本地仍物理删除；下次 `/activities` 刷新又会写回本地。没有 tombstone、重试次数或退避。见 `activity_provider.dart`。 | 未解决；离线删除会复活。 |
| P1-3 | P1 | 资料 PATCH 对 `bio/gender/birthday/weight_kg` 直接赋值；客户端缺字段会写成 `NULL`。见 `handlers/social.rs`。 | 未解决；局部更新可能清空资料。 |
| P1-4 | P1 | JWT 存于 `SharedPreferences`，本地活动与资料为明文 SQLite。见 `core/network/api_client.dart`、`core/db/local_db.dart`。 | 未解决；需采用平台安全存储及加密数据库/密钥管理。 |
| P1-5 | P1 | 活动上传已校验类型、点数、距离和时长上限，并有事务与客户端 ID 幂等处理；但未校验经纬度、有限数、时间单调、速度/海拔合理性、文本长度，也没有登录限流。见 `handlers/activity.rs`、`models.rs`、`main.rs`。 | 部分修复；仍不可相信输入。 |
| P1-6 | P1 | 距离、配速、爬升、热量均由客户端入库；GPS 在准备页已把首点加入内存，录制时每个点复制整个列表；暂停/恢复与海拔噪声没有完整算法保障。见 `gps_tracker.dart`。 | 未解决；排行榜和长记录的准确性、性能均不足。 |
| P1-7 | P1 | App 只加载公网 Style URL；没有区域包、下载、校验、空间预算或离线回退。见 `core/map/map_config.dart`。 | 未解决；户外弱网不可用。 |
| P1-8 | P1 | 地图 Compose 使用 `:latest`，文档使用 Tilemaker `master`，数据文件名固定为 `china.mbtiles`，无数据清单、checksum、原子切换或回滚。Style 也硬编码生产域名。见 `linli_map/docker-compose.yml`、`DEPLOYMENT-PLAN.md`、`styles/style.json`。 | 未解决；地图供应链不可复现。 |
| P1-9 | P1 | 地图预览关闭 attribution；Style/TileJSON 未声明 OSM 署名。见 `linli_map/web/index.html`、`styles/style.json`。 | 未解决；上线前须完成署名和许可义务核验。 |
| P1-10 | P1 | Flutter 测试只有 `expect(true, isTrue)`；Rust 未见测试；Web 没有 test/lint 脚本；地图 `npm test` 固定失败。 | 未解决；目前没有可靠回归门禁。 |

## 第一阶段：停止扩功能并关闭 P0

### P0-1 本地数据按账号隔离

**目标：** 任一账号绝不能读取、同步、删除或覆盖另一个账号的数据。

1. 采用“每个已认证用户一个本地数据库”的方案：数据库路径使用不可逆的用户 ID 派生值；数据库加密密钥只保存在 Keychain/Keystore。所有 repository API 都显式接收当前 `userId`，不得再有全局无用户上下文的 `LocalDb.instance`。
2. 若保留单库，替代方案是所有表都加入 `owner_user_id NOT NULL`，所有查询、更新、删除和唯一索引都带它；`my_profile` 的主键改为 `user_id`。两种方案只能选一种，禁止混用。
3. 录制开始前验证认证态和数据库所属账号；账号切换时停止当前录制、关闭数据库句柄并清除内存缓存。
4. 版本迁移中检测旧的无归属库。内测数据可在发布前清除；如必须保留，先隔离为不可展示、不可上传的 legacy 数据，经过人工确认的导出/恢复流程处理。不得把旧数据自动绑定给下一位登录者。

**验收：**

- A 离线录制后登出，B 登录同一设备：B 的活动、资料、待发送队列均为空，且网络 mock 中不存在 A 活动使用 B token 的请求。
- B 删除自己的活动后，A 再登录仍能得到 A 的原始数据。
- 数据迁移测试覆盖 v2 数据库、空库、迁移中断和 legacy 数据；所有 legacy 行都不具备可同步资格。

### P0-2 草稿与放弃操作的持久化状态机

**目标：** “放弃”绝不出网；崩溃后可恢复或可明确丢弃，不产生僵尸活动。

1. 将状态收敛为持久化枚举：`recording`、`draft`、`pending_upload`、`synced`、`pending_delete`、`failed`、`discarded`。迁移时增加状态、失败码、重试次数、下次重试时间、更新时间与租约字段。
2. 将“停止定位/暂停写入 → 排空点写队列 → 原子更新或删除 DB 行 → 更新 UI”封装为单一命令，不允许 UI 直接组合这些步骤。
3. 放弃操作首先取得活动租约，取消定位订阅和所有未完成写入；随后在同一事务中标记 `discarded` 并删除点/主记录。只有事务成功后才 reset 和导航；失败须显示“未能丢弃，稍后重试”，不得假装成功。
4. 上传 worker 只领取 `pending_upload`；放弃动作与上传动作必须通过同一租约/事务互斥。App 重启时清理未完成的 `recording` 或提示继续/放弃。

**验收：**

- 在写点、点“放弃”、上传开始三个时刻交错执行 100 次，服务端均不收到被放弃的活动。
- 在每个状态注入崩溃后重启：不会有孤儿点、不会上传 `discarded`，且用户能看到准确的恢复提示。
- 保存页的放弃按钮完成后回到安全页面，不能停留在已 reset 的保存视图。

### P0-3 轨迹隐私与个人信息权利

**目标：** 精确原始轨迹和时间序列仅活动所有者可读取；新活动默认私密。

1. 将 `is_private` 演进为 `visibility`（至少 `private`、`followers`、`public`），数据库默认 `private`，服务端默认也必须是 `private`。客户端保存页必须显示明确的可见范围控件，不能依赖缺省值。
2. 为用户加入私密账号、关注审批、移除关注者和拉黑模型。所有 feed、活动详情、GPX、点赞和通知接口共用一个授权策略，禁止各端自行判断。
3. 保存原始轨迹与对外轨迹两份表示：原始点只向所有者返回；非所有者只得到按可见范围生成的抽稀、延迟并裁剪起终点的轨迹。GPX 默认仅所有者可导出。
4. 增加住宅隐私区：用户可设置中心和半径；生成共享轨迹时裁掉两端落入区域的点。没有足够点时不共享路线。服务端测试必须覆盖穿越隐私区、单端命中、双端命中和跨越边界。
5. 上线前实现隐私说明、单独同意记录、撤回同意、数据导出、账号注销、数据删除/保留策略，并由法务核验连续定位数据、地图服务和跨境/存储要求。

**验收：**

- 新建活动未选择公开时，数据库和 API 都为 `private`。
- 非所有者枚举 ID、关注、点赞、导出 GPX、直接请求详情均无法得到完整点、时间或速度。
- 公开活动的返回轨迹不含设定隐私区内的起终点；所有者仍可获得完整原始轨迹。

### P0-4 后台/锁屏录制

**目标：** 用户明确开始后，在平台允许的条件下，锁屏和后台连续记录，并对中断可见、可恢复。

1. Android：实现带常驻通知的 location foreground service；声明并在目标 Android 版本上验证所需的 foreground-service/location 权限、通知权限和定位权限。不得由 Dart `Timer` 作为唯一计时真相。
2. iOS：启用 Location updates background mode，按实际产品需求请求合适的位置授权，并用 Core Location 的时间戳/原生持久状态恢复录制。权限文案要说明后台录制目的。
3. 计时基于单调时钟或 GPS 时间戳，暂停区间明确排除；每个点的写入有有界队列、批量提交和断电恢复策略。
4. 对权限降级、定位关闭、电量限制、网络切换、系统杀进程、重启和时钟变更建立可观测事件与用户提示。

**验收：**

- Android 与 iOS 真机各至少 8–12 小时：锁屏、后台、弱网、来电/低电量模式后轨迹、时长和状态符合预期。
- 强制结束后重启可识别未完成记录，数据不串、不重复，用户能继续或放弃。
- 自动测试覆盖计时、暂停、恢复、写队列和恢复决策；真机报告记录机型、系统版本、权限状态、电量与失败原因。

### P0-5 正式发布制品与最小 CI

1. 注册唯一 Android `applicationId`、iOS bundle identifier、正式图标与版本策略；删除 debug signing fallback。
2. 在 CI 的受保护密钥库中配置 Android upload key/Play App Signing 和 iOS distribution signing；密钥、证书、`*.jks`、`*.p12`、环境文件绝不入库或出现在日志。
3. 增加 PR 门禁：格式化、静态分析、单元/集成测试、依赖漏洞检查和可重复的 release build。受保护分支只接受通过门禁的变更。
4. 先在内部测试轨道验证安装、升级、登录、录制、后台恢复、登出和数据隔离，再创建商店提交。

**验收：** 干净 CI runner 从锁定依赖构建带正式签名的 AAB/IPA；安装旧内部版本并升级后账号和本地数据迁移符合 P0-1 的规则。

## 第二阶段：同步、计算与安全收口（P1）

### 同步与云端恢复

1. 在应用根部初始化认证和同步协调器；仅在认证成功且用户库已打开后启动 outbox。监听网络恢复和应用前台事件，但禁止并发重复 worker。
2. 用 outbox + tombstone 取代“失败也物理删除”：删除先持久化为 `pending_delete`，服务端确认后再回收；服务端列表合并时尊重 tombstone，直至删除确认或过期策略触发人工处理。
3. 为上传/删除持久化 idempotency key、指数退避、最大次数、可观测错误和手动重试。列表使用游标和同步水位；远端历史可分页恢复并缓存详情/点。
4. 定义冲突规则（同 ID 重传、服务器已删除、客户端改名/可见性、版本不兼容），以契约测试固定下来。

**验收：** 飞行模式下创建、保存、删除、重装、登录第二设备、网络多次切换后，活动只出现一次，删除不复活，且所有请求归属正确账号。

### 服务端输入、授权与指标计算

1. 给登录、注册、头像上传、搜索和活动 API 加基于 IP/账号的限流、大小限制、超时、结构化审计与告警；错误消息不得泄漏账号是否存在。
2. 对每个轨迹点校验有限数、纬度 `[-90, 90]`、经度 `[-180, 180]`、时间单调性、与活动起止时间关系、单段速度/距离/海拔变化合理范围；限制 title、description、nickname 和搜索词长度。
3. 服务端从原始点重算距离、移动时间、配速、爬升和热量，保存 `calculation_version` 与原始输入审计信息。客户端数值只作为显示预估，不能进入排名/统计权威值。
4. 修复资料 PATCH：使用可区分“字段缺失”和“显式清空”的请求类型/JSON Patch，所有字段均使用相同语义；增加长度、生日、体重和 URL 校验。

**验收：** 属性测试和 API 集成测试拒绝 NaN/Infinity、越界坐标、倒退时间、超速跳点、超长文本与高频登录；只改头像不会清空任何资料字段；伪造客户端总计不会影响服务端权威统计。

### GPS 算法、性能与离线地图

1. 录制仅从用户确认“开始”后写入正式轨迹；准备阶段定位用于地图 puck，不能进入活动点序列。暂停后重置距离段基准，避免跨暂停连线。
2. 以时间/精度/速度联合规则过滤漂移；爬升使用平滑或阈值算法；用真实轨迹夹具测试跑步、骑行、静止、隧道、GPS 跳点和暂停恢复。
3. 内存中使用分块/环形点缓冲，地图增量更新而不是每点复制全列表并序列化全量 GeoJSON；长时间录制设置内存、CPU、耗电和渲染帧率预算。
4. 设计离线区域包：选择区域/缩放级别、下载队列、hash 校验、原子安装、过期/清理、存储配额、样式版本兼容与离线回退 UI。先完成一省/城市的端到端试点，再扩展全国。

**验收：** 4、8、12 小时轨迹压测不出现 O(n²) 级内存/渲染退化；在无网络下已下载区域能加载底图和已缓存活动；未下载区域明确告知限制而非空白失败。

## 第三阶段：地图供应链、运维与交付质量

### 地图供应链

1. 新增 `dataset-manifest.yaml`，记录每份 OSM/DEM/POI 数据的来源、许可、取得时间、bbox、SHA-256、工具镜像 digest、样式/Schema 版本和产物版本。
2. 将 `maptiler/tileserver-gl:latest` 与 Tilemaker `master` 改为固定版本和镜像 digest。构建过程在干净环境运行并产出可复验的 manifest。
3. 产物使用版本目录（如 `releases/2026-07-13-<hash>/`）；上传后做 SHA-256、MBTiles SQLite integrity check、抽样瓦片/TileJSON/Style 健康检查，最后原子切换 `current`，至少保留上一版供回滚。
4. Style 使用环境化或相对资源 URL，使本地、staging、production 各自加载同域 TileJSON 和字体；预览页启用 attribution，Style/TileJSON 添加需要的 OSM/数据源署名及许可信息。
5. 在“户外”命名之前，补齐经合法数据源验证的等高线、地形/阴影、山峰、饮水点、避难设施、步道/路面和通行难度；每层有缩放级别、性能预算与视觉回归截图。
6. 公开提供中国地图前，完成测绘、地图审核/审图号、服务器与数据备案等专项法律合规评估；未获确认前限制为非公开内部环境。

**验收：** 可从 manifest 重建同版本瓦片；故意损坏产物无法发布；一次原子升级和回滚不会产生半加载瓦片；本地预览没有请求生产域名；所有 MapLibre 入口显示正确署名。

### 可观测性、灾备与测试矩阵

1. 引入崩溃、ANR、录制中断、同步失败、API 延迟/错误率、地图瓦片命中率和队列积压监控；所有移动端/服务端请求携带关联 ID，日志不得记录 JWT、精确轨迹或密码。
2. 定义录制、同步、API 与地图 SLO/错误预算，设置值班告警和事故响应手册。
3. 数据库、上传文件、地图产物进行加密备份；设定保留周期、密钥轮换、异地副本和至少季度恢复演练。
4. 补齐测试层次：Dart 单元/组件/集成测试，Rust 单元/API/数据库迁移测试，Web lint/type/build/组件测试，地图 JSON/schema/视觉/容器冒烟测试；将每层接入 CI。

## 建议的实施顺序与 PR 切分

1. **PR-1：发布冻结与基线 CI。** 固化工具版本，清理 Flutter 当前 6 项告警，增加可运行测试脚本与最小质量门禁。
2. **PR-2：账号隔离迁移。** 先完成 P0-1 和全套多账号回归；此 PR 合入前不改同步协议。
3. **PR-3：草稿/outbox/tombstone。** 完成 P0-2 与 P1 同步模型，覆盖断电、放弃、删除、重试和恢复。
4. **PR-4：隐私与授权。** 数据迁移先默认私密，再发布 API 授权、共享轨迹裁剪和客户端可见范围 UI；隐私权利接口与法务材料同一发布闸门。
5. **PR-5：后台录制与真机验收。** Android、iOS 分开交付，附长时测试证据后才允许下一 PR。
6. **PR-6：正式签名、内部测试和发布演练。** 与 P0 回归一起完成。
7. **PR-7 以后：** 服务端重算与限流、GPS 算法/性能、离线地图、地图供应链、可观测性与灾备。

每个 PR 必须包含：数据库迁移的向前/回退说明、威胁模型变化、自动化测试、监控字段变化和更新后的发布闸门结果。不要把 P0 与社交或视觉重构混在同一个 PR。

## 本地验证记录（2026-07-13）

| 检查 | 结果 | 说明 |
| --- | --- | --- |
| `flutter analyze` | 已执行，报告 6 项诊断 | 4 个已废弃的 `Radio` API 提示，另有 1 个未使用 import 和 1 个未使用字段；应在 PR-1 清零或显式设定质量门槛。 |
| `flutter test` | 通过 | 仅执行了一个占位 smoke test（`expect(true, isTrue)`），不构成业务回归。 |
| `git diff --check` | 通过 | 复核时已有的 3 个录制/地图未提交修改未被改动。 |
| Rust test/fmt/clippy | 未执行 | 当前环境未安装 `cargo`；CI 必须安装并强制执行。 |
| Web build | 未完成 | 依赖安装状态不完整，`vue-tsc` 不可执行；应在干净 CI runner 用 lockfile 重现。 |
| Server 与 Map Compose config | 通过 | 两个 Compose 文件可解析；未启动 Docker 引擎进行容器集成测试。 |
| 地图 Style/config 校验 | 通过 | JSON 与 config 脚本通过；`npm test` 仍是固定失败的占位脚本。 |
