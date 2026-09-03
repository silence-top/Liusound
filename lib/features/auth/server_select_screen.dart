import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_type.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../settings/servers_screen.dart';
import 'auth_controller.dart';
import 'login_screen.dart';

class ServerSelectScreen extends ConsumerWidget {
  const ServerSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              const SizedBox(height: 48),
              Center(
                child: Image.asset('assets/app/logo.png',
                    width: 80, height: 80),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('选择你的音乐服务',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text('支持 Navidrome / Subsonic / Jellyfin / Emby 等',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13)),
              ),
              const SizedBox(height: 32),
              if (auth.servers.isNotEmpty) ...[
                _SectionHeader('已保存的服务器'),
                const SizedBox(height: 8),
                ...auth.servers.map((s) => _SavedServerTile(
                      config: s,
                      isActive: s.id == auth.activeServerId,
                    )),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      fadeRoute<void>(const ServersScreen()),
                    ),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('管理服务器'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _SectionHeader('添加新服务器'),
              const SizedBox(height: 8),
              ...ServerType.values.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BackendTypeCard(type: t),
                  )),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            color: Colors.white38,
            fontSize: 13,
            fontWeight: FontWeight.bold));
  }
}

class _SavedServerTile extends ConsumerWidget {
  const _SavedServerTile({
    required this.config,
    required this.isActive,
  });

  final ServerConfig config;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      onTap: isActive
          ? null
          : () async {
              await ref.read(authControllerProvider.notifier).switchServer(
                    config.id,
                  );
            },
      child: Row(
        children: [
          _TypeIcon(type: config.type, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                const SizedBox(height: 2),
                Text('${config.serverUrl} · ${config.username}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('当前',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            )
          else
            const Icon(Icons.chevron_right,
                size: 20, color: Colors.white24),
        ],
      ),
    );
  }
}

class _BackendTypeCard extends StatelessWidget {
  const _BackendTypeCard({required this.type});

  final ServerType type;

  @override
  Widget build(BuildContext context) {
    final available = type.implemented;
    return Opacity(
      opacity: available ? 1.0 : 0.45,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: available
            ? () => Navigator.of(context).push(
                  fadeRoute<void>(LoginScreen(serverType: type)),
                )
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${type.displayName} 适配器开发中，敬请期待'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
        child: Row(
          children: [
            _TypeIcon(type: type, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(type.displayName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                      if (!available) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('即将推出',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(type.tagline,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 22,
                color: available ? const Color(0xFF666666) : Colors.white12),
          ],
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type, this.size = 28});

  final ServerType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (type.hasLogoAsset) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(type.iconAsset, width: size, height: size),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(type.fallbackIcon,
          size: size * 0.65, color: Colors.white70),
    );
  }
}
