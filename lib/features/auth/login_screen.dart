import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../shared/widgets/glass.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.serverType});

  final ServerType serverType;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _https = false;
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
      var host = _serverController.text.trim();
      var https = _https;
      // 直接粘贴完整 URL 时自动识别协议并同步开关
      if (host.startsWith('https://')) {
        https = true;
        host = host.substring(8);
      } else if (host.startsWith('http://')) {
        https = false;
        host = host.substring(7);
      }
      while (host.endsWith('/')) {
        host = host.substring(0, host.length - 1);
      }
      if (https != _https) _https = https;
      await ref
          .read(authControllerProvider.notifier)
          .login(
            widget.serverType,
            '${https ? 'https' : 'http'}://$host',
            _usernameController.text.trim(),
            _passwordController.text,
          );
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登录失败：$error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.serverType;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 32),
                Row(
                  children: [
                    _TypeIcon(type: type),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '登录 ${type.displayName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          type.tagline,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('服务器地址'),
                      TextFormField(
                        controller: _serverController,
                        keyboardType: TextInputType.url,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(hintText: type.urlHint),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null,
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('用户名'),
                      TextFormField(
                        controller: _usernameController,
                        autofillHints: const [AutofillHints.username],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: const InputDecoration(),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('密码'),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? '请输入密码' : null,
                      ),
                      const SizedBox(height: 8),
                      // 登录按钮右上方：HTTPS 开关（默认 HTTP，局域网直连无需开启）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text(
                            '启用 HTTPS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Switch(
                            value: _https,
                            activeThumbColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            onChanged: (v) => setState(() => _https = v),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});

  final ServerType type;

  @override
  Widget build(BuildContext context) {
    if (type.hasLogoAsset) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(type.iconAsset, width: 36, height: 36),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(type.fallbackIcon, size: 22, color: Colors.white70),
    );
  }
}
