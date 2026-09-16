import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/toast.dart';
import 'auth_controller.dart';

/// 编辑服务器（地址/端口/路径/HTTPS/用户名/密码/备注名）：
/// 各字段从现有配置预填（密码从存储 secrets 回填），保存时用新凭证完整
/// 走一次登录验证，失败原配置不动；编辑当前激活服务器保存后即刻生效
class EditServerScreen extends ConsumerStatefulWidget {
  const EditServerScreen({super.key, required this.config});

  final ServerConfig config;

  @override
  ConsumerState<EditServerScreen> createState() => _EditServerScreenState();
}

class _EditServerScreenState extends ConsumerState<EditServerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  final _pathController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _https = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _nameController.text = config.name;
    _usernameController.text = config.username;
    // 拆解 serverUrl 回填 地址/端口/路径/HTTPS（与登录页的拼接逻辑互逆）
    final uri = Uri.tryParse(config.serverUrl);
    if (uri != null && uri.hasScheme && uri.hasAuthority) {
      _https = uri.scheme == 'https';
      _serverController.text = uri.host;
      if (uri.hasPort) _portController.text = '${uri.port}';
      _pathController.text = uri.pathSegments.join('/');
    } else {
      _serverController.text = config.serverUrl;
    }
    // 密码明文随 secrets 持久化过，异步回填（异常时留空由用户重输）
    ref.read(authControllerProvider.notifier).storedPassword(config.id).then((
      pwd,
    ) {
      if (pwd != null && mounted && _passwordController.text.isEmpty) {
        _passwordController.text = pwd;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _portController.dispose();
    _pathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      // 与登录页同款归一化：地址框粘贴完整 URL（协议/子路径）时自动拆解
      var host = _serverController.text.trim();
      var https = _https;
      if (host.startsWith('https://')) {
        https = true;
        host = host.substring(8);
      } else if (host.startsWith('http://')) {
        host = host.substring(7);
      }
      final slash = host.indexOf('/');
      if (slash >= 0) host = host.substring(0, slash);
      while (host.endsWith('/')) {
        host = host.substring(0, host.length - 1);
      }
      final port = _portController.text.trim();
      if (port.isNotEmpty && !host.contains(':')) host = '$host:$port';
      var path = _pathController.text.trim();
      while (path.startsWith('/')) {
        path = path.substring(1);
      }
      while (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (https != _https) _https = https;
      await ref
          .read(authControllerProvider.notifier)
          .editServer(
            id: widget.config.id,
            serverUrl:
                '${https ? 'https' : 'http'}://$host'
                '${path.isEmpty ? '' : '/$path'}',
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text,
          );
      if (!mounted) return;
      showToast('已保存');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showToast('保存失败：${appUserMessage(error)}', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('编辑服务器')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _GroupLabel('备注名'),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: '留空保持「${widget.config.type.displayName}」不变',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _GroupLabel('服务器'),
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
                                hintText: widget.config.type.urlHint,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
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
                              decoration: const InputDecoration(hintText: '选填'),
                              validator: (v) {
                                final s = v?.trim() ?? '';
                                if (s.isEmpty) return null;
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
                    decoration: InputDecoration(
                      hintText: widget.config.type.pathHint,
                    ),
                  ),
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
                        activeThumbColor: Theme.of(context).colorScheme.primary,
                        onChanged: (v) => setState(() => _https = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _GroupLabel('登录信息'),
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
                    onFieldSubmitted: (_) => _save(),
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
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
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
                      onPressed: _submitting ? null : _save,
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
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
