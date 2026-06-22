import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

/// 注册页：新用户填昵称，创建本地账号。
///
/// 手机号通过构造参数传入（来自登录页验证码通过后的新用户流程）。
class RegisterPage extends ConsumerStatefulWidget {
  final String? phone;

  const RegisterPage({super.key, this.phone});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _nicknameController = TextEditingController();
  final Set<String> _selectedSports = {};
  int _currentStep = 0;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入昵称')),
      );
      return;
    }
    await ref.read(authProvider.notifier).register(
          widget.phone ?? '',
          nickname,
        );
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth.status == AuthStatus.authenticated) {
      context.go('/feed');
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep++);
          } else {
            _finish();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          } else {
            context.go('/login');
          }
        },
        controlsBuilder: (context, details) {
          final isLast = _currentStep == 2;
          return Row(
            children: [
              FilledButton(
                onPressed: details.onStepContinue,
                child: Text(isLast ? '完成注册' : '下一步'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: details.onStepCancel,
                child: Text(_currentStep == 0 ? '返回登录' : '上一步'),
              ),
            ],
          );
        },
        steps: [
          Step(
            title: const Text('昵称'),
            content: TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: '你的昵称',
                hintText: '其他用户会看到的名字',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Step(
            title: const Text('运动偏好'),
            content: Wrap(
              spacing: 8,
              children: ['跑步', '骑行', '徒步', '走路']
                  .map((sport) => FilterChip(
                        label: Text(sport),
                        selected: _selectedSports.contains(sport),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selectedSports.add(sport);
                            } else {
                              _selectedSports.remove(sport);
                            }
                          });
                        },
                      ))
                  .toList(),
            ),
          ),
          Step(
            title: const Text('头像'),
            content: Column(
              children: [
                const CircleAvatar(
                  radius: 48,
                  child: Icon(Icons.camera_alt, size: 32),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text('选择头像（开发中）'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
