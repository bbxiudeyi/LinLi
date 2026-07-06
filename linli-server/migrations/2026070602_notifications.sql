-- 通知表：记录"有人关注了你"等通知。
-- type 预留扩展（follow / kudo / comment 等），当前只用到 follow。
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- 接收者（被关注的人）
  actor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,  -- 触发者（关注的人）
  type TEXT NOT NULL,                                              -- 'follow'
  read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- 同一人同一类型不重复发通知（重复关注不重复通知）
  UNIQUE(user_id, actor_id, type)
);

CREATE INDEX IF NOT EXISTS idx_notifications_user
  ON notifications(user_id, read, created_at DESC);
