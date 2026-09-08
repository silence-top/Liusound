import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
import '../../shared/widgets/glass_quality.dart';
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
    final autoOpen = ref.watch(autoOpenPlayerProvider);
    final crossfade = ref.watch(crossfadeSecondsProvider);
    final effects = ref.watch(audioEffectsProvider);
    final sleepRemain = ref.watch(sleepTimerProvider);
    final speed = ref.watch(playbackSpeedProvider);
    final glassLevel = ref.watch(glassQualityProvider);
    final coverStyle = ref.watch(coverStyleProvider);
    final accent = ref.watch(appAccentProvider);
    final skin = ref.watch(appSkinProvider);
    final bgConfig = ref.watch(backgroundProvider);
    final barStyle = ref.watch(miniBarStyleProvider);
    final barOffset = ref.watch(miniBarOffsetProvider);
    final showIcons = ref.watch(settingsIconsProvider);
    final endText = ref.watch(listEndTextProvider);
    final powerSave = ref.watch(powerSaveProvider);
    final floatingLyrics = ref.watch(floatingLyricsProvider);
    final streaming = ref.watch(streamingSettingsProvider);
    // 打开设置页即后台静默探测服务端转码能力，供音质选择器判定是否放行转码档
    ref.watch(transcodeSupportProvider);
    final network = ref.watch(networkSettingsProvider);
    final cache = ref.watch(cacheSettingsProvider);
    final cacheSize = ref.watch(audioCacheSizeProvider);
    final appVersion = ref.watch(_packageInfoProvider).valueOrNull;

    // 嵌在 AppShell 顶部图标导航之下：不再自带 AppBar，避免双层标题栏叠加
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 48),
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
              _SwitchTile(
                icon: Icons.open_in_new_off,
                title: '点歌自动打开播放页',
                subtitle: '关闭后点歌仅播放，不弹出全屏播放器',
                value: autoOpen,
                onChanged: (v) =>
                    ref.read(autoOpenPlayerProvider.notifier).set(v),
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
              _ActionTile(
                icon: Icons.swap_horiz,
                title: '交叉淡入淡出',
                subtitle: crossfade == 0 ? '关闭' : '$crossfade 秒',
                onTap: () => showCrossfadePicker(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.equalizer,
                title: '音效（均衡器 / 低音 / 空间）',
                subtitle: effects.enabled ? '已开启' : '关闭',
                onTap: () => _showEffectsPanel(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.headphones,
                title: '耳机线控',
                subtitle: '自定义单击 / 双击 / 三击动作',
                onTap: () => _showHeadsetSheet(context),
              ),
              _divider,
              const _VolumeTile(),
            ],
          ),
          _GroupCard(
            title: '网络与缓存',
            children: [
              _ActionTile(
                icon: Icons.music_note_outlined,
                title: '在线音质（Wi-Fi）',
                subtitle: streaming.wifiQuality.label,
                onTap: () => _showQualityPicker(context, ref, cellular: false),
              ),
              _divider,
              _ActionTile(
                icon: Icons.cell_tower,
                title: '在线音质（移动网络）',
                subtitle: streaming.cellularQuality.label,
                onTap: () => _showQualityPicker(context, ref, cellular: true),
              ),
              _divider,
              _ActionTile(
                icon: Icons.graphic_eq,
                title: '转码格式',
                subtitle: streaming.transcodeFormat.label,
                onTap: () => _showTranscodeFormatPicker(context, ref),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.import_export,
                title: '移动网络传输',
                subtitle: streaming.cellularAllowed
                    ? '允许在移动网络下播放与下载'
                    : '关闭后仅 Wi-Fi 可播放',
                value: streaming.cellularAllowed,
                onChanged: (v) => ref
                    .read(streamingSettingsProvider.notifier)
                    .set(streaming.copyWith(cellularAllowed: v)),
              ),
              _divider,
              _ActionTile(
                icon: Icons.settings_ethernet,
                title: '网络设置',
                subtitle: network.proxy.isEmpty
                    ? '超时 ${network.timeoutSeconds}s · 直连'
                    : '超时 ${network.timeoutSeconds}s · 代理 ${network.proxy}',
                onTap: () => _showNetworkSettings(context, ref),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.save_alt,
                title: '边听边存',
                subtitle: '播放时缓存音频，断网可续播已缓存段落',
                value: cache.cacheWhileListen,
                onChanged: (v) => ref
                    .read(cacheSettingsProvider.notifier)
                    .set(cache.copyWith(cacheWhileListen: v)),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.cloud_download_outlined,
                title: '自动下载',
                subtitle: '后台离线「我喜欢」的歌曲（最多 50 首）',
                value: cache.autoDownload,
                onChanged: (v) {
                  ref
                      .read(cacheSettingsProvider.notifier)
                      .set(cache.copyWith(autoDownload: v));
                  if (v) unawaited(AutoDownload.run(ref.read));
                },
              ),
              _divider,
              _ActionTile(
                icon: Icons.storage,
                title: '缓存限额',
                subtitle: cache.limit.label,
                onTap: () => _showCacheLimitPicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: Icons.cleaning_services,
                title: '清理播放缓存',
                subtitle: cacheSize.when(
                  data: (bytes) => '当前占用 ${_fmtBytes(bytes)}',
                  loading: () => '统计中…',
                  error: (_, _) => '统计失败',
                ),
                onTap: () => _clearAudioCache(context, ref),
              ),
              _divider,
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
              const _SkinPickerTile(),
              if (skin == AppSkin.liquidGlass) ...[
                _divider,
                _ActionTile(
                  icon: Icons.auto_awesome,
                  title: '液态玻璃效果',
                  subtitle: glassLevel.label,
                  onTap: () => _showGlassLevelPicker(context, ref),
                ),
              ],
              _divider,
              _ActionTile(
                icon: coverStyle.icon,
                title: '唱片形态',
                subtitle: coverStyle.label,
                onTap: () => _showCoverStylePicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: Icons.palette_outlined,
                title: '主题色',
                subtitle: accent.label,
                onTap: () => _showAccentPicker(context, ref),
              ),
              if (skin != AppSkin.albumTint && skin != AppSkin.terminal) ...[
                _divider,
                _ActionTile(
                  icon: Icons.image_outlined,
                  title: '自定义背景',
                  subtitle: bgConfig.path != null ? '已设置' : '未设置',
                  onTap: () => _showBackgroundSettings(context, ref),
                ),
              ],
              _divider,
              _ActionTile(
                icon: Icons.tune,
                title: '控制栏样式',
                subtitle: barStyle.label,
                onTap: () => _showMiniBarStylePicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: Icons.height,
                title: '控制栏高度偏移',
                subtitle: barOffset == 0
                    ? '默认'
                    : '${barOffset.toStringAsFixed(0)}px',
                onTap: () => _showMiniBarOffsetPicker(context, ref),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.view_list_outlined,
                title: '部分设置项图标',
                subtitle: showIcons ? '显示' : '隐藏',
                value: showIcons,
                onChanged: (v) =>
                    ref.read(settingsIconsProvider.notifier).setVisible(v),
              ),
              _divider,
              _ActionTile(
                icon: Icons.text_fields,
                title: '列表触底文案',
                subtitle: endText,
                onTap: () => _showEndTextEditor(context, ref),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.battery_saver_outlined,
                title: '省电模式',
                subtitle: powerSave ? '已开启：关闭模糊、压缩动画' : '关闭',
                value: powerSave,
                onChanged: (v) =>
                    ref.read(powerSaveProvider.notifier).setEnabled(v),
              ),
            ],
          ),
          // 悬浮歌词仅 Android 提供悬浮窗能力（iOS 无对应 API，入口隐藏）
          _GroupCard(
            title: '系统与账户',
            children: [
              if (Platform.isAndroid) ...[
                _SwitchTile(
                  icon: Icons.picture_in_picture_alt,
                  title: '悬浮歌词',
                  subtitle: floatingLyrics ? '小窗显示当前歌词行' : '关闭',
                  value: floatingLyrics,
                  onChanged: (v) => _toggleFloatingLyrics(context, ref, v),
                ),
                _divider,
              ],
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
              _divider,
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
                iconColor: AppTheme.heartRed,
                titleColor: AppTheme.heartRed,
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

  void _toast(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
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
