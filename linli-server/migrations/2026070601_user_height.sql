-- 用户资料加身高字段（cm）。
-- 用于 BMI / 热量计算。
ALTER TABLE users ADD COLUMN IF NOT EXISTS height_cm DECIMAL(5,2);
