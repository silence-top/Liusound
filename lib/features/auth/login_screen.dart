import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

/// 登录页（对标 1.x LoginScreen：地址规范化 + 表单校验 + 登录态反馈）
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).login(
            normalizeServerUrl(_serverController.text),
            _usernameController.text.trim(),
            _passwordController.text,
          );
      // 登录成功后由根组件按 authControllerProvider 分流，无需手动导航
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 Navidrome')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              TextFormField(
                controller: _serverController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如 http://192.168.1.10:4533',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
