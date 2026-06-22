use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

/// 应用统一错误类型。
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("邮箱或密码错误")]
    InvalidCredentials,

    #[error("邮箱已注册")]
    EmailTaken,

    #[error("未登录或 token 无效")]
    Unauthorized,

    #[error("无权访问该资源")]
    Forbidden,

    #[error("资源不存在")]
    NotFound,

    #[error("请求参数错误: {0}")]
    BadRequest(String),

    #[error("数据库错误: {0}")]
    Database(#[from] sqlx::Error),

    #[error("JWT 错误: {0}")]
    Jwt(#[from] jsonwebtoken::errors::Error),

    #[error("密码哈希错误: {0}")]
    PasswordHash(String),

    #[error("GeoJSON 解析错误: {0}")]
    GeoJson(String),

    #[error("服务器内部错误: {0}")]
    Internal(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::InvalidCredentials => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, self.to_string()),
            AppError::Forbidden => (StatusCode::FORBIDDEN, self.to_string()),
            AppError::EmailTaken => (StatusCode::CONFLICT, self.to_string()),
            AppError::NotFound => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::Database(e) => {
                tracing::error!("DB error: {e:?}");
                (StatusCode::INTERNAL_SERVER_ERROR, "数据库错误".to_string())
            }
            AppError::Jwt(_) => (StatusCode::UNAUTHORIZED, "token 无效".to_string()),
            AppError::PasswordHash(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, "服务器错误".to_string())
            }
            AppError::GeoJson(_) => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::Internal(_) => {
                tracing::error!("Internal: {self:?}");
                (StatusCode::INTERNAL_SERVER_ERROR, "服务器内部错误".to_string())
            }
        };

        (status, Json(json!({ "error": message }))).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;
