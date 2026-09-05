import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../settings/servers_screen.dart';
import 'home_providers.dart';

/// 服务器详情页（资料库卡片点击进入，对齐设计图「资料库图标点进去的详情」）：
/// 头部（类型 + 别名 + 刷新）→ 资料库统计（歌曲/专辑/歌手/歌单）
/// → 用户设置（用户名/管理服务器）→ 资料库管理（连接线路/重新同步/删除资料库）。
class ServerDetailScreen extends ConsumerWidget {
  const ServerDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(authControllerProvider).activeConfig;
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      appBar: AppBar(title: Text(config?.type.displayName ?? '服务器')),
      body: config == null
          ? const Center(
              child: Text('未连接服务器', style: TextStyle(color: Colors.white38)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(config: config),
                const SizedBox(height: 16),
                _StatsCard(),
                const SizedBox(height: 20),
                const _SectionLabel('用户设置'),
                _UserSettingsCard(config: config),
                const SizedBox(height: 20),
                const _SectionLabel('资料库管理'),
                _ManageCard(config: config),
              ],
            ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.m),
          ),
          child: Icon(config.type.fallbackIcon, color: primary, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                config.type.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                config.serverUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {
            ref.invalidate(songTotalProvider);
            ref.invalidate(playlistsProvider);
            ref.invalidate(librarySongsProvider);
            ref.invalidate(libraryAlbumsProvider);
            ref.invalidate(artistsProvider);
          },
          child: const Text('刷新'),
        ),
      ],
    );
  }
}

/// 资料库统计：歌曲 / 专辑 / 歌手 / 歌单（歌手不支持的后端显示 —）
class _StatsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(songTotalProvider).valueOrNull ?? 0;
    final albums = ref.watch(libraryAlbumsProvider).valueOrNull;
    final artists = ref.watch(artistsProvider).valueOrNull;
    final playlists = ref.watch(playlistsProvider).valueOrNull;
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _statRow(context, '歌曲', '$total'),
          _divider(),
          _statRow(context, '专辑', albums == null ? '…' : '${albums.length}'),
          _divider(),
          _statRow(context, '歌手', artists == null ? '—' : '${artists.length}'),
          _divider(),
          _statRow(
            context,
            '歌单',
            playlists == null ? '…' : '${playlists.length}',
          ),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.08));
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
    );
  }
}

class _UserSettingsCard extends ConsumerWidget {
  const _UserSettingsCard({required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _row(context, '用户名', value: config.username),
          _divider(),
          _row(
            context,
            '管理服务器',
            trailing: const Icon(
              Icons.chevron_right,
              size: 20,
              color: Colors.white38,
            ),
            onTap: () =>
                Navigator.of(context)
                    .push(fadeRoute<void>(const ServersScreen())),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.08));
}

class _ManageCard extends ConsumerWidget {
  const _ManageCard({required this.config});

  final ServerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _row(context, '别名', value: config.name),
          _divider(),
          _row(context, '连接线路', value: config.serverUrl, valueCompact: true),
          _divider(),
          _row(
            context,
            '重新同步资料库',
            onTap: () async {
              ref.invalidate(songTotalProvider);
              ref.invalidate(playlistsProvider);
              ref.invalidate(librarySongsProvider);
              ref.invalidate(libraryAlbumsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已开始重新同步'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          _divider(),
          _row(
            context,
            '删除资料库',
            valueColor: Colors.redAccent,
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await glassDialog<bool>(
      context,
      title: '删除资料库',
      content: Text(
        '确定删除「${config.name}」？\n将清除该服务器的本地会话数据。',
        style: const TextStyle(
          color: Colors.white70,
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
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('删除'),
        ),
      ],
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).removeServer(config.id);
    }
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.08));
}

/// 通用行：label 左、值/箭头右、整行可点
Widget _row(
  BuildContext context,
  String label, {
  String? value,
  Color? valueColor,
  bool valueCompact = false,
  Widget? trailing,
  VoidCallback? onTap,
}) {
  final valueStyle = TextStyle(
    color: valueColor ?? Colors.white.withValues(alpha: 0.7),
    fontSize: 15,
  );
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.s),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
            ),
          ),
          const Spacer(),
          if (value != null)
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
            ),
          if (value != null && valueCompact) const SizedBox(width: 4),
          ?trailing,
        ],
      ),
    ),
  );
}
