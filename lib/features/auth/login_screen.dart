import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/skin_tokens.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/toast.dart';
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
  final _portController = TextEditingController();
  final _pathController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _https = false;
  bool _submitting = false;

  @override
  void dispose() {
    _serverController.dispose();
    _portController.dispose();
    _pathController.dispose();
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
        host = host.substring(7);
      }
      // 地址框里粘贴的子路径（如 ip:5666/music）转移到路径位
      final slash = host.indexOf('/');
      var pastedPath = '';
      if (slash >= 0) {
        pastedPath = host.substring(slash);
        host = host.substring(0, slash);
      }
      while (host.endsWith('/')) {
        host = host.substring(0, host.length - 1);
      }
      // 独立端口输入框（选填）：粘贴的完整 URL 已带端口时以域名框为准，不重复拼接
      final port = _portController.text.trim();
      if (port.isNotEmpty && !host.contains(':')) {
        host = '$host:$port';
      }
      // 路径位（选填）优先于地址框带出的子路径
      var path = _pathController.text.trim();
      if (path.isEmpty) path = pastedPath;
      while (path.startsWith('/')) {
        path = path.substring(1);
      }
      while (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (https != _https) _https = https;
      await ref
          .read(authControllerProvider.notifier)
          .login(
            widget.serverType,
            '${https ? 'https' : 'http'}://$host${path.isEmpty ? '' : '/$path'}',
            _usernameController.text.trim(),
            _passwordController.text,
          );
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (error) {
      if (!mounted) return;
      showToast('登录失败：${appUserMessage(error)}', error: true);
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
                          style: TextStyle(
                            color: AppTheme.textPrimaryOf(context),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          type.tagline,
                          style: TextStyle(
                            color: AppTheme.textDimOf(context),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const _GroupLabel('服务器'),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('服务器地址'),
                                TextFormField(
                                  controller: _serverController,
                                  keyboardType: TextInputType.url,
                                  style: TextStyle(
                                    color: AppTheme.textPrimaryOf(context),
                                    fontSize: 16,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: type.urlHint,
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? '请输入服务器地址'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('端口'),
                                TextFormField(
                                  controller: _portController,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    color: AppTheme.textPrimaryOf(context),
                                    fontSize: 16,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: '选填',
                                  ),
                                  validator: (v) {
                                    final s = v?.trim() ?? '';
                                    if (s.isEmpty) return null; // 选填
                                    final p = int.tryParse(s);
                                    return (p == null || p < 1 || p > 65535)
                                        ? '1-65535'
                                        : null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('路径'),
                      TextFormField(
                        controller: _pathController,
                        keyboardType: TextInputType.url,
                        style: TextStyle(
                          color: AppTheme.textPrimaryOf(context),
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(hintText: type.pathHint),
                      ),
                      // HTTPS 开关（默认 HTTP，局域网直连无需开启）
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '启用 HTTPS',
                            style: TextStyle(
                              color: AppTheme.textDimOf(context),
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
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _GroupLabel('登录信息'),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel('用户名'),
                      TextFormField(
                        controller: _usernameController,
                        autofillHints: const [AutofillHints.username],
                        style: TextStyle(
                          color: AppTheme.textPrimaryOf(context),
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
                        style: TextStyle(
                          color: AppTheme.textPrimaryOf(context),
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
                      const SizedBox(height: 24),
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
        style: TextStyle(color: AppTheme.textPrimaryOf(context), fontSize: 16),
      ),
    );
  }
}

/// 输入分组标题（服务器 / 登录信息）
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textDimOf(context),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
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
        color: SkinTokens.of(context).surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        type.fallbackIcon,
        size: 22,
        color: AppTheme.textDimOf(context),
      ),
    );
  }
}
