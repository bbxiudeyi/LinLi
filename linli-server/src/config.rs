use std::env;

/// 应用配置（从环境变量读取）。
#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub jwt_expires_hours: i64,
    pub host: String,
    pub port: u16,
    pub cors_origins: Vec<String>,
    /// 上传文件存储根目录（头像等用户文件）。
    pub upload_dir: String,
    /// 对外公开的基础 URL（用于拼上传文件的访问地址，如 https://api.bbtech.top）。
    pub public_base_url: String,
}

impl Config {
    /// 从环境变量加载（dotenvy 已在 main 里 load 过）。
    pub fn from_env() -> Self {
        Self {
            database_url: env::var("DATABASE_URL")
                .expect("DATABASE_URL must be set"),
            jwt_secret: env::var("JWT_SECRET")
                .expect("JWT_SECRET must be set"),
            jwt_expires_hours: env::var("JWT_EXPIRES_HOURS")
                .unwrap_or_else(|_| "168".into()) // 默认 7 天
                .parse()
                .expect("JWT_EXPIRES_HOURS must be a number"),
            host: env::var("HOST").unwrap_or_else(|_| "0.0.0.0".into()),
            port: env::var("PORT")
                .unwrap_or_else(|_| "8080".into())
                .parse()
                .expect("PORT must be a number"),
            cors_origins: env::var("CORS_ORIGINS")
                .unwrap_or_else(|_| "http://localhost:5173,http://localhost:8080".into())
                .split(',')
                .map(|s| s.trim().to_string())
                .collect(),
            upload_dir: env::var("UPLOAD_DIR")
                .unwrap_or_else(|_| "/opt/linli-server/uploads".into()),
            public_base_url: env::var("PUBLIC_BASE_URL")
                .unwrap_or_else(|_| "http://localhost:8080".into()),
        }
    }
}
