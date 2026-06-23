use crate::error::{AppError, AppResult};
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, Clone, Copy)]
pub struct Claims {
    pub sub: Uuid,      // user id
    pub exp: usize,     // 过期时间戳（秒）
    pub iat: usize,     // 签发时间
    pub ver: i64,       // token 版本号（用于撤销：登出/改密码时 +1，旧 token 失效）
}

/// 签发 JWT。需传入当前 token_version，写入 claims.ver。
pub fn sign_jwt(user_id: Uuid, token_version: i32, secret: &str, expires_hours: i64) -> AppResult<String> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id,
        iat: now.timestamp() as usize,
        exp: (now + Duration::hours(expires_hours)).timestamp() as usize,
        ver: token_version as i64,
    };
    let token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )?;
    Ok(token)
}

/// 校验 JWT，返回 Claims。
pub fn verify_jwt(token: &str, secret: &str) -> AppResult<Claims> {
    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )?;
    Ok(data.claims)
}

// ==================== 密码哈希（argon2）====================

/// 哈希明文密码。
pub fn hash_password(plain: &str) -> AppResult<String> {
    use argon2::{
        password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
        Argon2,
    };
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    argon2
        .hash_password(plain.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AppError::PasswordHash(e.to_string()))
}

/// 校验明文密码与哈希是否匹配。
pub fn verify_password(plain: &str, hash: &str) -> bool {
    use argon2::{
        password_hash::{PasswordHash, PasswordVerifier},
        Argon2,
    };
    let parsed = match PasswordHash::new(hash) {
        Ok(h) => h,
        Err(_) => return false,
    };
    Argon2::default()
        .verify_password(plain.as_bytes(), &parsed)
        .is_ok()
}

// ==================== Axum 鉴权提取器 ====================

use axum::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;

/// 当前登录用户的提取器：
/// ```rust,ignore
/// async fn handler(AuthUser(user_id): AuthUser) { ... }
/// ```
/// 依赖全局中间件 auth_middleware 先把 Claims 塞进 request extensions。
#[derive(Debug, Clone, Copy)]
pub struct AuthUser(pub Uuid);

#[async_trait]
impl<S> FromRequestParts<S> for AuthUser
where
    S: Send + Sync,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        // 从 extensions 里取（中间件已塞好）
        let claims = parts
            .extensions
            .get::<Claims>()
            .copied()
            .ok_or(AppError::Unauthorized)?;
        Ok(AuthUser(claims.sub))
    }
}

/// JWT 中间件：从 Authorization header 解析 token，把 Claims 塞进 request extensions。
/// 公开路由（无 token）也放行，让 handler 自己决定是否需要 AuthUser。
use axum::middleware::Next;
use axum::response::Response;

pub async fn auth_middleware(
    mut req: axum::extract::Request,
    next: Next,
) -> Response {
    // 从 request extensions 取 AppState（Extension layer 提供的）
    let state = req.extensions().get::<crate::AppState>().cloned();

    if let Some(state) = state {
        let auth_header = req
            .headers()
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "));

        if let Some(token) = auth_header {
            if let Ok(claims) = verify_jwt(token, &state.config.jwt_secret) {
                // ★ 校验 token_version：查 DB 当前版本，不匹配则视为已撤销
                let db_ver: Option<(i32,)> = sqlx::query_as(
                    "SELECT token_version FROM users WHERE id = $1",
                )
                .bind(claims.sub)
                .fetch_optional(&state.db)
                .await
                .ok()
                .flatten();

                if let Some((db_ver,)) = db_ver {
                    if claims.ver == db_ver as i64 {
                        // 版本匹配，放行
                        req.extensions_mut().insert(claims);
                    }
                    // 版本不匹配：不塞 claims → 后续 AuthUser 提取器会返回 401
                }
            }
        }
    }
    next.run(req).await
}
