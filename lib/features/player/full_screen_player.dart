import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../shared/cover_art.dart';
import '../auth/auth_controller.dart';
import 'player_controller.dart';

/// 相似歌曲推荐（按歌曲 id 缓存，对标 1.x getSimilarSongs）
final similarSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, songId) {
  return ref.watch(navidromeClientProvider).getSimilarSongs(songId);
});

const double _lyricItemExtent = 48; // 每行歌词高度（对齐 1.x LYRIC_HEIGHT）

/// 全屏播放器（对标 1.x FullScreenPlayer + QueueModal）：
/// 三 Tab —— 相似推荐 / 播放队列 / 歌词同步。
///
/// 性能红线：外壳只 watch [currentSongProvider]（切歌才重建）；
/// 进度条、播放按钮、模式按钮为独立小组件局部订阅高频流。
class FullScreenPlayer extends ConsumerStatefulWidget {
  const FullScreenPlayer({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends ConsumerState<FullScreenPlayer>
    with TickerProviderStateMixin {
  // 对齐 1.x：默认停留在"歌曲"（队列）Tab
  late final TabController _tab =
      TabController(length: 3, vsync: this, initialIndex: 1);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏：下滑关闭
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  iconSize: 32,
                  onPressed: widget.onClose,
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Text('正在播放', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
            // 大封面
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
              child: AspectRatio(
                aspectRatio: 1,
                child: CoverArt(albumId: song.albumId, size: 600, radius: 16),
              ),
            ),
            // 歌名 / 歌手
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const _ProgressSlider(),
            const _TransportControls(),
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: '推荐'),
                Tab(text: '歌曲'),
                Tab(text: '歌词'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  const _RecommendTab(),
                  const _QueueTab(),
                  _LyricsTab(song: song),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- 进度条（局部订阅 position/duration 流，支持拖动 seek） ----------

class _ProgressSlider extends ConsumerStatefulWidget {
  const _ProgressSlider();

  @override
  ConsumerState<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends ConsumerState<_ProgressSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final value = _dragValue ??
        position.inMilliseconds.toDouble().clamp(0, maxMs <= 0 ? 1 : maxMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(_formatTime(position),
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
          Expanded(
            child: Slider(
              value: value,
              max: maxMs <= 0 ? 1 : maxMs,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                ref
                    .read(playerActionsProvider)
                    .seek(Duration(milliseconds: v.round()));
                setState(() => _dragValue = null);
              },
            ),
          ),
          Text(_formatTime(duration),
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }

  static String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---------- 传输控制（模式 / 上一首 / 播放暂停 / 下一首） ----------

class _TransportControls extends ConsumerWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _ModeButton(),
          IconButton(
            iconSize: 36,
            color: Colors.white,
            icon: const Icon(Icons.skip_previous),
            onPressed: () => ref.read(playerActionsProvider).playPrevious(),
          ),
          const _PlayButton(),
          IconButton(
            iconSize: 36,
            color: Colors.white,
            icon: const Icon(Icons.skip_next),
            onPressed: () => ref.read(playerActionsProvider).playNext(),
          ),
          // 右侧占位保持按钮组居中对称
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// 播放模式按钮（仅订阅 playMode，点击在 顺序→随机→单曲循环 间切换）
class _ModeButton extends ConsumerWidget {
  const _ModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playModeProvider);
    final icon = switch (mode) {
      PlayMode.order => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.repeatOne => Icons.repeat_one,
    };
    return IconButton(
      iconSize: 28,
      color: Colors.white70,
      tooltip: const {
            PlayMode.order: '顺序播放',
            PlayMode.shuffle: '随机播放',
            PlayMode.repeatOne: '单曲循环',
          }[mode] ??
          '',
      icon: Icon(icon),
      onPressed: () => ref.read(playerActionsProvider).cyclePlayMode(),
    );
  }
}

/// 播放/暂停大按钮（仅订阅 isPlaying 布尔流，翻转时才重建）
class _PlayButton extends ConsumerWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    return IconButton(
      iconSize: 64,
      color: Colors.white,
      icon: Icon(isPlaying
          ? Icons.pause_circle_filled
          : Icons.play_circle_fill),
      onPressed: () => ref.read(playerActionsProvider).toggle(),
    );
  }
}

// ---------- Tab 1：相似推荐 ----------

class _RecommendTab extends ConsumerWidget {
  const _RecommendTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final similar = ref.watch(similarSongsProvider(song.id));

    return similar.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: Text('推荐加载失败', style: TextStyle(color: Colors.white38)),
      ),
      data: (songs) {
        if (songs.isEmpty) {
          return const Center(
            child: Text('暂无相似推荐', style: TextStyle(color: Colors.white38)),
          );
        }
        return ListView.builder(
          itemCount: songs.length,
          itemExtent: 64,
          itemBuilder: (_, i) => _SongTile(song: songs[i]),
        );
      },
    );
  }
}

// ---------- Tab 2：播放队列 ----------

class _QueueTab extends ConsumerWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    if (queue.isEmpty) {
      return const Center(
        child: Text('队列为空', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('播放队列 (${queue.length})',
                  style: const TextStyle(fontSize: 13, color: Colors.white38)),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(playerActionsProvider).clearQueue(),
                child: const Text('清空', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: queue.length,
            itemExtent: 64,
            itemBuilder: (_, i) => _QueueTile(song: queue[i]),
          ),
        ),
      ],
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentSongProvider);
    final isCurrent = current?.id == song.id;
    return ListTile(
      dense: true,
      leading: CoverArt(albumId: song.albumId, size: 44, radius: 8),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isCurrent ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isCurrent ? FontWeight.bold : null,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: isCurrent
          ? Icon(Icons.graphic_eq,
              size: 20, color: Theme.of(context).colorScheme.primary)
          : IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white38),
              onPressed: () =>
                  ref.read(playerActionsProvider).removeFromQueue(song.id),
            ),
      onTap: () => ref.read(playerActionsProvider).play(song),
    );
  }
}

/// 通用歌曲列表项（推荐 Tab 复用）
class _SongTile extends ConsumerWidget {
  const _SongTile({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      leading: CoverArt(albumId: song.albumId, size: 44, radius: 8),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      onTap: () => ref.read(playerActionsProvider).play(song),
    );
  }
}

// ---------- Tab 3：歌词同步（滚动同步 + 偏移微调，按歌曲持久化） ----------

class _LyricsTab extends ConsumerStatefulWidget {
  const _LyricsTab({required this.song});

  final Song song;

  @override
  ConsumerState<_LyricsTab> createState() => _LyricsTabState();
}

class _LyricsTabState extends ConsumerState<_LyricsTab> {
  List<LyricLine> _lyrics = const [];
  double _offset = 0;
  bool _manualScrolling = false;
  int _lastIndex = -2;
  Timer? _manualScrollTimer;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _loadOffset();
  }

  @override
  void didUpdateWidget(_LyricsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.id != oldWidget.song.id) {
      _parseLyrics();
      _offset = 0;
      _lastIndex = -2;
      _loadOffset();
    }
  }

  @override
  void dispose() {
    _manualScrollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _parseLyrics() =>
      setState(() => _lyrics = parseLyrics(widget.song.lyrics));

  Future<void> _loadOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble('$lyricOffsetKeyPrefix${widget.song.id}') ?? 0;
    if (mounted) setState(() => _offset = v);
  }

  /// 保存偏移（0 表示清除该歌曲的偏移记录，对标 1.x handleSaveLyricOffset）
  Future<void> _persistOffset(double v) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$lyricOffsetKeyPrefix${widget.song.id}';
    if (v == 0) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, v);
    }
  }

  void _adjustOffset(double delta) =>
      setState(() => _offset = double.parse((_offset + delta).toStringAsFixed(2)));

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    // 播放进度 → 当前行计算 + 自动滚动（仅本 Tab 订阅高频进度流）
    ref.listen(positionProvider, (_, snapshot) {
      if (_lyrics.isEmpty) return;
      final position = snapshot.valueOrNull ?? Duration.zero;
      final idx = findLyricIndex(
          _lyrics, position.inMilliseconds / 1000.0 + _offset);
      if (idx == _lastIndex) return;
      _lastIndex = idx;
      setState(() {}); // 仅当前行变化时重绘歌词列表
      if (idx >= 0 && _controller.hasClients && !_manualScrolling) {
        final target = (idx * _lyricItemExtent -
                _controller.position.viewportDimension / 2 +
                _lyricItemExtent / 2)
            .clamp(0.0, _controller.position.maxScrollExtent);
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    if (_lyrics.isEmpty) {
      return const Center(
        child: Text('暂无歌词', style: TextStyle(color: Colors.white38)),
      );
    }

    return Column(
      children: [
        // 歌词主体（用户手动滚动后暂停自动跟随 2.5s）
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              if (n.direction != ScrollDirection.idle) {
                _manualScrolling = true;
                _manualScrollTimer?.cancel();
                _manualScrollTimer = Timer(
                    const Duration(milliseconds: 2500),
                    () => _manualScrolling = false);
              }
              return false;
            },
            child: ListView.builder(
              controller: _controller,
              itemExtent: _lyricItemExtent,
              padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
              itemCount: _lyrics.length,
              itemBuilder: (_, i) {
                final isCurrent = i == _lastIndex;
                return Center(
                  child: Text(
                    _lyrics[i].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isCurrent ? 18 : 15,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? primary : Colors.white54,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // 偏移微调工具栏（±0.05s，保存后按歌曲持久化）
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('偏移 ${_offset.toStringAsFixed(2)}s',
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 18),
                tooltip: '歌词延后 0.05s',
                onPressed: () => _adjustOffset(-0.05),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                tooltip: '歌词提前 0.05s',
                onPressed: () => _adjustOffset(0.05),
              ),
              TextButton(
                onPressed: () => _persistOffset(_offset),
                child: const Text('保存', style: TextStyle(fontSize: 13)),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _offset = 0);
                  _persistOffset(0);
                },
                child: const Text('重置', style: TextStyle(fontSize: 13)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                tooltip: '复制歌词',
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: _lyrics.map((l) => l.text).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('歌词已复制'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
