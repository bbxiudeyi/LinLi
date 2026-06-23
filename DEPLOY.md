# 林立 App 服务器部署手册

> 适用于 2C2G Linux 服务器的完整部署流程。

## 架构总览

```
                    ┌─────────────────────┐
                    │   你的服务器 2C2G   │
                    │                     │
  Flutter App ──────┤  Caddy (443/80)     │  ← 自动 HTTPS
       手机         │   ├─ /api/* → api   │
                    │   └─ /*    → web    │
  Vue 网页 ─────────┤                     │
     浏览器         │  api (Rust:8080)    │
                    │   ↑                 │
                    │  web (nginx:80)     │
                    │   ↑                 │
                    │  db (Postgres:5432) │
                    └─────────────────────┘
```

4 个容器，总内存占用约 1GB（2GB 服务器留 1GB 缓冲）。

---

## 前置准备（在本地电脑做）

### 1. 把代码上传到 Git

```bash
# 在 d:\linli 目录
git add .
git commit -m "准备部署"
git push origin main
```

### 2. 确认域名 DNS 已指向服务器

在域名注册商后台设置：
- A 记录 `www` → 你的服务器公网 IP
- 等待 DNS 生效（用 `nslookup www.bbtech.com` 验证）

---

## 服务器部署（在服务器上做）

### 第 1 步：SSH 登录服务器

```bash
ssh root@你的服务器IP
```

### 第 2 步：安装 Docker

```bash
# 一键安装 Docker + Docker Compose
curl -fsSL https://get.docker.com | sh

# 验证
docker --version
docker compose version
```

### 第 3 步：拉取代码

```bash
cd /opt
git clone 你的仓库地址 linli
cd linli
```

### 第 4 步：配置环境变量

```bash
# 复制模板
cp .env.prod.example .env.prod

# 编辑（必须改这几个值）
vim .env.prod
```

**必须修改的项**：
```env
DOMAIN=www.bbtech.com                          # 你的域名

# 用下面两条命令生成随机值，替换进 .env.prod
DB_PASSWORD=$(openssl rand -base64 24)         # 数据库密码
JWT_SECRET=$(openssl rand -base64 32)          # JWT 密钥

CORS_ORIGINS=https://www.bbtech.com            # 你的网页域名（带 https://）
MAPBOX_TOKEN=pk.你的mapbox_public_token        # Mapbox token
```

生成密码的快捷方式：
```bash
echo "DB_PASSWORD=$(openssl rand -base64 24)"
echo "JWT_SECRET=$(openssl rand -base64 32)"
```

### 第 5 步：启动所有服务

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

**首次启动**：
- 编译 Rust 后端（约 10-15 分钟，在容器内编译）
- 构建 Vue 网页（约 2-3 分钟）
- 启动数据库 + 迁移建表
- Caddy 申请 HTTPS 证书（Let's Encrypt）

**预期输出**：
```
[+] Running 5/5
 ✔ Network linli_linli-net  Created
 ✔ Container linli-db        Started
 ✔ Container linli-api       Started
 ✔ Container linli-web       Started
 ✔ Container linli-caddy     Started
```

### 第 6 步：验证部署

```bash
# 看所有容器状态（都应该是 Up）
docker compose -f docker-compose.prod.yml ps

# 看后端日志（确认启动成功）
docker compose -f docker-compose.prod.yml logs api | tail -20

# 测试 API
curl https://www.bbtech.com/api/v1/health

# 浏览器打开网页
# https://www.bbtech.com → 应该看到登录页
```

---

## 常用运维命令

```bash
# 查看所有服务状态
docker compose -f docker-compose.prod.yml ps

# 实时查看所有日志
docker compose -f docker-compose.prod.yml logs -f

# 只看某个服务日志
docker compose -f docker-compose.prod.yml logs -f api

# 重启某个服务
docker compose -f docker-compose.prod.yml restart api

# 更新代码后重新部署
git pull
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build

# 停止所有服务（数据保留）
docker compose -f docker-compose.prod.yml down

# 停止并删除数据（⚠️ 慎用，会丢所有用户数据）
docker compose -f docker-compose.prod.yml down -v
```

---

## 数据库备份（重要！）

### 手动备份

```bash
# 备份到文件
docker exec linli-db pg_dump -U postgres linli > backup_$(date +%Y%m%d).sql

# 从备份恢复
cat backup_20260623.sql | docker exec -i linli-db psql -U postgres -d linli
```

### 自动每天备份（crontab）

```bash
# 编辑定时任务
crontab -e

# 添加这行（每天凌晨 3 点备份）
0 3 * * * docker exec linli-db pg_dump -U postgres linli > /opt/backups/linli_$(date +\%Y\%m\%d).sql

# 创建备份目录
mkdir -p /opt/backups
```

---

## 常见问题排查

### Q1: 容器起不来

```bash
# 看具体错误
docker compose -f docker-compose.prod.yml logs api
docker compose -f docker-compose.prod.yml logs db
```

### Q2: API 连不上数据库

检查 `.env.prod` 里的 `DB_PASSWORD` 是否和 `DATABASE_URL` 一致。

### Q3: HTTPS 证书申请失败

- 确认域名 DNS 已生效：`nslookup www.bbtech.com`
- 确认服务器 80/443 端口已开放（安全组规则）
- 看 Caddy 日志：`docker compose -f docker-compose.prod.yml logs caddy`

### Q4: 网页打不开但 API 能用

```bash
# 看 web 容器状态
docker compose -f docker-compose.prod.yml logs web
```

### Q5: 内存不够（OOM）

```bash
# 看内存占用
docker stats --no-stream

# 2GB 服务器如果不够，减小 db 内存限制
# 改 docker-compose.prod.yml 里 db 的 memory: 700M → 500M
```

---

## 文件清单

```
d:\linli\
├── docker-compose.prod.yml   ← 生产部署清单（4 个服务）
├── Caddyfile                 ← Caddy 反代配置
├── .env.prod.example         ← 环境变量模板
├── DEPLOY.md                 ← 本文档
│
├── linli-server\
│   ├── Dockerfile            ← Rust 后端镜像
│   └── docker-compose.yml    ← 本地开发用（只起 DB）
│
└── linli-web\
    ├── Dockerfile            ← Vue 网页镜像
    ├── nginx.conf            ← 网页静态托管配置
    └── .dockerignore
```
