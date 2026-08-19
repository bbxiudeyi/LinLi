-- P0-3（生产就绪整改）：活动默认改为私密。
--
-- 1) 列默认值改为 TRUE：不传 is_private 的旧客户端/新活动一律私密。
-- 2) 存量公开活动全部转为私密：精确轨迹 + 时间序列属于敏感个人信息，
--    内测阶段不应对外可见；用户可自行在 App 内重新选择公开。
--
-- 回退说明：如需恢复个别活动的公开状态，由用户在客户端重新设置；
-- 本迁移不提供批量回退（安全默认方向只进不退）。

ALTER TABLE activities ALTER COLUMN is_private SET DEFAULT TRUE;

UPDATE activities SET is_private = TRUE;
