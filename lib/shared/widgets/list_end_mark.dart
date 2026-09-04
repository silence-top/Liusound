import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/settings_prefs.dart';
import '../../features/player/player_controller.dart';

/// 统一的「列表结束提示」（架构契约 AppListEnd）：文案按当前列表上下文
/// 取下一首，支持 {nTitle}/{nArtist}/{nAlbum} 占位符（§8.4）。
/// 各歌曲列表共用一份实现，上下文取传入列表而非全局播放队列。
class ListEndMark extends ConsumerWidget {
  const ListEndMark({super.key, required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(listEndTextProvider);
    final current = ref.watch(currentSongProvider);
    final index = current == null
        ? -1
        : songs.indexWhere((song) => song.id == current.id);
    final next = index >= 0 && index < songs.length - 1
        ? songs[index + 1]
        : null;
    final text = template
        .replaceAll('{nTitle}', next?.title ?? '？')
        .replaceAll('{nArtist}', next?.artist ?? '？')
        .replaceAll('{nAlbum}', next?.album ?? '？');
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 48),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: AppTheme.textFaintOf(context), fontSize: 14),
        ),
      ),
    );
  }
}
