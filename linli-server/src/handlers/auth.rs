use crate::auth::{hash_password, sign_jwt, verify_password, AuthUser};
use crate::error::{AppError, AppResult};
use crate::models::{AuthResponse, LoginRequest, RegisterRequest, User, UserProfile};
use crate::AppState;
use axum::extract::State;
use axum::Json;
use validator::Validate;

/// POST /api/v1/auth/register
///
/// body: `{ email, password, nickname }`
/// 返回 JWT + 用户信息。
pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> AppResult<Json<AuthResponse>> {
    req.validate()
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    // 检查邮箱是否已注册
    let existing: Option<(uuid::Uuid,)> = sqlx::query_as(
        "SELECT id FROM users WHERE email = $1",
    )
    .bind(&req.email)
    .fetch_optional(&state.db)
    .await?;
    if existing.is_some() {
        return Err(AppError::EmailTaken);
    }

    let password_hash = hash_password(&req.password)?;

    let user: User = sqlx::query_as(
        r#"INSERT INTO users (email, password_hash, nickname)
           VALUES ($1, $2, $3)
           RETURNING id, email, password_hash, nickname, avatar_url, bio,
                     gender, birthday, weight_kg, token_version, created_at, updated_at"#,
    )
    .bind(&req.email)
    .bind(&password_hash)
    .bind(&req.nickname)
    .fetch_one(&state.db)
    .await?;

    let token = sign_jwt(user.id, user.token_version, &state.config.jwt_secret, state.config.jwt_expires_hours)?;
    Ok(Json(AuthResponse {
        token,
        user: user.into(),
    }))
}

/// POST /api/v1/auth/login
///
/// body: `{ email, password }`
/// 返回 JWT + 用户信息。
pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> AppResult<Json<AuthResponse>> {
    req.validate()
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let user: Option<User> = sqlx::query_as(
        r#"SELECT id, email, password_hash, nickname, avatar_url, bio,
                  gender, birthday, weight_kg, token_version, created_at, updated_at
           FROM users WHERE email = $1"#,
    )
    .bind(&req.email)
    .fetch_optional(&state.db)
    .await?;

    let user = user.ok_or(AppError::InvalidCredentials)?;
    if !verify_password(&req.password, &user.password_hash) {
        return Err(AppError::InvalidCredentials);
    }

    let token = sign_jwt(user.id, user.token_version, &state.config.jwt_secret, state.config.jwt_expires_hours)?;
    Ok(Json(AuthResponse {
        token,
        user: user.into(),
    }))
}

/// POST /api/v1/auth/logout
///
/// 撤销当前 token：token_version + 1，使所有旧 token 立即失效。
pub async fn logout(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    sqlx::query("UPDATE users SET token_version = token_version + 1 WHERE id = $1")
        .bind(user_id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "logged_out": true })))
}

/// GET /api/v1/auth/me
///
/// 需鉴权。返回当前登录用户的公开资料。
pub async fn me(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> AppResult<Json<UserProfile>> {
    let user: User = sqlx::query_as(
        r#"SELECT id, email, password_hash, nickname, avatar_url, bio,
                  gender, birthday, weight_kg, token_version, created_at, updated_at
           FROM users WHERE id = $1"#,
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(user.into()))
}
