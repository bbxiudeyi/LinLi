/// 本地用户模型（替代 Supabase Auth 的 User）。
///
/// 单用户本地 App，登录后存本地数据库，无需云账号。
class LocalUser {
  final String id;
  final String phone;
  final String nickname;

  const LocalUser({
    required this.id,
    required this.phone,
    required this.nickname,
  });

  factory LocalUser.fromRow(Map<String, dynamic> row) {
    return LocalUser(
      id: row['id'] as String,
      phone: row['phone'] as String? ?? '',
      nickname: row['nickname'] as String? ?? '运动爱好者',
    );
  }
}
