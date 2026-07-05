use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::AppState;
use axum::extract::{Multipart, State};
use axum::Json;
use serde::Serialize;
use std::path::PathBuf;
use tokio::fs;

/// 上传头像响应。
#[derive(Serialize)]
pub struct UploadAvatarResponse {
    pub url: String,
}

/// POST /api/v1/uploads/avatar
///
/// 接收 multipart 文件（字段名 `file`），存为 `{upload_dir}/avatars/{user_id}.jpg`，
/// 返回可通过 PUBLIC_BASE_URL 访问的完整 URL。
///
/// 校验：必须是图片（content-type image/*）、大小 < 2MB。
/// 同一用户多次上传会覆盖旧头像（文件名固定）。
pub async fn upload_avatar(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    mut multipart: Multipart,
) -> AppResult<Json<UploadAvatarResponse>> {
    // 取出第一个字段（字段名要求是 file）
    let field = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(format!("读取上传字段失败: {e}")))?
        .ok_or_else(|| AppError::BadRequest("缺少文件字段 'file'".into()))?;

    // 字段名校验（兼容前端用 file 或 image 命名）
    let field_name = field.name().unwrap_or("").to_string();
    if field_name != "file" && field_name != "image" {
        return Err(AppError::BadRequest(
            "字段名必须是 'file'".into(),
        ));
    }

    // content-type 校验：必须是图片
    let content_type = field
        .content_type()
        .map(|s| s.to_string())
        .unwrap_or_default();
    if !content_type.starts_with("image/") {
        return Err(AppError::BadRequest("文件必须是图片".into()));
    }

    // 读取数据（限制 2MB）
    const MAX_SIZE: usize = 2 * 1024 * 1024;
    let data = field
        .bytes()
        .await
        .map_err(|e| AppError::BadRequest(format!("读取文件数据失败: {e}")))?;
    if data.len() > MAX_SIZE {
        return Err(AppError::BadRequest("文件过大，最大 2MB".into()));
    }

    // 构造存储路径：{upload_dir}/avatars/{user_id}.jpg
    let mut dir = PathBuf::from(&state.config.upload_dir);
    dir.push("avatars");
    fs::create_dir_all(&dir)
        .await
        .map_err(|e| AppError::Internal(format!("创建目录失败: {e}")))?;

    // 文件名用 user_id（覆盖旧头像，不堆积）
    let filename = format!("{user_id}.jpg");
    let file_path = dir.join(&filename);

    // 写入磁盘
    fs::write(&file_path, &data)
        .await
        .map_err(|e| AppError::Internal(format!("写入文件失败: {e}")))?;

    // 拼公开 URL（前端直接用这个 URL 加载图片）
    let url = format!(
        "{}/uploads/avatars/{}",
        state.config.public_base_url.trim_end_matches('/'),
        filename
    );

    tracing::info!("用户 {user_id} 上传头像: {url} ({} bytes)", data.len());
    Ok(Json(UploadAvatarResponse { url }))
}
