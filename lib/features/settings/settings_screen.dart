import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/glass_quality.dart';
import '../auth/auth_controller.dart';
import '../player/action_sheets.dart';
import '../player/cover_style.dart';
import '../player/player_controller.dart';
import 'servers_screen.dart';

/// 版本号读自 pubspec（package_info_plus），避免手写常量与发布版本脱节
final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

/// 设置页（对齐设计图「设置」分组卡片样式）：
/// 播放（循环播放 / 启动后自动播放 / 定时停止 / 播放速度 / 音量）
/// → 存储（图片缓存 / 歌词偏移）→ 服务器 → 版本 → 退出登录。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(authControllerProvider).activeConfig;
    final loop = ref.watch(loopPlaybackProvider);
    final autoPlay = ref.watch(autoPlayProvider);
    final sleepRemain = ref.watch(sleepTimerProvider);
    final speed = ref.watch(playbackSpeedProvider);
    final glassLevel = ref.watch(glassQualityProvider);
    final coverStyle = ref.watch(coverStyleProvider);
    final appVersion = ref.watch(_packageInfoProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 48),
        children: [
          _GroupCard(
            title: '播放',
            children: [
              _SwitchTile(
                icon: Icons.repeat,
                title: '循环播放',
                subtitle: '关闭后播完整个队列即停止',
                value: loop,
                onChanged: (v) =>
                    ref.read(loopPlaybackProvider.notifier).state = v,
              ),
              _divider,
              _SwitchTile(
                icon: Icons.play_circle_outline,
                title: '启动后自动播放',
                subtitle: '打开应用时恢复上次播放进度并继续播放',
                value: autoPlay,
                onChanged: (v) => _setAutoPlay(ref, v),
              ),
              _divider,
              _ActionTile(
                icon: Icons.timer_outlined,
                title: '定时停止播放',
                subtitle: sleepRemain != null
                    ? '剩余 ${_fmtRemain(sleepRemain)}'
                    : '未启用',
                onTap: () => showSleepTimerPicker(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.speed,
                title: '播放速度',
                subtitle: speed == 1.0 ? '正常' : '${speed.toStringAsFixed(2)}x',
                onTap: () => showSpeedPicker(context),
              ),
              _divider,
              const _VolumeTile(),
            ],
          ),
          _GroupCard(
            title: '存储',
            children: [
              _ActionTile(
                icon: Icons.image_outlined,
                title: '清除图片缓存',
                subtitle: '清理磁盘上的封面图片缓存',
                onTap: () => _clearImageCache(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.format_line_spacing,
                title: '清理歌词偏移缓存',
                subtitle: '删除所有歌曲保存的歌词时间偏移',
                onTap: () => _clearLyricOffsets(context),
              ),
            ],
          ),
          _GroupCard(
            title: '外观',
            children: [
              _ActionTile(
                icon: Icons.auto_awesome,
                title: '液态玻璃效果',
                subtitle: glassLevel.label,
                onTap: () => _showGlassLevelPicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: coverStyle.icon,
                title: '唱片形态',
                subtitle: coverStyle.label,
                onTap: () => _showCoverStylePicker(context, ref),
              ),
            ],
          ),
          _GroupCard(
            title: '服务器',
            children: [
              _ActionTile(
                icon: Icons.dns_outlined,
                title: config?.type.displayName ?? '未连接',
                subtitle: config != null
                    ? '${config.serverUrl} · ${config.username}'
                    : '点击添加服务器',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ServersScreen(),
                  ),
                ),
              ),
            ],
          ),
          _GroupCard(
            children: [
              _InfoTile(
                icon: Icons.info_outline,
                title: '版本',
                subtitle: appVersion == null
                    ? '读取中…'
                    : '${appVersion.version}+${appVersion.buildNumber}',
              ),
              _divider,
              _ActionTile(
                icon: Icons.logout,
                title: '退出登录',
                subtitle: '清除本地会话与播放状态',
                iconColor: Colors.redAccent,
                titleColor: Colors.redAccent,
                onTap: () => _confirmLogout(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setAutoPlay(WidgetRef ref, bool v) async {
    ref.read(autoPlayProvider.notifier).state = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_play', v);
    } catch (_) {
      // 持久化失败静默（本次会话内仍然生效）
    }
  }

  String _fmtRemain(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  /// 清理全部歌词偏移（对标 1.x clearAllLyricOffsets）
  Future<void> _clearLyricOffsets(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith(lyricOffsetKeyPrefix))
          .toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      _toast(messenger, '已清理 ${keys.length} 条歌词偏移');
    } catch (_) {
      _toast(messenger, '清理失败');
    }
  }

  Future<void> _clearImageCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DefaultCacheManager().emptyCache();
      _toast(messenger, '图片缓存已清理');
    } catch (_) {
      _toast(messenger, '清理失败');
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await glassDialog<bool>(
      context,
      title: '退出登录',
      content: const Text(
        '将清除本地会话与播放状态，确定退出？',
        style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确定'),
        ),
      ],
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  void _toast(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

// ---------- 分组卡片组件 ----------

const _divider = Divider(height: 1, indent: 56);

/// 液态玻璃档位选择（关闭 / 标准 / 增强），选择后立即生效并持久化
Future<void> _showGlassLevelPicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(glassQualityProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '液态玻璃效果',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final level in GlassLevel.values)
          ListTile(
            leading: level == current
                ? const Icon(Icons.check, color: AppTheme.primary)
                : const SizedBox(width: 24),
            title: Text(
              level.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref.read(glassQualityProvider.notifier).setLevel(level);
              Navigator.of(context).pop();
            },
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '关闭在低端设备上更流畅；增强提高模糊强度，高配设备体验更佳',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// 唱片形态选择（§4.2：黑胶 / CD / 方形玻璃卡片 / 全屏模糊大图）
Future<void> _showCoverStylePicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(coverStyleProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '唱片形态',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final style in CoverStyle.values)
          ListTile(
            leading: Icon(style.icon, color: Colors.white70),
            trailing: style == current
                ? const Icon(Icons.check, color: AppTheme.primary)
                : null,
            title: Text(
              style.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref.read(coverStyleProvider.notifier).setStyle(style);
              Navigator.of(context).pop();
            },
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '黑胶与 CD 随播放旋转，黑胶带唱针升降动画；'
            '方形卡片与全屏大图保持静态，模糊强度跟随液态玻璃档位',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                title!,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      value: value,
      activeThumbColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.white70),
      title: Text(
        title,
        style: TextStyle(color: titleColor ?? Colors.white, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: Colors.white24,
        size: 22,
      ),
      onTap: onTap,
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}

/// 音量调节行（实时调节播放器音量，StreamBuilder 局部重建）
class _VolumeTile extends ConsumerWidget {
  const _VolumeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);
    return StreamBuilder<double>(
      stream: player.volumeStream,
      initialData: player.volume,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 1.0;
        return ListTile(
          leading: const Icon(Icons.volume_up, color: Colors.white70),
          title: const Text(
            '音量',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          subtitle: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: volume,
              activeColor: AppTheme.primary,
              inactiveColor: Colors.white24,
              onChanged: (v) => player.setVolume(v),
            ),
          ),
          trailing: SizedBox(
            width: 42,
            child: Text(
              '${(volume * 100).round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        );
      },
    );
  }
}
