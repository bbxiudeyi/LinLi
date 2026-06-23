mod auth;
mod config;
mod db;
mod error;
mod handlers;
mod models;

use axum::http::{header, Method};
use axum::routing::{delete, get, patch, post};
use axum::Router;
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

/// 全局应用状态（共享给所有 handler）。
#[derive(Clone)]
pub struct AppState {
    pub db: sqlx::PgPool,
    pub config: Arc<config::Config>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 加载 .env
    let _ = dotenvy::dotenv();

    // 初始化日志
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "linli_server=debug,tower_http=debug,sqlx=warn".into()),
        )
        .init();

    let config = config::Config::from_env();
    tracing::info!("启动 linli-server, 监听 {}:{}", config.host, config.port);

    // 连接数据库（带重试，等 PG 起来）
    let db = connect_with_retry(&config.database_url).await?;
    sqlx::migrate!("./migrations").run(&db).await?;
    tracing::info!("数据库连接成功，迁移完成");

    let state = AppState {
        db: db.clone(),
        config: Arc::new(config.clone()),
    };

    // CORS
    let cors = build_cors(&config.cors_origins);

    // 路由
    let app = Router::new()
        .route("/health", get(health))
        // 认证（公开）
        .route("/api/v1/auth/register", post(handlers::auth::register))
        .route("/api/v1/auth/login", post(handlers::auth::login))
        .route("/api/v1/auth/logout", post(handlers::auth::logout))
        .route("/api/v1/auth/me", get(handlers::auth::me))
        // 用户
        .route("/api/v1/users/:id", get(handlers::social::get_user_profile))
        .route("/api/v1/users/me", patch(handlers::social::update_my_profile))
        .route("/api/v1/users/:id/follow", post(handlers::social::follow_user))
        .route(
            "/api/v1/users/:id/follow",
            delete(handlers::social::unfollow_user),
        )
        // 活动
        .route("/api/v1/activities", get(handlers::activity::list_my_activities))
        .route("/api/v1/activities", post(handlers::activity::create_activity))
        .route("/api/v1/activities/:id", get(handlers::activity::get_activity))
        .route("/api/v1/activities/:id", delete(handlers::activity::delete_activity))
        // 点赞
        .route("/api/v1/activities/:id/kudos", post(handlers::social::add_kudo))
        .route(
            "/api/v1/activities/:id/kudos",
            delete(handlers::social::remove_kudo),
        )
        // Feed
        .route("/api/v1/feed", get(handlers::social::feed))
        // 层的顺序（从外到内执行）：trace → cors → middleware → extension → routes
        // extension 必须在中间件"之前"（更内层），中间件才能在 extensions 里读到
        .layer(axum::middleware::from_fn(auth::auth_middleware))
        .layer(axum::Extension(state.clone()))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr = format!("{}:{}", config.host, config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("linli-server 启动完成: http://{addr}");
    axum::serve(listener, app).await?;
    Ok(())
}

/// 健康检查（公开，不鉴权）。
async fn health() -> &'static str {
    "ok"
}

/// 连接数据库，最多重试 30 秒。
async fn connect_with_retry(url: &str) -> anyhow::Result<sqlx::PgPool> {
    for i in 1..=15 {
        match db::create_pool(url).await {
            Ok(pool) => return Ok(pool),
            Err(e) => {
                tracing::warn!("数据库连接失败（第 {i}/15 次）: {e}");
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }
        }
    }
    anyhow::bail!("数据库连接 15 次重试均失败")
}

/// 构建 CORS 层。启动时校验 + 打印日志（防配错）。
fn build_cors(origins: &[String]) -> CorsLayer {
    // ★ S3 安全：通配 * 配合 credentials 会泄露，拒绝启动
    if origins.iter().any(|o| o.trim() == "*") {
        panic!(
            "CORS_ORIGINS 不能是 '*'（开了 allow_credentials 会泄露凭据）。\
             请改成具体域名，如 https://www.bbtech.com"
        );
    }
    let parsed: Vec<_> = origins
        .iter()
        .filter_map(|o| o.parse().ok())
        .collect();
    tracing::info!("CORS 允许的源: {:?}", parsed);
    CorsLayer::new()
        .allow_origin(parsed)
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PATCH,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION])
        .allow_credentials(true)
}
