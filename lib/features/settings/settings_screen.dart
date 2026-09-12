import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/platform/app_platform.dart';
import '../../core/platform/local_image.dart';

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cache_manager.dart';
import '../../core/audio/audio_effects.dart';
import '../../core/download/auto_download.dart';
import '../../core/floating/floating_lyrics.dart';
import '../../core/theme/accent.dart';
import '../../core/theme/app_skin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/background.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/theme/settings_prefs.dart';
import '../../core/settings/streaming_prefs.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';
import '../player/action_sheets.dart';
import '../player/cover_style.dart';
import '../player/mini_bar_style.dart';
import '../player/player_controller.dart';
import 'servers_screen.dart';

part 'settings_sheets_storage.dart';
part 'settings_sheets_appearance.dart';
part 'settings_sheets_audio.dart';
part 'settings_sheets_player.dart';

part 'settings_sub_playback.dart';
part 'settings_sub_effects.dart';
part 'settings_sub_network.dart';
part 'settings_sub_storage.dart';
part 'settings_sub_appearance.dart';
part 'settings_sub_player_style.dart';
part 'settings_sub_system.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(authControllerProvider).activeConfig;
    final effects = ref.watch(audioEffectsProvider);
    final streaming = ref.watch(streamingSettingsProvider);
    final skin = ref.watch(appSkinProvider);
    final coverStyle = ref.watch(coverStyleProvider);
    final cacheSize = ref.watch(audioCacheSizeProvider);
    final appVersion = ref.watch(_packageInfoProvider).valueOrNull;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            4,
            12,
            48 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _EntryCard(
              icon: Icons.play_circle_outline,
              title: '播放',
              subtitle: '循环 · 自动播放 · 速度 · 定时',
              onTap: () => _push(context, const _PlaybackSettingsPage()),
            ),
            _EntryCard(
              icon: Icons.equalizer,
              title: '音效',
              subtitle: effects.enabled ? '均衡器已开启' : '均衡器 · 低音 · 空间 · 线控',
              onTap: () => _push(context, const _EffectsSettingsPage()),
            ),
            _EntryCard(
              icon: Icons.wifi,
              title: '网络',
              subtitle:
                  'Wi-Fi ${streaming.wifiQuality.label} · 转码 ${streaming.transcodeFormat.label}',
              onTap: () => _push(context, const _NetworkSettingsPage()),
            ),
            _EntryCard(
              icon: Icons.storage_outlined,
              title: '存储与缓存',
              subtitle: cacheSize.when(
                data: (bytes) => '缓存 ${_fmtBytes(bytes)} · 边听边存 · 自动下载',
                loading: () => '边听边存 · 自动下载 · 缓存限额',
                error: (_, _) => '边听边存 · 自动下载 · 缓存限额',
              ),
              onTap: () => _push(context, const _StorageSettingsPage()),
            ),
            _EntryCard(
              icon: Icons.palette_outlined,
              title: '外观',
              subtitle: '${skin.label} · 主题色 · 背景',
              onTap: () => _push(context, const _AppearanceSettingsPage()),
            ),
            _EntryCard(
              icon: Icons.album_outlined,
              title: '播放器样式',
              subtitle: coverStyle.label,
              onTap: () => _push(context, const _PlayerStyleSettingsPage()),
            ),
            _EntryCard(
              icon: Icons.settings_outlined,
              title: '系统',
              subtitle: config != null
                  ? '${config.type.displayName} · ${appVersion?.version ?? ''}'
                  : '未连接 · ${appVersion?.version ?? ''}',
              onTap: () => _push(context, const _SystemSettingsPage()),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

// ---------- 入口卡片 ----------

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: ListTile(
          leading: Icon(icon, color: AppTheme.textDimOf(context)),
          title: Text(
            title,
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textFaintOf(context),
              fontSize: 12,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: AppTheme.textFaintOf(context),
            size: 22,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

// ---------- 共享组件 ----------

const _divider = Divider(height: 1, indent: 56);

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
                style: TextStyle(
                  color: AppTheme.textFaintOf(context),
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

class _SwitchTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final showIcons = ref.watch(settingsIconsProvider);
    return SwitchListTile(
      secondary: showIcons
          ? Icon(icon, color: AppTheme.textDimOf(context))
          : const SizedBox(width: 24),
      title: Text(
        title,
        style: TextStyle(color: AppTheme.textPrimaryOf(context), fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppTheme.textFaintOf(context), fontSize: 12),
      ),
      value: value,
      activeThumbColor: Theme.of(context).colorScheme.primary,
      onChanged: onChanged,
    );
  }
}

class _ActionTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final showIcons = ref.watch(settingsIconsProvider);
    return ListTile(
      leading: showIcons
          ? Icon(icon, color: iconColor ?? AppTheme.textDimOf(context))
          : const SizedBox(width: 24),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? AppTheme.textPrimaryOf(context),
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppTheme.textFaintOf(context), fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppTheme.textFaintOf(context),
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
      leading: Icon(icon, color: AppTheme.textDimOf(context)),
      title: Text(
        title,
        style: TextStyle(color: AppTheme.textPrimaryOf(context), fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppTheme.textFaintOf(context), fontSize: 12),
      ),
    );
  }
}

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
          leading: Icon(Icons.volume_up, color: AppTheme.textDimOf(context)),
          title: Text(
            '音量',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
            ),
          ),
          subtitle: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: volume,
              activeColor: Theme.of(context).colorScheme.primary,
              inactiveColor: AppTheme.textFaintOf(context),
              onChanged: (v) => player.setVolume(v),
            ),
          ),
          trailing: SizedBox(
            width: 42,
            child: Text(
              '${(volume * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: AppTheme.textFaintOf(context),
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- 工具函数 ----------

String _fmtBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

Future<void> _setAutoPlay(WidgetRef ref, bool v) async {
  ref.read(autoPlayProvider.notifier).state = v;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_play', v);
  } catch (_) {}
}

String _fmtRemain(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

Future<void> _clearLyricOffsets(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(lyricOffsetKeyPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    showToast('已清理 ${keys.length} 条歌词偏移');
  } catch (_) {
    showToast('清理失败', error: true);
  }
}

Future<void> _clearImageCache(BuildContext context) async {
  try {
    await DefaultCacheManager().emptyCache();
    showToast('图片缓存已清理');
  } catch (_) {
    showToast('清理失败', error: true);
  }
}

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await glassDialog<bool>(
    context,
    title: '退出登录',
    content: Text(
      '将清除本地会话与播放状态，确定退出？',
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
        child: const Text('确定'),
      ),
    ],
  );
  if (confirmed == true) {
    await ref.read(authControllerProvider.notifier).logout();
  }
}
