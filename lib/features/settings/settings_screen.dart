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
    final network = ref.watch(networkSettingsProvider);
    final cache = ref.watch(cacheSettingsProvider);
    final cacheSize = ref.watch(audioCacheSizeProvider);
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
              if (skin != AppSkin.highContrast) ...[
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

/// 缓存限额选择（附录·四）：2GB / 5GB / 10GB / 无限制
Future<void> _showCacheLimitPicker(BuildContext context, WidgetRef ref) {
  final settings = ref.read(cacheSettingsProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '缓存限额',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final l in CacheLimit.values)
          ListTile(
            leading: l == settings.limit
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              l.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref
                  .read(cacheSettingsProvider.notifier)
                  .set(settings.copyWith(limit: l));
              Navigator.of(context).pop();
            },
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '超出限额时从最旧的缓存文件开始清理',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// 清理播放缓存（边听边存产生的音频缓存，不影响离线下载文件）
Future<void> _clearAudioCache(BuildContext context, WidgetRef ref) async {
  final confirmed = await glassDialog<bool>(
    context,
    title: '清理播放缓存',
    content: const Text(
      '将删除边听边存产生的音频缓存文件，离线下载不受影响。确定清理？',
      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('清理'),
      ),
    ],
  );
  if (confirmed != true) return;
  await AudioCache.clear();
  ref.invalidate(audioCacheSizeProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('播放缓存已清理'), duration: Duration(seconds: 2)),
  );
}

/// 字节数人性化显示
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

/// 在线音质分档选择（附录·四）：Wi-Fi 与移动网络独立配置
Future<void> _showQualityPicker(
  BuildContext context,
  WidgetRef ref, {
  required bool cellular,
}) {
  final settings = ref.read(streamingSettingsProvider);
  final current = cellular ? settings.cellularQuality : settings.wifiQuality;
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            cellular ? '在线音质（移动网络）' : '在线音质（Wi-Fi）',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final q in StreamQuality.values)
          ListTile(
            leading: q == current
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              q.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              final controller = ref.read(streamingSettingsProvider.notifier);
              controller.set(
                cellular
                    ? settings.copyWith(cellularQuality: q)
                    : settings.copyWith(wifiQuality: q),
              );
              Navigator.of(context).pop();
            },
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '无损播放原始文件；其余档位由服务端转码（需后端支持），'
            '可显著降低流量与加载等待',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// 转码格式选择（附录·四）：MP3 兼容性最好，OPUS 同码率下音质更佳
Future<void> _showTranscodeFormatPicker(BuildContext context, WidgetRef ref) {
  final settings = ref.read(streamingSettingsProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '转码格式',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final f in TranscodeFormat.values)
          ListTile(
            leading: f == settings.transcodeFormat
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              f.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref
                  .read(streamingSettingsProvider.notifier)
                  .set(settings.copyWith(transcodeFormat: f));
              Navigator.of(context).pop();
            },
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '仅在选择非无损音质档位时生效；OPUS 需要服务端转码器支持',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// 网络设置（附录·一）：超时 / 代理 / 证书校验 / hosts 映射。
/// 表单做成 StatefulWidget 自持控制器，弹窗退场动画期间不会撞 dispose
class _NetworkSettingsForm extends StatefulWidget {
  const _NetworkSettingsForm({required this.initial, required this.onSave});

  final NetworkSettings initial;
  final void Function(NetworkSettings) onSave;

  @override
  State<_NetworkSettingsForm> createState() => _NetworkSettingsFormState();
}

class _NetworkSettingsFormState extends State<_NetworkSettingsForm> {
  late final TextEditingController _proxy = TextEditingController(
    text: widget.initial.proxy,
  );
  late final TextEditingController _hosts = TextEditingController(
    text: widget.initial.hostOverrides,
  );
  late bool _verify = widget.initial.verifyCertificates;
  late int _timeout = widget.initial.timeoutSeconds;

  @override
  void dispose() {
    _proxy.dispose();
    _hosts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '网络设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          '请求超时（$_timeout 秒）',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Slider(
          value: _timeout.toDouble(),
          min: 5,
          max: 60,
          divisions: 11,
          label: '$_timeout',
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) => setState(() => _timeout = v.round()),
        ),
        TextField(
          controller: _proxy,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            labelText: '代理地址（如 127.0.0.1:7890）',
            labelStyle: TextStyle(color: Colors.white38, fontSize: 13),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'HTTPS 证书校验',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            '自签名内网服务器可关闭',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          value: _verify,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) => setState(() => _verify = v),
        ),
        TextField(
          controller: _hosts,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'hosts 映射（域名=IP，分号分隔）',
            labelStyle: TextStyle(color: Colors.white38, fontSize: 13),
            border: OutlineInputBorder(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '仅 HTTP 直连完整生效；HTTPS 握手 SNI 使用映射 IP，'
            '需配合关闭证书校验',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  widget.onSave(
                    NetworkSettings(
                      timeoutSeconds: _timeout,
                      proxy: _proxy.text.trim(),
                      verifyCertificates: _verify,
                      hostOverrides: _hosts.text.trim(),
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _showNetworkSettings(BuildContext context, WidgetRef ref) {
  final initial = ref.read(networkSettingsProvider);
  return glassBottomSheet<void>(
    context,
    _NetworkSettingsForm(
      initial: initial,
      onSave: (s) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('网络设置已更新，切换服务器后生效')));
        ref.read(networkSettingsProvider.notifier).set(s);
      },
    ),
  );
}

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
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
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
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
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

/// 悬浮歌词开关：开启前校验悬浮窗权限，未授予则跳系统设置页
Future<void> _toggleFloatingLyrics(
  BuildContext context,
  WidgetRef ref,
  bool v,
) async {
  if (!v) {
    await ref.read(floatingLyricsProvider.notifier).setEnabled(false);
    return;
  }
  if (await FloatingLyrics.hasPermission()) {
    await ref.read(floatingLyricsProvider.notifier).setEnabled(true);
    return;
  }
  // 先记录用户意图；Android 设置页返回后由 permissionChanged 自动启用或回退。
  await ref.read(floatingLyricsProvider.notifier).setEnabled(true);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('授权后将自动启用悬浮歌词')));
  }
  await FloatingLyrics.requestPermission();
}

/// 主题选择：内联预览卡网格（P1 主题系统化）。
/// 不用玻璃底部弹层——选择后设置页立即切换主题，展开状态用于对比预览。
class _SkinPickerTile extends ConsumerStatefulWidget {
  const _SkinPickerTile();

  @override
  ConsumerState<_SkinPickerTile> createState() => _SkinPickerTileState();
}

class _SkinPickerTileState extends ConsumerState<_SkinPickerTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(appSkinProvider);
    return Column(
      children: [
        _ActionTile(
          icon: Icons.style_outlined,
          title: '主题',
          subtitle: _open ? '点击收起预览' : skin.label,
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _SkinPreviewGrid(
              current: skin,
              onSelect: (s) => ref.read(appSkinProvider.notifier).set(s),
            ),
          ),
      ],
    );
  }
}

class _SkinPreviewGrid extends StatelessWidget {
  const _SkinPreviewGrid({required this.current, required this.onSelect});

  final AppSkin current;
  final ValueChanged<AppSkin> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in AppSkin.values)
              SizedBox(
                width: width,
                child: _SkinPreviewCard(
                  skin: s,
                  selected: s == current,
                  accent: accent,
                  onTap: () => onSelect(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 每主题一张迷你预览卡：底色 / 面板色 / 描边 / 发光 / 主题色点，用各主题
/// 自己的 token 绘制，切换后卡片内容即时反映新主题的实际观感。
class _SkinPreviewCard extends StatelessWidget {
  const _SkinPreviewCard({
    required this.skin,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppSkin skin;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SkinTokens.forSkin(skin);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : t.borderHairline,
            width: selected ? 2 : 1,
          ),
          boxShadow: t.glow.a == 0
              ? null
              : [BoxShadow(color: t.glow, blurRadius: 12, spreadRadius: -4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 20,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: t.borderHairline),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              skin.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textDim,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Text(
              skin.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音效面板（Android）：EQ 波段滑杆 + 预设曲线 + 低音/空间近似 + 参数剪贴板导入导出
Future<void> _showEffectsPanel(BuildContext context) {
  String freqLabel(int hz) => hz >= 1000
      ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz'
      : '$hz Hz';

  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final st = ref.watch(audioEffectsProvider);
        final notifier = ref.read(audioEffectsProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '音效',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!Platform.isAndroid)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  '音效仅在 Android 设备上可用',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              )
            else if (st.bands.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  '未获取到设备音效通道，播放一首歌曲后重试',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    const Text('均衡器', style: TextStyle(color: Colors.white)),
                    const Spacer(),
                    Switch(value: st.enabled, onChanged: notifier.setEnabled),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in eqPresets.keys)
                      GestureDetector(
                        onTap: () => notifier.applyPreset(name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final band in st.bands.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          freqLabel(band.$2.centerHz),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          min: band.$2.minMb.toDouble(),
                          max: band.$2.maxMb.toDouble(),
                          divisions: ((band.$2.maxMb - band.$2.minMb) / 50)
                              .round(),
                          value: (st.gains[band.$1] ?? 0)
                              .clamp(band.$2.minMb, band.$2.maxMb)
                              .toDouble(),
                          onChanged: (v) =>
                              notifier.setBand(band.$1, v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${((st.gains[band.$1] ?? 0) / 100).toStringAsFixed(1)} dB',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 68,
                      child: Text(
                        '低音增强',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1000,
                        divisions: 20,
                        value: st.bass.toDouble(),
                        onChanged: (v) => notifier.setBass(v.round()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 68,
                      child: Text(
                        '空间音效',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1000,
                        divisions: 20,
                        value: st.virtualizer.toDouble(),
                        onChanged: (v) => notifier.setVirtualizer(v.round()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: jsonEncode(st.gains)),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('EQ 曲线已复制到剪贴板'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share, size: 16),
                      label: const Text('导出曲线'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () async {
                        final raw = await Clipboard.getData('text/plain');
                        final text = raw?.text;
                        if (text == null || text.isEmpty) return;
                        try {
                          final map = jsonDecode(text) as Map<String, dynamic>;
                          for (final e in map.entries) {
                            final index = int.parse(e.key);
                            if (index >= st.bands.length) continue;
                            await notifier.setBand(
                              index,
                              (e.value as num).round(),
                            );
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('EQ 曲线已导入'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('剪贴板内容不是有效的 EQ 曲线'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('导入曲线'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    ),
  );
}

/// 耳机线控映射（§9.2）：单击/双击/三击 → 播放暂停/切歌/收藏
Future<void> _showHeadsetSheet(BuildContext context) {
  Widget row(
    String label,
    HeadsetAction current,
    void Function(HeadsetAction) onPick,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in HeadsetAction.values)
              GestureDetector(
                onTap: () => onPick(a),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: a == current
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white24,
                    ),
                    color: a == current
                        ? Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.18)
                        : null,
                  ),
                  child: Text(
                    a.label,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final cfg = ref.watch(headsetClicksProvider);
        final notifier = ref.read(headsetClicksProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '耳机线控',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            row('单击', cfg.single, (a) => notifier.set(single: a)),
            row('双击', cfg.doubleTap, (a) => notifier.set(doubleTap: a)),
            row('三击', cfg.triple, (a) => notifier.set(triple: a)),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Text(
                '默认：单击播放/暂停，双击下一首，三击上一首；'
                '长按和音量键由系统控制',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 主题色选择（§8.1）：六个预设色板，选中后立即生效并持久化
Future<void> _showAccentPicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(appAccentProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '主题色',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final a in AppAccent.values)
                GestureDetector(
                  onTap: () {
                    ref.read(appAccentProvider.notifier).setAccent(a);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: a.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: a == current ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: a == current
                        ? const Icon(Icons.check, color: Colors.white, size: 24)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final a in AppAccent.values)
          if (a == current)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                a.label,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
      ],
    ),
  );
}

/// 自定义背景设置（§8.1）：选图 / 清除 + 不透明度与模糊度滑块
Future<void> _showBackgroundSettings(BuildContext context, WidgetRef ref) {
  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final bg = ref.watch(backgroundProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '自定义背景',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1920,
                      maxHeight: 1920,
                      imageQuality: 85,
                    );
                    if (img != null) {
                      await ref
                          .read(backgroundProvider.notifier)
                          .setImage(img.path);
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('选择图片'),
                ),
                if (bg.path != null) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(backgroundProvider.notifier).clearImage(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清除'),
                  ),
                ],
              ],
            ),
            if (bg.path != null) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '不透明度 ${(bg.opacity * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    SliderTheme(
                      data: const SliderThemeData(trackHeight: 2),
                      child: Slider(
                        value: bg.opacity,
                        min: 0.05,
                        max: 1.0,
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: Colors.white24,
                        onChanged: (v) =>
                            ref.read(backgroundProvider.notifier).setOpacity(v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '模糊度 ${bg.blur.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    SliderTheme(
                      data: const SliderThemeData(trackHeight: 2),
                      child: Slider(
                        value: bg.blur,
                        min: 0,
                        max: 30,
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: Colors.white24,
                        onChanged: (v) =>
                            ref.read(backgroundProvider.notifier).setBlur(v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '图片仅保存在本地，不会上传到任何服务器',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 控制栏样式选择（§8.2）：毛玻璃 / 纯色 / 渐变
Future<void> _showMiniBarStylePicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(miniBarStyleProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '控制栏样式',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final style in MiniBarStyle.values)
          ListTile(
            leading: Icon(switch (style) {
              MiniBarStyle.glass => Icons.blur_on_outlined,
              MiniBarStyle.solid => Icons.rectangle_outlined,
              MiniBarStyle.gradient => Icons.gradient_outlined,
            }, color: Colors.white70),
            trailing: style == current
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            title: Text(
              style.label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref.read(miniBarStyleProvider.notifier).setStyle(style);
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

/// 控制栏高度偏移微调（§8.2）：-20 ~ 40px，步进 2
Future<void> _showMiniBarOffsetPicker(BuildContext context, WidgetRef ref) {
  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final offset = ref.watch(miniBarOffsetProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '控制栏高度偏移',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    '${offset.toStringAsFixed(0)}px',
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  SliderTheme(
                    data: const SliderThemeData(trackHeight: 2),
                    child: Slider(
                      value: offset,
                      min: -20,
                      max: 40,
                      divisions: 30,
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Colors.white24,
                      onChanged: (v) =>
                          ref.read(miniBarOffsetProvider.notifier).setOffset(v),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '正值上移、负值下移，用于适配不同底部导航栏高度',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 列表触底文案编辑（§8.4）
Future<void> _showEndTextEditor(BuildContext context, WidgetRef ref) async {
  final current = ref.read(listEndTextProvider);
  final controller = TextEditingController(text: current);
  final result = await glassDialog<String>(
    context,
    title: '列表触底文案',
    content: TextField(
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      decoration: const InputDecoration(
        hintText: '留空恢复默认',
        helperText: '支持占位符：{nTitle} 下一首歌名 / {nArtist} 歌手 / {nAlbum} 专辑',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
  controller.dispose();
  if (result != null) {
    ref.read(listEndTextProvider.notifier).setText(result);
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
          ? Icon(icon, color: Colors.white70)
          : const SizedBox(width: 24),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
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
          ? Icon(icon, color: iconColor ?? Colors.white70)
          : const SizedBox(width: 24),
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
              activeColor: Theme.of(context).colorScheme.primary,
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
