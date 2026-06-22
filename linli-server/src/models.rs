use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

// ==================== User ====================

#[derive(Debug, Clone, Serialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub nickname: String,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub gender: Option<String>,
    pub birthday: Option<NaiveDate>,
    pub weight_kg: Option<f64>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, validator::Validate)]
pub struct RegisterRequest {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 8, max = 64))]
    pub password: String,
    #[validate(length(min = 1, max = 32))]
    pub nickname: String,
}

#[derive(Debug, Deserialize, validator::Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user: UserProfile,
}

/// 更新资料的请求（所有字段可选）。
#[derive(Debug, Deserialize, Default)]
pub struct UpdateUserRequest {
    pub nickname: Option<String>,
    pub bio: Option<String>,
    pub gender: Option<String>,
    pub birthday: Option<NaiveDate>,
    pub weight_kg: Option<f64>,
}

/// 用户公开信息（不含密码）。
#[derive(Debug, Clone, Serialize, FromRow)]
pub struct UserProfile {
    pub id: Uuid,
    pub email: String,
    pub nickname: String,
    pub avatar_url: Option<String>,
    pub bio: Option<String>,
    pub gender: Option<String>,
    pub birthday: Option<NaiveDate>,
    pub weight_kg: Option<f64>,
    pub created_at: DateTime<Utc>,
}

impl From<User> for UserProfile {
    fn from(u: User) -> Self {
        Self {
            id: u.id,
            email: u.email,
            nickname: u.nickname,
            avatar_url: u.avatar_url,
            bio: u.bio,
            gender: u.gender,
            birthday: u.birthday,
            weight_kg: u.weight_kg,
            created_at: u.created_at,
        }
    }
}

// ==================== Activity ====================

#[derive(Debug, Clone, Copy, Deserialize, Serialize, sqlx::Type)]
#[serde(rename_all = "lowercase")]
#[sqlx(type_name = "TEXT", rename_all = "lowercase")]
pub enum SportType {
    Run,
    Ride,
    Hike,
    Walk,
}

/// 轨迹点（客户端上传格式，GeoJSON LineString 的一个坐标）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackPoint {
    pub lat: f64,
    pub lng: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub altitude: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub speed: Option<f64>,
}

/// 上传活动的请求体。
#[derive(Debug, Deserialize, validator::Validate)]
pub struct CreateActivityRequest {
    #[serde(rename = "type")]
    pub sport_type: String, // "run" / "ride" / "hike" / "walk"
    pub distance_m: i32,
    pub duration_s: i32,
    pub moving_time_s: Option<i32>,
    pub avg_pace_s_per_km: Option<i32>,
    pub avg_speed_kmh: Option<f64>,
    pub max_speed_kmh: Option<f64>,
    pub elevation_gain_m: Option<f64>,
    pub elevation_loss_m: Option<f64>,
    pub calories: Option<i32>,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    /// 轨迹坐标序列 [[lng, lat], ...]（GeoJSON LineString 坐标格式）
    pub track: Vec<(f64, f64)>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub is_private: Option<bool>,
}

/// 活动列表项（不含轨迹坐标，省流量）。
#[derive(Debug, Clone, Serialize, FromRow)]
pub struct ActivityListItem {
    pub id: Uuid,
    pub user_id: Uuid,
    #[serde(rename = "type")]
    #[sqlx(rename = "type")]
    pub sport_type: String,
    pub distance_m: i32,
    pub duration_s: i32,
    pub moving_time_s: i32,
    pub avg_pace_s_per_km: i32,
    pub avg_speed_kmh: f64,
    pub max_speed_kmh: f64,
    pub elevation_gain_m: f64,
    pub elevation_loss_m: f64,
    pub calories: i32,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub is_private: bool,
    // join 用户字段（feed 用）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nickname: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    // 点赞数 + 当前用户是否已赞
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kudo_count: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub has_kudo: Option<bool>,
}

/// 活动详情（含完整轨迹）。
#[derive(Debug, Serialize)]
pub struct ActivityDetail {
    #[serde(flatten)]
    pub item: ActivityListItem,
    /// [[lng, lat], ...]
    pub track: Vec<(f64, f64)>,
}
