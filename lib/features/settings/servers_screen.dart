import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../auth/auth_controller.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('服务器管理')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (auth.servers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('暂无已保存的服务器',
                    style: TextStyle(color: Colors.white38, fontSize: 15)),
              ),
            )
          else
            ...auth.servers.map((config) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ServerCard(
                    config: config,
                    isActive: config.id == auth.activeServerId,
                  ),
                )),
        ],
      ),
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.config, required this.isActive});

  final ServerConfig config;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ServerIcon(type: config.type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(config.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16)),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('当前连接',
                                style: TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(config.serverUrl,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 14, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(width: 4),
              Text(config.username,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12)),
              const Spacer(),
              if (!isActive)
                TextButton.icon(
                  onPressed: () => _switchTo(ref),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('切换', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              PopupMenuButton<_Action>(
                onSelected: (action) =>
                    _onAction(action, context, ref),
                icon: const Icon(Icons.more_vert,
                    size: 20, color: Colors.white38),
                itemBuilder: (_) => [
                  if (!isActive)
                    const PopupMenuItem(
                      value: _Action.switchTo,
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz, size: 18),
                          SizedBox(width: 8),
                          Text('切换到此服务器'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: _Action.test,
                    child: Row(
                      children: [
                        Icon(Icons.wifi_find, size: 18),
                        SizedBox(width: 8),
                        Text('检测连接'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: _Action.delete,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('删除',
                            style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _switchTo(WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).switchServer(config.id);
  }

  Future<void> _onAction(
      _Action action, BuildContext context, WidgetRef ref) async {
    switch (action) {
      case _Action.switchTo:
        await _switchTo(ref);
      case _Action.test:
        await _testConnection(context, ref);
      case _Action.delete:
        await _confirmDelete(context, ref);
    }
  }

  Future<void> _testConnection(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final adapter = ref.read(serverAdapterProvider);
    if (adapter == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法创建适配器')),
      );
      return;
    }
    try {
      final ok = await adapter.validateSession();
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? '连接正常' : '连接失败：会话无效'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('连接失败：$e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除「${config.name}」？\n将清除该服务器的本地会话数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).removeServer(config.id);
    }
  }
}

enum _Action { switchTo, test, delete }

class _ServerIcon extends StatelessWidget {
  const _ServerIcon({required this.type});

  final ServerType type;

  @override
  Widget build(BuildContext context) {
    if (type.hasLogoAsset) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(type.iconAsset, width: 32, height: 32),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(type.fallbackIcon, size: 20, color: Colors.white70),
    );
  }
}
