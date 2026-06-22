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
/// 我的活动的列表（不含轨迹坐标）。
pub async fn list_my_activities(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<Vec<ActivityListItem>>> {
    let limit = q.limit.unwrap_or(50).clamp(1, 200);

    let rows: Vec<ActivityListItem> = if let Some(cursor) = q.cursor {
        let cursor_ts = chrono::DateTime::parse_from_rfc3339(&cursor)
            .map_err(|e| AppError::BadRequest(format!("cursor 格式错误: {e}")))?
            .with_timezone(&chrono::Utc);
        sqlx::query_as(
            r#"SELECT a.id, a.user_id, a.type, a.distance_m, a.duration_s,
                      a.moving_time_s, a.avg_pace_s_per_km, a.avg_speed_kmh,
                      a.max_speed_kmh, a.elevation_gain_m, a.elevation_loss_m,
                      a.calories, a.start_time, a.end_time, a.title,
                      a.description, a.is_private
               FROM activities a
               WHERE a.user_id = $1 AND a.start_time < $2
               ORDER BY a.start_time DESC LIMIT $3"#,
        )
        .bind(user_id)
        .bind(cursor_ts)
        .bind(limit)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query_as(
            r#"SELECT a.id, a.user_id, a.type, a.distance_m, a.duration_s,
                      a.moving_time_s, a.avg_pace_s_per_km, a.avg_speed_kmh,
                      a.max_speed_kmh, a.elevation_gain_m, a.elevation_loss_m,
                      a.calories, a.start_time, a.end_time, a.title,
                      a.description, a.is_private
               FROM activities a
               WHERE a.user_id = $1
               ORDER BY a.start_time DESC LIMIT $2"#,
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&state.db)
        .await?
    };

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
    let valid_types = ["run", "ride", "hike", "walk"];
    if !valid_types.contains(&req.sport_type.as_str()) {
        return Err(AppError::BadRequest(format!(
            "type 必须是 {:?} 之一",
            valid_types
        )));
    }
    if req.track.len() < 2 {
        return Err(AppError::BadRequest("track 至少 2 个点".into()));
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
        r#"SELECT a.id, a.user_id, a.type, a.distance_m, a.duration_s,
                  a.moving_time_s, a.avg_pace_s_per_km, a.avg_speed_kmh,
                  a.max_speed_kmh, a.elevation_gain_m, a.elevation_loss_m,
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
