-- 林立运动 App 数据库初始化
-- PostgreSQL 16 + PostGIS

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

-- ============================================
-- 用户表（邮箱+密码登录）
-- ============================================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  nickname TEXT NOT NULL,
  avatar_url TEXT,
  bio TEXT,
  gender TEXT CHECK (gender IN ('male', 'female')),
  birthday DATE,
  weight_kg DECIMAL(5,2),
  token_version INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- 运动活动表（轨迹用 PostGIS LineString 存）
-- ============================================
CREATE TABLE IF NOT EXISTS activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('run', 'ride', 'hike', 'walk')),
  distance_m INTEGER NOT NULL DEFAULT 0,
  duration_s INTEGER NOT NULL DEFAULT 0,
  moving_time_s INTEGER NOT NULL DEFAULT 0,
  avg_pace_s_per_km INTEGER NOT NULL DEFAULT 0,
  avg_speed_kmh DECIMAL(6,2) NOT NULL DEFAULT 0,
  max_speed_kmh DECIMAL(6,2) NOT NULL DEFAULT 0,
  elevation_gain_m DECIMAL(8,2) NOT NULL DEFAULT 0,
  elevation_loss_m DECIMAL(8,2) NOT NULL DEFAULT 0,
  calories INTEGER NOT NULL DEFAULT 0,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ,
  track GEOMETRY(LineString, 4326),
  title TEXT,
  description TEXT,
  is_private BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_activities_user_time
  ON activities(user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_activities_track
  ON activities USING GIST(track);
CREATE INDEX IF NOT EXISTS idx_activities_start_time
  ON activities(start_time DESC);

-- ============================================
-- 关注关系
-- ============================================
CREATE TABLE IF NOT EXISTS follows (
  follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- ============================================
-- 点赞（多用户）
-- ============================================
CREATE TABLE IF NOT EXISTS kudos (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, activity_id)
);

CREATE INDEX IF NOT EXISTS idx_kudos_activity ON kudos(activity_id);

-- ============================================
-- updated_at 自动更新函数
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
