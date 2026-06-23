-- 多维轨迹点表
-- 替代 activities.track (LineString) 的纯坐标存储，
-- 保留每个点的海拔/速度/采集时间，供详情页海拔剖面、配速曲线、GPX 导出使用。
-- activities.track (LineString) 列保留（地图快速渲染 + 未来 segment 空间查询）。

CREATE TABLE IF NOT EXISTS activity_points (
  id BIGSERIAL PRIMARY KEY,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,          -- 点序号（0-based，保持原始顺序）
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  ele DOUBLE PRECISION,          -- 海拔(米)，可空（部分定位无此值）
  speed DOUBLE PRECISION,        -- 瞬时速度(m/s)，可空
  recorded_at TIMESTAMPTZ,       -- 该点的采集时间
  UNIQUE(activity_id, seq)
);

CREATE INDEX IF NOT EXISTS idx_activity_points_activity
  ON activity_points(activity_id, seq);
