import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/profile_provider.dart';

/// 编辑个人资料页。
///
/// 支持修改：昵称、简介、性别、生日、体重(kg)。
/// 头像目前用占位（后续可接入 image_picker + Supabase Storage）。
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
  String? _gender; // 'male' | 'female' | 'other'
  DateTime? _birthday;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider).profile ?? {};
    _nicknameCtrl = TextEditingController(text: p['nickname'] as String? ?? '');
    _bioCtrl = TextEditingController(text: p['bio'] as String? ?? '');
    _weightCtrl = TextEditingController(
        text: p['weight_kg'] != null ? p['weight_kg'].toString() : '');
    _gender = p['gender'] as String?;
    final b = p['birthday'] as String?;
    if (b != null) _birthday = DateTime.tryParse(b);
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    _weightCtrl.dispose();
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
            // 头像（占位，后续接入图片上传）
            Center(
              child: Stack(
                children: [
                  const CircleAvatar(radius: 48, child: Icon(Icons.person, size: 56)),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6B35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
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
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('男'),
                    value: 'male',
                    groupValue: _gender,
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('女'),
                    value: 'female',
                    groupValue: _gender,
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
              ],
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
