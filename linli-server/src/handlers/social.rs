use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::models::{ActivityListItem, UpdateUserRequest, UserProfile};
use crate::AppState;
use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

// ==================== 用户资料 ====================

/// GET /api/v1/users/:id
pub async fn get_user_profile(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<UserProfile>> {
    let user: Option<UserProfile> = sqlx::query_as(
        r#"SELECT id, email, nickname, avatar_url, bio, gender, birthday,
                  weight_kg, created_at FROM users WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?;
    user.map(Json).ok_or(AppError::NotFound)
}

/// PATCH /api/v1/users/me
///
/// 更新资料（任意字段可选）。
pub async fn update_my_profile(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(req): Json<UpdateUserRequest>,
) -> AppResult<Json<UserProfile>> {
    // 校验 gender
    if let Some(ref g) = req.gender {
        if g != "male" && g != "female" {
            return Err(AppError::BadRequest("gender 必须是 male 或 female".into()));
        }
    }

    let user: UserProfile = sqlx::query_as(
        r#"UPDATE users SET
             nickname = COALESCE($1, nickname),
             bio = $2,
             gender = $3,
             birthday = $4,
             weight_kg = $5
           WHERE id = $6
           RETURNING id, email, nickname, avatar_url, bio, gender, birthday,
                     weight_kg, created_at"#,
    )
    .bind(&req.nickname)
    .bind(req.bio.as_deref())
    .bind(req.gender.as_deref())
    .bind(req.birthday)
    .bind(req.weight_kg)
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(user))
}

// ==================== Feed（关注流）====================

#[derive(Debug, Deserialize)]
pub struct FeedQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// GET /api/v1/feed
///
/// 返回当前用户 + 关注的人的公开活动（按时间倒序）。
pub async fn feed(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Query(q): Query<FeedQuery>,
) -> AppResult<Json<Vec<ActivityListItem>>> {
    let limit = q.limit.unwrap_or(30).clamp(1, 100);

    let rows: Vec<ActivityListItem> = sqlx::query_as(
        r#"SELECT a.id, a.user_id, a.type, a.distance_m, a.duration_s,
                  a.moving_time_s, a.avg_pace_s_per_km, a.avg_speed_kmh,
                  a.max_speed_kmh, a.elevation_gain_m, a.elevation_loss_m,
                  a.calories, a.start_time, a.end_time, a.title,
                  a.description, a.is_private,
                  u.nickname,
                  u.avatar_url,
                  (SELECT COUNT(*) FROM kudos k WHERE k.activity_id = a.id) AS kudo_count,
                  EXISTS(SELECT 1 FROM kudos k WHERE k.activity_id = a.id AND k.user_id = $1) AS has_kudo
           FROM activities a
           JOIN users u ON u.id = a.user_id
           WHERE (a.user_id = $1
                  OR a.user_id IN (SELECT following_id FROM follows WHERE follower_id = $1))
             AND a.is_private = FALSE
           ORDER BY a.start_time DESC
           LIMIT $2"#,
    )
    .bind(user_id)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(rows))
}

// ==================== 点赞 ====================

/// POST /api/v1/activities/:id/kudos
pub async fn add_kudo(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(activity_id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    // 活动存在性
    let exists: Option<(Uuid,)> =
        sqlx::query_as("SELECT id FROM activities WHERE id = $1")
            .bind(activity_id)
            .fetch_optional(&state.db)
            .await?;
    if exists.is_none() {
        return Err(AppError::NotFound);
    }

    sqlx::query(
        "INSERT INTO kudos (user_id, activity_id) VALUES ($1, $2)
         ON CONFLICT (user_id, activity_id) DO NOTHING",
    )
    .bind(user_id)
    .bind(activity_id)
    .execute(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "kudoed": true })))
}

/// DELETE /api/v1/activities/:id/kudos
pub async fn remove_kudo(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(activity_id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    sqlx::query("DELETE FROM kudos WHERE user_id = $1 AND activity_id = $2")
        .bind(user_id)
        .bind(activity_id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "kudoed": false })))
}

// ==================== 关注 ====================

/// POST /api/v1/users/:id/follow
pub async fn follow_user(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(target_id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    if user_id == target_id {
        return Err(AppError::BadRequest("不能关注自己".into()));
    }
    sqlx::query(
        "INSERT INTO follows (follower_id, following_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING",
    )
    .bind(user_id)
    .bind(target_id)
    .execute(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "following": true })))
}

/// DELETE /api/v1/users/:id/follow
pub async fn unfollow_user(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(target_id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    sqlx::query("DELETE FROM follows WHERE follower_id = $1 AND following_id = $2")
        .bind(user_id)
        .bind(target_id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "following": false })))
}
