# 林立 (linli)

> 国产运动社交 App — 记录轨迹、结识同好、探索热门路线。

一个用 Flutter 构建的运动社交应用，仿照 Strava / Keep 的核心体验，主打户外运动记录 + 社区互动 + 数据可视化。

## 功能模块

| 模块 | 说明 |
|------|------|
| **认证** | 注册 / 登录 |
| **运动记录** | GPS 轨迹记录（跑步 / 骑行 / 徒步等），实时绘制路径 |
| **信息流** | 社区动态，关注其他用户的活动 |
| **数据分析** | 个人运动数据可视化（图表） |
| **路段探索** | 发现热门路线 / 路段 |
| **个人资料** | 资料编辑、主页、统计 |

## 技术栈

| 类别 | 选型 |
|------|------|
| 框架 | Flutter 3.7+ / Dart |
| 状态管理 | Riverpod 2.6（含代码生成） |
| 路由 | go_router 14 |
| 后端 | Supabase 2.8（开发期本地用 sqflite 替代） |
| 地图 | Mapbox GL（注释说明高德 3.0.0 与新版 Flutter 不兼容） |
| 定位 | geolocator |
| 图表 | fl_chart |
| 本地存储 | sqflite + shared_preferences |
| 工具 | dio（HTTP）、freezed（不可变模型）、image_picker、permission_handler |

## 快速开始

### 环境要求

- Flutter SDK >= 3.7.0
- Dart SDK >= 3.7.0
- Android Studio / Xcode（按平台二选一）
- Mapbox 账号（用于地图 access token）

### 安装与运行

```bash
# 1. 拉依赖
flutter pub get

# 2. 配置 Mapbox（见下方"配置说明"）

# 3. 跑起来（自动连接当前设备 / 模拟器）
flutter run
```

### 配置说明

项目使用 Mapbox 显示地图，需要配置 access token：

1. 去 [Mapbox 账号页](https://account.mapbox.com/access-tokens/) 拿一个 public token
2. 在 `lib/core/map/mapbox_config.dart` 中填入

> ⚠️ **不要把 token 硬编码提交到仓库**。建议改用 `.env` + `flutter_dotenv` 管理。

## 项目结构

```
lib/
├── main.dart                    # 入口
├── app/                         # 应用框架（路由 / 主题 / 主壳）
│   ├── app.dart
│   ├── main_shell.dart
│   ├── router.dart
│   ├── theme.dart
│   └── theme_provider.dart
├── core/                        # 基础设施
│   ├── database/                # 本地 DB / Supabase 客户端
│   ├── location/                # 定位服务
│   ├── map/                     # Mapbox 配置 / 坐标工具
│   └── utils/                   # 工具
└── features/                    # 业务模块
    ├── auth/                    # 登录注册
    ├── activity/                # 运动记录（GPS 轨迹）
    ├── feed/                    # 信息流
    ├── analytics/               # 数据分析
    ├── segment/                 # 路段探索
    └── profile/                 # 个人资料
```

每个 feature 模块内部约定结构：`pages/`（页面）、`providers/`（状态）、`services/`（服务）、`models/`（模型）。

## 数据库

- **本地**：sqflite（开发期替代 Supabase，单机可用）
- **云端**：Supabase（待切换），迁移文件在 `supabase/migrations/`

## 路线图 / TODO

- [ ] Supabase 正式接入（替换本地 sqflite）
- [ ] iOS 签名 / 上架配置
- [ ] Android 签名 / 上架配置
- [ ] App 图标 / 启动图标准化
- [ ] Mapbox token 改为环境变量管理
- [ ] README 文档完善
- [ ] 单元测试覆盖

## 已知问题

- pubspec 里 `applicationId` 仍为 `com.example.linli`（未改）
- `android/app/build.gradle.kts` 的 release 还在用 debug key 签名
- README 之前是 Flutter 模板，已在本版本重写

## 许可证

MIT（待定）