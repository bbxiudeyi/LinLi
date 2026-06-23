# 林立 (linli)

> 国产运动社交 App — 记录轨迹、结识同好、探索热门路线。

一个完整的运动记录平台，包含**手机 App + 网页版 + 云端后端**，三端共用同一套 API 和数据库。

## 架构总览

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  linli-app  │     │ linli-server │     │  linli-web  │
│  Flutter    │────▶│  Rust + Axum │◀────│  Vue 3      │
│  手机 App   │ HTTP│  + PostgreSQL│ HTTP │  网页版     │
│             │ JWT │  + PostGIS   │ JWT │             │
└─────────────┘     └──────────────┘     └─────────────┘
                            │
                     共用 Mapbox token
                     （三端通用）
```

| 项目 | 技术栈 | 目录 | 说明 |
|------|--------|------|------|
| **手机 App** | Flutter / Dart | `linli-app/` | 录制运动、地图轨迹、社交 |
| **后端** | Rust / Axum / sqlx | `linli-server/` | REST API + JWT 鉴权 |
| **网页版** | Vue 3 / TypeScript | `linli-web/` | 浏览器查看活动、登录注册 |
| **数据库** | PostgreSQL 16 + PostGIS | Docker 容器 | 轨迹用 LineString 存储 |

## 功能模块

| 模块 | App | 网页 | 说明 |
|------|:---:|:----:|------|
| 注册 / 登录 | ✅ | ✅ | 邮箱 + 密码，JWT 鉴权 |
| 运动记录 | ✅ | — | GPS 实时轨迹 + 渐隐尾巴效果 |
| 活动上传 | ✅ | — | 录完自动上传云端 |
| 活动详情 | ✅ | 🚧 | 统计数据 + Mapbox 轨迹地图 |
| 动态流 | ✅ | 🚧 | 关注的人的活动 |
| 个人资料 | ✅ | 🚧 | 编辑资料、查看统计 |
| 数据分析 | ✅ | — | 周/月/年图表 |
| 点赞 / 关注 | ✅ | 🚧 | 社交互动 |

## 快速开始（本地开发）

### 前置要求

- Flutter SDK >= 3.7.0
- Rust（stable）
- Node.js >= 20
- Docker Desktop

### 1. 启动数据库

```bash
cd linli-server
cp .env.example .env          # 编辑 .env 改 JWT_SECRET
docker compose up -d          # 启动 PostgreSQL + PostGIS
```

### 2. 启动后端

```bash
cd linli-server
cargo run                     # 监听 http://localhost:8080
```

### 3. 启动网页版

```bash
cd linli-web
npm install
npm run dev                   # 访问 http://localhost:5173
```

### 4. 启动手机 App

```bash
cd linli-app
flutter pub get
flutter run                   # 连接模拟器或真机
```

## 配置说明

### Mapbox Token

去 [Mapbox 账号页](https://account.mapbox.com/access-tokens/) 拿 public token，填入：

- **App**: `linli-app/lib/core/map/mapbox_config.dart`
- **网页**: `linli-web/` 构建时通过环境变量注入
- **后端**: 不需要（后端不渲染地图）

### 环境变量

| 变量 | 在哪配 | 说明 |
|------|--------|------|
| `DATABASE_URL` | `linli-server/.env` | PostgreSQL 连接串 |
| `JWT_SECRET` | `linli-server/.env` | JWT 签名密钥 |
| `CORS_ORIGINS` | `linli-server/.env` | 允许的前端源 |
| `MAPBOX_PUBLIC_TOKEN` | `linli-app/.../mapbox_config.dart` | App 的 Mapbox token |

## API 概览

所有接口前缀 `/api/v1`，详细列表见 [API 文档](linli-server/src/main.rs)（路由定义）。

| 方法 | 路径 | 鉴权 | 说明 |
|------|------|:----:|------|
| POST | `/auth/register` | ❌ | 邮箱密码注册 |
| POST | `/auth/login` | ❌ | 登录返回 JWT |
| POST | `/auth/logout` | ✅ | 撤销当前 token |
| GET | `/auth/me` | ✅ | 当前用户信息 |
| GET | `/activities` | ✅ | 我的活动列表 |
| POST | `/activities` | ✅ | 上传活动（含轨迹）|
| GET | `/activities/:id` | ✅ | 活动详情（含轨迹）|
| DELETE | `/activities/:id` | ✅ | 删除活动 |
| GET | `/feed` | ✅ | 关注流 |
| PATCH | `/users/me` | ✅ | 更新资料 |
| POST/DELETE | `/users/:id/follow` | ✅ | 关注/取关 |
| POST/DELETE | `/activities/:id/kudos` | ✅ | 点赞/取消 |

## 📚 文档

> 所有产品规则、设计规范的唯一事实来源。修改 UI/功能前，请先查阅对应文档。

### 产品文档

| 文档 | 内容 | 更新频率 |
|------|------|---------|
| [产品目标](docs/product-goals.md) | 产品定位、目标用户、核心价值、里程碑 | 低（战略级）|
| [产品功能](docs/product-features.md) | 功能清单、状态、优先级 | 高（迭代节奏）|

### 设计规范

| 文档 | 内容 | 适用范围 |
|------|------|---------|
| [设计系统](docs/design-system.md) | 颜色、字体、间距、圆角等通用规范 | **App + Web 通用** |
| [App 设计](docs/design-app.md) | 页面结构、交互、平台差异 | Flutter App |
| [Web 设计](docs/design-web.md) | 字体大小、字重、样式、响应式、组件 | Vue 网页版 |

### 部署运维

- [**DEPLOY.md**](DEPLOY.md)：完整部署手册（6 步 + 运维命令 + 排错）

### 文档维护约定

- 改 UI 前：先查 [设计系统](docs/design-system.md)，确认改动符合规范
- 加功能前：先查 [功能清单](docs/product-features.md)，确认是否在计划内
- 规范有变：改完代码**同步更新文档**

## 部署

生产环境部署到服务器，详见 **[DEPLOY.md](DEPLOY.md)**。

一键启动（4 个容器，约 1GB 内存）：

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

## 项目结构

```
linli/
├── linli-app/                 # Flutter 手机 App
│   ├── lib/
│   │   ├── app/               # 路由、主题、主壳
│   │   ├── core/              # 网络、数据库、地图配置
│   │   ├── features/          # 业务模块（auth/activity/feed/profile）
│   │   └── shared/            # 共享组件（地图等）
│   └── pubspec.yaml
│
├── linli-server/              # Rust 后端
│   ├── src/
│   │   ├── auth.rs            # JWT + 密码哈希 + 鉴权中间件
│   │   ├── handlers/          # API 处理函数
│   │   ├── models.rs          # 数据模型
│   │   └── main.rs            # 启动 + 路由
│   ├── migrations/            # 数据库建表 SQL
│   ├── Dockerfile
│   └── docker-compose.yml     # 本地开发（只起 DB）
│
├── linli-web/                 # Vue 3 网页版
│   ├── src/
│   │   ├── api/               # axios 封装
│   │   ├── stores/            # Pinia 状态
│   │   ├── router/            # Vue Router
│   │   └── views/             # 页面
│   ├── Dockerfile
│   └── nginx.conf
│
├── docker-compose.prod.yml    # 生产部署清单（4 服务）
├── Caddyfile                  # 反代 + HTTPS
├── .env.prod.example          # 生产环境变量模板
└── DEPLOY.md                  # 部署手册
```

## 安全特性

- ✅ JWT + token_version 撤销机制（登出/改密码后旧 token 立即失效）
- ✅ argon2 密码哈希
- ✅ 上传轨迹大小限制（防数据库撑爆）
- ✅ CORS 域名白名单（防恶意网站调 API）
- ✅ 错误信息脱敏（不泄露 SQL 细节）
- ✅ Caddy 自动 HTTPS + 安全头

## 技术栈速查

| 层 | 技术 |
|----|------|
| App | Flutter 3.7+ / Riverpod / go_router / Mapbox GL / geolocator |
| 后端 | Rust / Axum / sqlx / JWT / argon2 / PostgreSQL / PostGIS |
| 网页 | Vue 3 / Vite / TypeScript / Pinia / Vue Router / axios |
| 部署 | Docker Compose / Caddy / Let's Encrypt |

## 许可证

MIT
