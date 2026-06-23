use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::models::{ActivityDetail, ActivityListItem, CreateActivityRequest};
use crate::AppState;
use axum::extract::{Path, Query, State};
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
    // ★ S2 安全限制：轨迹点数、距离、时长的合理上限
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

    // 把 [[lng, lat], ...] 拼成 PostGIS 的 WKT / 直接用 ST_GeomFromGeoJSON
    let coords: Vec<String> = req
        .track
        .iter()
        .map(|(lng, lat)| format!("{lng} {lat}"))
        .collect();
    let linestring_wkt = format!("LINESTRING({})", coords.join(", "));

    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO activities (
              user_id, type, distance_m, duration_s, moving_time_s,
              avg_pace_s_per_km, avg_speed_kmh, max_speed_kmh,
              elevation_gain_m, elevation_loss_m, calories,
              start_time, end_time, track, title, description, is_private
           )
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                   ST_GeomFromText($14, 4326), $15, $16, $17)
           RETURNING id"#,
    )
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
    .fetch_one(&state.db)
    .await?;

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

    // 3. 单独查轨迹（ST_AsGeoJSON 输出 GeoJSON LineString）
    let track_geojson: Option<(String,)> = sqlx::query_as(
        "SELECT ST_AsGeoJSON(track)::text FROM activities WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    let track = parse_geojson_linestring(
        &track_geojson.and_then(|(s,)| if s.is_empty() { None } else { Some(s) }).unwrap_or_default(),
    )?;

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

// ==================== GeoJSON 解析 ====================

/// 解析 PostGIS `ST_AsGeoJSON` 输出的 LineString JSON。
/// 输入示例：`{"type":"LineString","coordinates":[[116.4,39.9],[116.5,39.9]]}`
fn parse_geojson_linestring(geojson_str: &str) -> AppResult<Vec<(f64, f64)>> {
    if geojson_str.is_empty() {
        return Ok(vec![]);
    }
    let parsed: serde_json::Value =
        serde_json::from_str(geojson_str).map_err(|e| AppError::GeoJson(e.to_string()))?;
    let coords = parsed
        .get("coordinates")
        .and_then(|c| c.as_array())
        .ok_or_else(|| AppError::GeoJson("coordinates 字段缺失".into()))?;
    coords
        .iter()
        .map(|p| {
            let arr = p.as_array().ok_or_else(|| AppError::GeoJson("坐标格式错误".into()))?;
            if arr.len() < 2 {
                return Err(AppError::GeoJson("坐标至少 2 维".into()));
            }
            let lng = arr[0].as_f64().ok_or_else(|| AppError::GeoJson("lng 非 number".into()))?;
            let lat = arr[1].as_f64().ok_or_else(|| AppError::GeoJson("lat 非 number".into()))?;
            Ok((lng, lat))
        })
        .collect()
}
