import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/profile_provider.dart';

/// 编辑个人资料页。
///
/// 支持修改：头像（点击选图，压缩 256px/JPEG80% 后上传）、
/// 昵称、简介、性别、生日、体重(kg)。
/// 字段对应数据库 users 表。
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;
  String? _gender; // 'male' | 'female' | 'other'
  DateTime? _birthday;
  bool _saving = false;

  /// 当前头像 URL（选图上传成功后立即更新，无需等"保存"按钮）。
  String? _avatarUrl;
  bool _uploadingAvatar = false;
  // 防止头像 URL 缓存导致图片不刷新：上传成功后给 URL 加个时间戳
  String? _avatarSuffix;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider).profile ?? {};
    _nicknameCtrl = TextEditingController(text: p['nickname'] as String? ?? '');
    _bioCtrl = TextEditingController(text: p['bio'] as String? ?? '');
    _weightCtrl = TextEditingController(
        text: p['weight_kg'] != null ? p['weight_kg'].toString() : '');
    _heightCtrl = TextEditingController(
        text: p['height_cm'] != null ? p['height_cm'].toString() : '');
    _gender = p['gender'] as String?;
    final b = p['birthday'] as String?;
    if (b != null) _birthday = DateTime.tryParse(b);
    _avatarUrl = p['avatar_url'] as String?;
  }

  /// 选图 → 裁剪 → 压缩 → 上传。
  /// ① image_picker 从相册选图
  /// ② image_cropper 弹出裁剪界面（1:1 方形，适合头像）
  /// ③ 裁剪输出时压缩到 256px / JPEG 80%
  /// ④ 上传到后端 + 更新显示
  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      // ① 选图
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return; // 用户取消

      // ② 裁剪（1:1 方形，输出 256px / JPEG 80%）
      final cropped = await ImageCropper().cropImage(
        sourcePath: xfile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          IOSUiSettings(
            title: '裁剪头像',
            aspectRatioLockEnabled: true,
            aspectRatioPickerButtonHidden: true,
            resetAspectRatioEnabled: false,
          ),
          AndroidUiSettings(
            toolbarTitle: '裁剪头像',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: Colors.black,
            lockAspectRatio: true,
          ),
        ],
        compressFormat: ImageCompressFormat.jpg,
        maxHeight: 256,
        maxWidth: 256,
        compressQuality: 80,
      );
      if (cropped == null) return; // 用户在裁剪界面取消

      final file = File(cropped.path);

      // ④ 上传 + 刷新
      final ok = await ref.read(profileProvider.notifier).uploadAvatar(file);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('头像上传失败，请检查网络')),
          );
        }
        return;
      }
      final newUrl = ref.read(profileProvider).profile?['avatar_url'] as String?;
      if (mounted) {
        setState(() {
          _avatarUrl = newUrl;
          _avatarSuffix = '?t=${DateTime.now().millisecondsSinceEpoch}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选图失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final fields = <String, dynamic>{
      'nickname': _nicknameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
    };
    if (_gender != null) fields['gender'] = _gender;
    if (_birthday != null) {
      fields['birthday'] = _birthday!.toIso8601String().split('T').first;
    }
    final w = double.tryParse(_weightCtrl.text.trim());
    if (w != null) fields['weight_kg'] = w;
    final h = double.tryParse(_heightCtrl.text.trim());
    if (h != null) fields['height_cm'] = h;

    final ok = await ref.read(profileProvider.notifier).updateProfile(fields);
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料已更新')),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请检查网络或登录状态')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像（点击选图上传）
            Center(
              child: GestureDetector(
                onTap: _uploadingAvatar ? null : _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(
                              '$_avatarUrl$_avatarSuffix',
                            )
                          : null,
                      child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                          ? const Icon(Icons.person, size: 56)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF000000),
                          shape: BoxShape.circle,
                        ),
                        child: _uploadingAvatar
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt,
                                size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '点击头像更换',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
            const SizedBox(height: 24),

            _Label('昵称'),
            TextField(
              controller: _nicknameCtrl,
              decoration: const InputDecoration(hintText: '请输入昵称'),
            ),
            const SizedBox(height: 16),

            _Label('简介'),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '介绍一下自己'),
            ),
            const SizedBox(height: 16),

            _Label('性别'),
            // Flutter 3.32+：用 RadioGroup 祖先统一管理选中值（替代逐个传 groupValue）
            RadioGroup<String>(
              groupValue: _gender,
              onChanged: (v) => setState(() => _gender = v),
              child: Row(
                children: const [
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('男'),
                      value: 'male',
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('女'),
                      value: 'female',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            _Label('生日'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_birthday == null
                  ? '请选择'
                  : '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _birthday ?? DateTime(2000),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _birthday = picked);
              },
            ),
            const SizedBox(height: 8),

            _Label('体重 (kg)'),
            TextField(
              controller: _weightCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '用于热量计算'),
            ),
            const SizedBox(height: 16),

            _Label('身高 (cm)'),
            TextField(
              controller: _heightCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '用于 BMI 计算'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: TextStyle(
              color: Colors.grey[700], fontSize: 13,
          fontWeight: FontWeight.w500)),
    );
  }
}
