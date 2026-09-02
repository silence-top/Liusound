import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';
import '../player/player_controller.dart';

/// 设置页（对标 1.x SettingsScreen：服务器信息 / 缓存管理 / 登出）
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器'),
            subtitle: Text(session?.serverUrl ?? '-'),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('用户'),
            subtitle: Text(session?.username ?? '-'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.format_line_spacing),
            title: const Text('清理歌词偏移缓存'),
            subtitle: const Text('删除所有歌曲保存的歌词时间偏移'),
            onTap: () => _clearLyricOffsets(context),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('清除图片缓存'),
            subtitle: const Text('清理磁盘上的封面图片缓存'),
            onTap: () => _clearImageCache(context),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            subtitle: Text('2.0.0+1 (Flutter)'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('退出登录',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('将清除本地会话与播放状态，确定退出？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
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
