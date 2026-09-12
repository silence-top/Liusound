import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../core/errors/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/skin_tokens.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/toast.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../auth/login_screen.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 56,
              backgroundColor: Colors.transparent,
              foregroundColor: AppTheme.textPrimaryOf(context),
              title: const Text('服务器管理'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  GlassCard(
                    child: ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.s),
                        ),
                        child: Icon(
                          Icons.add,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        '添加服务器',
                        style: TextStyle(
                          color: AppTheme.textPrimaryOf(context),
                          fontSize: 16,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppTheme.textFaintOf(context),
                      ),
                      onTap: () => _showAddServerSheet(context),
                    ),
                  ),
                  if (auth.servers.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          '暂无已保存的服务器',
                          style: TextStyle(
                            color: AppTheme.textFaintOf(context),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  else
                    ...auth.servers.map(
                      (config) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ServerCard(
                          config: config,
                          isActive: config.id == auth.activeServerId,
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 选择要添加的服务器类型（未实现的后端置灰），选后进登录页
  void _showAddServerSheet(BuildContext context) {
    glassBottomSheet(
      context,
      SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in ServerType.values)
              ListTile(
                leading: _ServerIcon(type: type),
                title: Text(
                  type.displayName,
                  style: TextStyle(
                    color: type.implemented
                        ? AppTheme.textPrimaryOf(context)
                        : AppTheme.textFaintOf(context),
                  ),
                ),
                trailing: type.implemented
                    ? null
                    : Text(
                        '即将推出',
                        style: TextStyle(
                          color: AppTheme.textFaintOf(context),
                          fontSize: 12,
                        ),
                      ),
                onTap: type.implemented
                    ? () {
                        Navigator.of(context).pop();
                        Navigator.of(
                          context,
                        ).push(fadeRoute<void>(LoginScreen(serverType: type)));
                      }
                    : null,
              ),
          ],
        ),
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
      padding: const EdgeInsets.all(16),
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
                          child: Text(
                            config.name,
                            style: TextStyle(
                              color: AppTheme.textPrimaryOf(context),
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '当前连接',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config.serverUrl,
                      style: TextStyle(
                        color: AppTheme.textFaintOf(context),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: AppTheme.textFaintOf(context),
              ),
              const SizedBox(width: 4),
              Text(
                config.username,
                style: TextStyle(
                  color: AppTheme.textFaintOf(context),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (!isActive)
                TextButton.icon(
                  onPressed: () => _switchTo(ref),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('切换', style: TextStyle(fontSize: 14)),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              PopupMenuButton<_Action>(
                onSelected: (action) => _onAction(action, context, ref),
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: AppTheme.textFaintOf(context),
                ),
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
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppTheme.heartRed,
                        ),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: AppTheme.heartRed)),
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
    _Action action,
    BuildContext context,
    WidgetRef ref,
  ) async {
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
    try {
      final ok = await ref
          .read(authControllerProvider.notifier)
          .validateServer(config.id);
      showToast(ok ? '连接正常' : '连接失败：会话无效', error: !ok);
    } catch (e) {
      showToast('连接失败：${appUserMessage(e)}', error: true);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await glassDialog<bool>(
      context,
      title: '删除服务器',
      content: Text(
        '确定删除「${config.name}」？\n将清除该服务器的本地会话数据。',
        style: TextStyle(
          color: AppTheme.textDimOf(context),
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppTheme.heartRed),
          child: const Text('删除'),
        ),
      ],
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
        color: SkinTokens.of(context).surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        type.fallbackIcon,
        size: 20,
        color: AppTheme.textDimOf(context),
      ),
    );
  }
}
