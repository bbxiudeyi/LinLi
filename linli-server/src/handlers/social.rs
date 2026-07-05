use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::models::{
    ActivityListItem, PublicUserProfile, UpdateProfileResponse, UpdateUserRequest,
};
use crate::AppState;
use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

// ==================== 用户资料 ====================

/// GET /api/v1/users/:id
///
/// 返回其他用户的**公开资料**（不含 email、体重等隐私字段）。
pub async fn get_user_profile(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PublicUserProfile>> {
    let user: Option<PublicUserProfile> = sqlx::query_as(
        r#"SELECT id, nickname, avatar_url, bio, created_at
           FROM users WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?;
    user.map(Json).ok_or(AppError::NotFound)
}

/// PATCH /api/v1/users/me
///
/// 更新资料（任意字段可选）。若改了密码：token_version+1（其他设备掉线），
/// 并用新版本重签 token 返回，客户端应替换本地 token。
pub async fn update_my_profile(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(req): Json<UpdateUserRequest>,
) -> AppResult<Json<UpdateProfileResponse>> {
    // 校验 gender
    if let Some(ref g) = req.gender {
        if g != "male" && g != "female" {
            return Err(AppError::BadRequest("gender 必须是 male 或 female".into()));
        }
    }

    // 如果改密码：先哈希，且 token_version+1（让其他设备掉线）
    let (new_pwd_hash, bump_version) = if let Some(ref pwd) = req.password {
        if pwd.len() < 8 {
            return Err(AppError::BadRequest("密码至少 8 位".into()));
        }
        let hash = crate::auth::hash_password(pwd)?;
        (Some(hash), true)
    } else {
        (None, false)
    };

    let user: crate::models::UserProfile = sqlx::query_as(
        r#"UPDATE users SET
             nickname = COALESCE($1, nickname),
             avatar_url = COALESCE($2, avatar_url),
             bio = $3,
             gender = $4,
             birthday = $5,
             weight_kg = $6,
             password_hash = COALESCE($7, password_hash),
             token_version = CASE WHEN $8::boolean
                                  THEN token_version + 1
                                  ELSE token_version END
           WHERE id = $9
           RETURNING id, email, nickname, avatar_url, bio, gender, birthday,
                     weight_kg, created_at"#,
    )
    .bind(&req.nickname)
    .bind(&req.avatar_url)
    .bind(req.bio.as_deref())
    .bind(req.gender.as_deref())
    .bind(req.birthday)
    .bind(req.weight_kg)
    .bind(new_pwd_hash)
    .bind(bump_version)
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;

    // 改密码：失效缓存，并读回新 token_version 重签 token，让本设备继续可用
    let new_token = if bump_version {
        crate::token_version_cache::invalidate(user_id).await;
        let (new_ver,): (i32,) =
            sqlx::query_as("SELECT token_version FROM users WHERE id = $1")
                .bind(user_id)
                .fetch_one(&state.db)
                .await?;
        crate::token_version_cache::put(user_id, new_ver).await;
        Some(crate::auth::sign_jwt(
            user_id,
            new_ver,
            &state.config.jwt_secret,
            state.config.jwt_expires_hours,
        )?)
    } else {
        None
    };

    let msg = if bump_version {
        "资料已更新，密码已修改，其他设备需重新登录"
    } else {
        "资料已更新"
    };
    tracing::info!("用户 {user_id} 更新资料: {msg}");
    Ok(Json(UpdateProfileResponse {
        user,
        token: new_token,
    }))
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
        r#"SELECT a.id, a.user_id, a.type AS "type", a.distance_m, a.duration_s,
                  a.moving_time_s, a.avg_pace_s_per_km,
                  a.avg_speed_kmh::float8 AS avg_speed_kmh,
                  a.max_speed_kmh::float8 AS max_speed_kmh,
                  a.elevation_gain_m::float8 AS elevation_gain_m,
                  a.elevation_loss_m::float8 AS elevation_loss_m,
                  a.calories, a.start_time, a.end_time, a.title,
                  a.description, a.is_private,
                  u.nickname,
                  u.avatar_url,
                  -- 聚合一次，避免每行相关子查询（N+1）
                  COALESCE(kc.cnt, 0)::bigint AS kudo_count,
                  EXISTS(SELECT 1 FROM kudos k
                         WHERE k.activity_id = a.id AND k.user_id = $1) AS has_kudo
           FROM activities a
           JOIN users u ON u.id = a.user_id
           LEFT JOIN (
               SELECT activity_id, COUNT(*) AS cnt
               FROM kudos GROUP BY activity_id
           ) kc ON kc.activity_id = a.id
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
