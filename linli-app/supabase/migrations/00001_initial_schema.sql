-- 途迹 (TuJi) Database Schema
-- Supabase PostgreSQL Migration

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 用户表
-- ============================================
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  phone TEXT UNIQUE,
  nickname TEXT NOT NULL,
  avatar_url TEXT,
  bio TEXT,
  gender TEXT CHECK (gender IN ('male', 'female', 'other')),
  birthday DATE,
  weight_kg DECIMAL(5,2),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 自动创建用户记录（注册触发器）
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, phone, nickname)
  VALUES (
    NEW.id,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'nickname', '运动爱好者')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- 运动活动表
-- ============================================
CREATE TABLE activities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('run', 'ride', 'hike', 'walk', 'swim')),
  title TEXT,
  description TEXT,
  distance_m INTEGER DEFAULT 0,
  duration_s INTEGER DEFAULT 0,
  moving_time_s INTEGER DEFAULT 0,
  elapsed_time_s INTEGER DEFAULT 0,
  avg_pace_s_per_km INTEGER DEFAULT 0,
  avg_speed_kmh DECIMAL(6,2) DEFAULT 0,
  max_speed_kmh DECIMAL(6,2) DEFAULT 0,
  elevation_gain_m DECIMAL(8,2) DEFAULT 0,
  elevation_loss_m DECIMAL(8,2) DEFAULT 0,
  avg_heart_rate INTEGER,
  max_heart_rate INTEGER,
  calories INTEGER DEFAULT 0,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ,
  start_latlng POINT,
  end_latlng POINT,
  map_image_url TEXT,
  photo_urls TEXT[] DEFAULT '{}',
  is_private BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_activities_user_id ON activities(user_id);
CREATE INDEX idx_activities_start_time ON activities(start_time DESC);
CREATE INDEX idx_activities_type ON activities(type);

-- ============================================
-- GPS 轨迹点
-- ============================================
CREATE TABLE gps_points (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  latlng POINT NOT NULL,
  altitude_m DECIMAL(8,2),
  accuracy_m DECIMAL(6,2),
  speed_ms DECIMAL(6,2),
  heart_rate INTEGER,
  timestamp TIMESTAMPTZ NOT NULL,
  distance_from_start_m INTEGER DEFAULT 0
);

CREATE INDEX idx_gps_points_activity_id ON gps_points(activity_id);

-- ============================================
-- 路段 (Segments)
-- ============================================
CREATE TABLE segments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  sport_type TEXT NOT NULL CHECK (sport_type IN ('run', 'ride', 'hike')),
  distance_m INTEGER NOT NULL,
  avg_grade DECIMAL(5,2) DEFAULT 0,
  elevation_diff_m DECIMAL(8,2) DEFAULT 0,
  climb_category INTEGER DEFAULT 0 CHECK (climb_category BETWEEN 0 AND 5),
  start_latlng POINT NOT NULL,
  end_latlng POINT NOT NULL,
  polyline TEXT,
  created_by UUID REFERENCES users(id),
  effort_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_segments_sport_type ON segments(sport_type);

-- ============================================
-- 路段成绩 (Segment Efforts)
-- ============================================
CREATE TABLE segment_efforts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  segment_id UUID NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  duration_s INTEGER NOT NULL,
  avg_speed_kmh DECIMAL(6,2),
  avg_heart_rate INTEGER,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  rank_overall INTEGER,
  rank_gender INTEGER,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_segment_efforts_segment_id ON segment_efforts(segment_id);
CREATE INDEX idx_segment_efforts_user_id ON segment_efforts(user_id);
CREATE INDEX idx_segment_efforts_duration ON segment_efforts(segment_id, duration_s ASC);

-- ============================================
-- 关注关系
-- ============================================
CREATE TABLE follows (
  follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id != following_id)
);

CREATE INDEX idx_follows_follower ON follows(follower_id);
CREATE INDEX idx_follows_following ON follows(following_id);

-- ============================================
-- 点赞 (Kudos)
-- ============================================
CREATE TABLE kudos (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, activity_id)
);

CREATE INDEX idx_kudos_activity ON kudos(activity_id);

-- ============================================
-- 评论
-- ============================================
CREATE TABLE comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_comments_activity ON comments(activity_id);

-- ============================================
-- Row Level Security (RLS)
-- ============================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE segment_efforts ENABLE ROW LEVEL SECURITY;
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE kudos ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

-- Users: 可读所有，只能改自己的
CREATE POLICY "Users are readable by all" ON users
  FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- Activities: 公开活动可读，只能操作自己的
CREATE POLICY "Public activities are readable" ON activities
  FOR SELECT USING (is_private = false OR user_id = auth.uid());
CREATE POLICY "Users can create activities" ON activities
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own activities" ON activities
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own activities" ON activities
  FOR DELETE USING (auth.uid() = user_id);

-- GPS Points: 跟随 activity 权限
CREATE POLICY "GPS points readable with activity" ON gps_points
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM activities WHERE activities.id = gps_points.activity_id
            AND (activities.is_private = false OR activities.user_id = auth.uid()))
  );
CREATE POLICY "Users can insert GPS points" ON gps_points
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM activities WHERE activities.id = gps_points.activity_id
            AND activities.user_id = auth.uid())
  );

-- Segments: 所有人可读，登录用户可创建
CREATE POLICY "Segments are readable by all" ON segments
  FOR SELECT USING (true);
CREATE POLICY "Authenticated users can create segments" ON segments
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Segment Efforts: 跟随 segment 权限
CREATE POLICY "Segment efforts are readable" ON segment_efforts
  FOR SELECT USING (true);
CREATE POLICY "Users can create efforts" ON segment_efforts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Follows: 可读，只能操作自己的
CREATE POLICY "Follows are readable" ON follows
  FOR SELECT USING (true);
CREATE POLICY "Users can follow" ON follows
  FOR INSERT WITH CHECK (auth.uid() = follower_id);
CREATE POLICY "Users can unfollow" ON follows
  FOR DELETE USING (auth.uid() = follower_id);

-- Kudos: 可读，只能操作自己的
CREATE POLICY "Kudos are readable" ON kudos
  FOR SELECT USING (true);
CREATE POLICY "Users can give kudos" ON kudos
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can remove kudos" ON kudos
  FOR DELETE USING (auth.uid() = user_id);

-- Comments: 可读，登录用户可创建
CREATE POLICY "Comments are readable" ON comments
  FOR SELECT USING (true);
CREATE POLICY "Users can comment" ON comments
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own comments" ON comments
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================
-- Updated_at 自动更新触发器
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
