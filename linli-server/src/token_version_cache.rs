//! 进程内 token_version 缓存，缓解鉴权中间件每请求一次 DB 查询的压力。
//!
//! token_version 是低频变更（仅在登出 / 改密码时 +1），绝大部分请求校验都命中缓存。
//! TTL 兜底：即便 handler 忘记调 [invalidate]，最多 TTL 秒后也会重新查库。
//!
//! 多实例部署时，每个实例有独立缓存，TTL 期内可能允许已撤销 token 通过——
//! 若对此敏感，可改用 Redis 共享缓存；当前单实例 + 短 TTL 足够。

use std::collections::HashMap;
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use tokio::sync::Mutex;
use uuid::Uuid;

/// 缓存 TTL：超过该时长强制重新查库（兜底）。
const TTL: Duration = Duration::from_secs(60);

/// 进程级单例缓存：user_id -> (token_version, 写入时刻)。
static CACHE: LazyLock<Mutex<HashMap<Uuid, (i32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// 读取缓存的 token_version。未命中或过期返回 None。
pub async fn get(user_id: Uuid) -> Option<i32> {
    let guard = CACHE.lock().await;
    let (ver, at) = guard.get(&user_id)?;
    if at.elapsed() < TTL {
        Some(*ver)
    } else {
        None
    }
}

/// 写入 / 刷新缓存（DB 查到最新版本后调用）。
pub async fn put(user_id: Uuid, version: i32) {
    let mut guard = CACHE.lock().await;
    guard.insert(user_id, (version, Instant::now()));
}

/// 失效某个用户的缓存。
/// 在 token_version 发生变更时（登出、改密码）调用。
pub async fn invalidate(user_id: Uuid) {
    let mut guard = CACHE.lock().await;
    guard.remove(&user_id);
}
