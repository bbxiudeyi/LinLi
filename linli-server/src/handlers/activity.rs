use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::models::{
    ActivityDetail, ActivityListItem, CreateActivityRequest, TrackPointOutput,
};
use crate::AppState;
use axum::extract::{Path, Query, State};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct ListQuery {
    pub limit: Option<i64>,
    /// 游标分页：上一页最后一条的 start_time（ISO8601）
    pub cursor: Option<String>,
}

/// GET /api/v1/activities
///
/// 我的活动的列表（不含轨迹坐标）。游标分页：传 cursor 则取该时间之前。
pub async fn list_my_activities(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<Vec<ActivityListItem>>> {
    let limit = q.limit.unwrap_or(50).clamp(1, 200);

    // cursor 解析：None 表示首页。统一成单个 SQL，用 `($2 IS NULL OR ...)` 兼顾两种情况。
    let cursor_ts: Option<chrono::DateTime<chrono::Utc>> = match q.cursor.as_deref() {
        None => None,
        Some(c) => Some(
            chrono::DateTime::parse_from_rfc3339(c)
                .map_err(|e| AppError::BadRequest(format!("cursor 格式错误: {e}")))?
                .with_timezone(&chrono::Utc),
        ),
    };

    // 列表项里 join 用户字段、点赞统计在本接口用不到，直接填 NULL（FromRow 要求字段齐全）。
    let rows: Vec<ActivityListItem> = sqlx::query_as(
        r#"SELECT a.id, a.user_id, a.type AS "type", a.distance_m, a.duration_s,
                  a.moving_time_s, a.avg_pace_s_per_km,
                  a.avg_speed_kmh::float8 AS avg_speed_kmh,
                  a.max_speed_kmh::float8 AS max_speed_kmh,
                  a.elevation_gain_m::float8 AS elevation_gain_m,
                  a.elevation_loss_m::float8 AS elevation_loss_m,
                  a.calories, a.start_time, a.end_time, a.title,
                  a.description, a.is_private,
                  NULL::text AS nickname, NULL::text AS avatar_url,
                  NULL::bigint AS kudo_count, NULL::bool AS has_kudo
           FROM activities a
           WHERE a.user_id = $1
             AND ($2::timestamptz IS NULL OR a.start_time < $2)
           ORDER BY a.start_time DESC
           LIMIT $3"#,
    )
    .bind(user_id)
    .bind(cursor_ts)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(rows))
}

/// GET /api/v1/activities/stats/daily
///
/// 返回当前用户最近一年的每日活动数，供"活跃日历"热力图展示。
/// 返回格式：`[{ "date": "2026-06-01", "count": 3 }, ...]`（只含有活动的日期）。
pub async fn daily_stats(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> AppResult<Json<Vec<serde_json::Value>>> {
    let rows: Vec<(chrono::NaiveDate, i64)> = sqlx::query_as(
        r#"SELECT (start_time AT TIME ZONE 'UTC')::date AS d, COUNT(*) AS c
           FROM activities
           WHERE user_id = $1
             AND start_time > now() - INTERVAL '365 days'
           GROUP BY d
           ORDER BY d"#,
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await?;

    let out: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|(d, c)| {
            serde_json::json!({ "date": d.format("%Y-%m-%d").to_string(), "count": c })
        })
        .collect();
    Ok(Json(out))
}

/// POST /api/v1/activities
///
/// 上传新活动。track 是 `[[lng, lat], ...]` 数组。
pub async fn create_activity(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(req): Json<CreateActivityRequest>,
) -> AppResult<Json<serde_json::Value>> {
    // 校验运动类型
    const VALID_TYPES: [&str; 4] = ["run", "ride", "hike", "walk"];
    if !VALID_TYPES.contains(&req.sport_type.as_str()) {
        return Err(AppError::BadRequest(format!(
            "type 必须是 {:?} 之一",
            VALID_TYPES
        )));
    }
    // 校验点数上限
    const MAX_TRACK_POINTS: usize = 50_000; // 单次最多 5 万点（约马拉松级）
    const MAX_DISTANCE_M: i32 = 1_000_000; // 1000 km
    const MAX_DURATION_S: i32 = 24 * 3600; // 24 小时
    if req.track.len() < 2 {
        return Err(AppError::BadRequest("track 至少 2 个点".into()));
    }
    if req.track.len() > MAX_TRACK_POINTS {
        return Err(AppError::BadRequest(format!(
            "轨迹点数 {}/{} 超过上限",
            req.track.len(),
            MAX_TRACK_POINTS
        )));
    }
    if req.distance_m < 0 || req.distance_m > MAX_DISTANCE_M {
        return Err(AppError::BadRequest(format!(
            "distance_m 必须在 0..{MAX_DISTANCE_M} 之间"
        )));
    }
    if req.duration_s < 0 || req.duration_s > MAX_DURATION_S {
        return Err(AppError::BadRequest(format!(
            "duration_s 必须在 0..{MAX_DURATION_S} 之间"
        )));
    }

    // ★ 幂等：若客户端传入 id，检查是否已存在
    //   - 属于本人 → 视为重传，直接返回（活动可能上次上传部分成功）
    //   - 属于他人 → 极小概率的 id 碰撞，拒绝
    //   - 不存在 → 正常插入
    let id = req.id.unwrap_or_else(|| Uuid::new_v4());
    if req.id.is_some() {
        let existing: Option<(Uuid,)> =
            sqlx::query_as("SELECT user_id FROM activities WHERE id = $1")
                .bind(id)
                .fetch_optional(&state.db)
                .await?;
        if let Some((owner,)) = existing {
            if owner != user_id {
                return Err(AppError::BadRequest(
                    "activity id 已被占用（与本人不匹配）".into(),
                ));
            }
            // 属于本人的重传，直接返回 id（活动行+点表上次可能已写入）
            return Ok(Json(serde_json::json!({ "id": id })));
        }
    }

    // 用事务保证原子性：activities 行 + activity_points 行一起成功或一起失败
    let mut tx = state.db.begin().await?;

    // ① 插入 activities 主行（track LineString 仍写，地图快速渲染用）
    let coords: Vec<String> = req
        .track
        .iter()
        .map(|p| format!("{} {}", p.lng, p.lat))
        .collect();
    let linestring_wkt = format!("LINESTRING({})", coords.join(", "));

    // 用客户端传入的 id 插入；ON CONFLICT 兜底防并发重复（理论上上面已检查）
    sqlx::query(
        r#"INSERT INTO activities (
              id, user_id, type, distance_m, duration_s, moving_time_s,
              avg_pace_s_per_km, avg_speed_kmh, max_speed_kmh,
              elevation_gain_m, elevation_loss_m, calories,
              start_time, end_time, track, title, description, is_private
           )
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                   ST_GeomFromText($15, 4326), $16, $17, $18)
           ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(id)
    .bind(user_id)
    .bind(&req.sport_type)
    .bind(req.distance_m)
    .bind(req.duration_s)
    .bind(req.moving_time_s.unwrap_or(req.duration_s))
    .bind(req.avg_pace_s_per_km.unwrap_or(0))
    .bind(req.avg_speed_kmh.unwrap_or(0.0))
    .bind(req.max_speed_kmh.unwrap_or(0.0))
    .bind(req.elevation_gain_m.unwrap_or(0.0))
    .bind(req.elevation_loss_m.unwrap_or(0.0))
    .bind(req.calories.unwrap_or(0))
    .bind(req.start_time)
    .bind(req.end_time)
    .bind(&linestring_wkt)
    .bind(&req.title)
    .bind(&req.description)
    .bind(req.is_private.unwrap_or(false))
    .execute(&mut *tx)
    .await?;

    // ② 批量插入多维点到 activity_points（UNNEST 一次插入，避免 N 次 INSERT）
    //    ON CONFLICT DO NOTHING：重传时已存在的点不重复插入
    let n = req.track.len();
    let mut seqs = Vec::with_capacity(n);
    let mut lats = Vec::with_capacity(n);
    let mut lngs = Vec::with_capacity(n);
    let mut eles = Vec::with_capacity(n);
    let mut speeds = Vec::with_capacity(n);
    let mut times = Vec::with_capacity(n);
    for (i, p) in req.track.iter().enumerate() {
        seqs.push(i as i32);
        lats.push(p.lat);
        lngs.push(p.lng);
        eles.push(p.ele);
        speeds.push(p.speed);
        times.push(p.time);
    }

    sqlx::query(
        r#"INSERT INTO activity_points
             (activity_id, seq, lat, lng, ele, speed, recorded_at)
           SELECT $1, * FROM UNNEST(
             $2::int[], $3::float8[], $4::float8[],
             $5::float8[], $6::float8[], $7::timestamptz[]
           )
           ON CONFLICT (activity_id, seq) DO NOTHING"#,
    )
    .bind(id)
    .bind(&seqs)
    .bind(&lats)
    .bind(&lngs)
    .bind(&eles)
    .bind(&speeds)
    .bind(&times)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(Json(serde_json::json!({ "id": id })))
}

/// GET /api/v1/activities/:id
///
/// 活动详情（含完整轨迹）。
pub async fn get_activity(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ActivityDetail>> {
    // 1. 查活动基础信息（用 ActivityListItem 直接 FromRow）
    let item: Option<ActivityListItem> = sqlx::query_as(
        r#"SELECT a.id, a.user_id, a.type AS "type", a.distance_m, a.duration_s,
                  a.moving_time_s, a.avg_pace_s_per_km,
                  a.avg_speed_kmh::float8 AS avg_speed_kmh,
                  a.max_speed_kmh::float8 AS max_speed_kmh,
                  a.elevation_gain_m::float8 AS elevation_gain_m,
                  a.elevation_loss_m::float8 AS elevation_loss_m,
                  a.calories, a.start_time, a.end_time, a.title,
                  a.description, a.is_private,
                  NULL::text AS nickname, NULL::text AS avatar_url,
                  NULL::bigint AS kudo_count, NULL::bool AS has_kudo
           FROM activities a WHERE a.id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    let item = item.ok_or(AppError::NotFound)?;

    // 2. 权限：私密活动只有本人可看
    if item.is_private && item.user_id != user_id {
        return Err(AppError::Forbidden);
    }

    // 3. 查多维轨迹点（按 seq 排序，含海拔/速度/时间）
    let track: Vec<TrackPointOutput> = sqlx::query_as(
        r#"SELECT seq, lat, lng, ele, speed, recorded_at
           FROM activity_points
           WHERE activity_id = $1
           ORDER BY seq"#,
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(ActivityDetail { item, track }))
}

/// DELETE /api/v1/activities/:id
pub async fn delete_activity(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    // 校验所有权
    let owner: Option<(Uuid,)> = sqlx::query_as("SELECT user_id FROM activities WHERE id = $1")
        .bind(id)
        .fetch_optional(&state.db)
        .await?;
    match owner {
        None => return Err(AppError::NotFound),
        Some((oid,)) if oid != user_id => return Err(AppError::Forbidden),
        _ => {}
    }

    sqlx::query("DELETE FROM activities WHERE id = $1")
        .bind(id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "deleted": id })))
}

// ==================== GPX 导出 ====================

/// 加载活动的基础信息 + 所有权校验。
/// 返回 (sport_type, title, owner_id)，用于 GPX 生成和权限判断。
async fn load_activity_meta(
    state: &AppState,
    id: Uuid,
    user_id: Uuid,
) -> AppResult<(String, Option<String>, Uuid, bool)> {
    let row: Option<(String, Option<String>, Uuid, bool)> = sqlx::query_as(
        r#"SELECT type, title, user_id, is_private FROM activities WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?;
    let (sport_type, title, owner_id, is_private) = row.ok_or(AppError::NotFound)?;
    // 私密活动只有本人可导出
    if is_private && owner_id != user_id {
        return Err(AppError::Forbidden);
    }
    Ok((sport_type, title, owner_id, is_private))
}

/// GET /api/v1/activities/:id/export.gpx
///
/// 从 activity_points 实时生成 GPX 1.1 文件下载。
/// 不引入 XML 依赖：GPX 结构简单，用字符串拼接 + 转义即可。
pub async fn export_gpx(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Response> {
    let (sport_type, title, _owner_id, _is_private) =
        load_activity_meta(&state, id, user_id).await?;

    // 查多维点
    let points: Vec<TrackPointOutput> = sqlx::query_as(
        r#"SELECT seq, lat, lng, ele, speed, recorded_at
           FROM activity_points WHERE activity_id = $1 ORDER BY seq"#,
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;

    let name = xml_escape(&title.unwrap_or_else(|| sport_type.clone()));

    // 拼接 GPX 1.1（手写，符合 GPX 1.1 schema）
    let mut xml = String::with_capacity(256 + points.len() * 120);
    xml.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    xml.push_str("<gpx version=\"1.1\" creator=\"LinLi\" ");
    xml.push_str("xmlns=\"http://www.topografix.com/GPX/1/1\">\n");

    // 元数据
    xml.push_str("  <metadata>\n");
    xml.push_str(&format!("    <name>{name}</name>\n"));
    xml.push_str("    <author><name>LinLi</name></author>\n");
    xml.push_str("  </metadata>\n");

    // 轨迹
    xml.push_str("  <trk>\n");
    xml.push_str(&format!("    <name>{name}</name>\n"));
    xml.push_str("    <type>");
    xml.push_str(&sport_type);
    xml.push_str("</type>\n");
    xml.push_str("    <trkseg>\n");

    for p in &points {
        // lat/lon 是 trkpt 的属性（必填）
        xml.push_str(&format!(
            "      <trkpt lat=\"{:.7}\" lon=\"{:.7}\">\n",
            p.lat, p.lng
        ));
        if let Some(ele) = p.ele {
            xml.push_str(&format!("        <ele>{:.2}</ele>\n", ele));
        }
        if let Some(t) = p.recorded_at {
            // GPX 要求 ISO8601 UTC，带 Z
            xml.push_str(&format!(
                "        <time>{}</time>\n",
                t.format("%Y-%m-%dT%H:%M:%SZ")
            ));
        }
        if let Some(s) = p.speed {
            // 速度存到扩展字段（GPX 1.1 无标准速度元素，用 extensions）
            xml.push_str("        <extensions>\n");
            xml.push_str(&format!(
                "          <speed>{:.2}</speed>\n",
                s
            ));
            xml.push_str("        </extensions>\n");
        }
        xml.push_str("      </trkpt>\n");
    }

    xml.push_str("    </trkseg>\n  </trk>\n</gpx>\n");

    // 构建下载响应
    let filename = format!("linli-{}.gpx", id);
    let content_type: axum::http::HeaderValue =
        "application/gpx+xml; charset=utf-8".parse().unwrap();
    let disposition: axum::http::HeaderValue =
        format!("attachment; filename=\"{filename}\"").parse().unwrap();
    Ok((
        [
            (axum::http::header::CONTENT_TYPE, content_type),
            (axum::http::header::CONTENT_DISPOSITION, disposition),
        ],
        xml,
    )
        .into_response())
}

/// XML 文本转义（& < > " '）。
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
