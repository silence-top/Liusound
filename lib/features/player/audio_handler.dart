import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/local/local_library.dart';
import '../../core/models/models.dart';
import '../../core/theme/settings_prefs.dart';
import '../../core/widget/home_widget_sync.dart';
import '../auth/auth_controller.dart';
import 'player_controller.dart';

/// audio_service 后台播放处理器：
/// - 包装全局 AudioPlayer，向系统媒体通知栏广播播放状态/歌曲元数据
/// - 承接耳机线控（单击/双击/三击可映射）/ 通知栏 / 锁屏 / 蓝牙 AVRCP / 车机
/// - 当前队列作为媒体浏览内容暴露（Android Auto 等浏览端可见可播）
class AppAudioHandler extends BaseAudioHandler {
  AppAudioHandler(this._ref) {
    final player = _ref.read(audioPlayerProvider);
    _player = player;
    // 播放事件 → 系统播放状态广播（通知栏进度/按钮态）
    player.playbackEventStream.listen(_broadcastState);
    // 拔出耳机/断开蓝牙 → 自动暂停（避免突然外放）
    AudioSession.instance.then((session) {
      session.becomingNoisyEventStream.listen((_) => _player.pause());
    });
    // 当前歌曲 → 通知栏元数据 + 桌面小部件（切歌即刷新）
    _ref.listen<Song?>(currentSongProvider, (_, song) => _syncMediaItem(song));
    _syncMediaItem(_ref.read(currentSongProvider));
    // 播放态变化 → 桌面小部件播放/暂停图标
    player.playingStream.listen((playing) {
      unawaited(
        HomeWidgetSync.push(
          song: _ref.read(currentSongProvider),
          playing: playing,
        ),
      );
    });
  }

  final Ref _ref;
  late final AudioPlayer _player;
  Timer? _clickTimer;
  int _clickCount = 0;

  // ---------- 系统控制回调 → 全局播放器 ----------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _ref.read(playerActionsProvider).playNext();

  @override
  Future<void> skipToPrevious() =>
      _ref.read(playerActionsProvider).playPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// 线控点击：HEADSETHOOK/PLAY_PAUSE 每次按下都会到达这里，
  /// 按 400ms 窗口聚合出单击/双击/三击，再按用户映射分发
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button != MediaButton.media) return super.click(button);
    _clickCount++;
    _clickTimer?.cancel();
    _clickTimer = Timer(const Duration(milliseconds: 400), () {
      final count = _clickCount;
      _clickCount = 0;
      unawaited(_dispatchClick(count));
    });
  }

  /// Android Auto / 车机浏览：根节点即当前队列（部分能力，完整曲库浏览需
  /// MediaLibraryService 级改造，见待办清单说明）
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId != 'root') return const [];
    return _ref.read(queueProvider).map(_mediaItemFor).toList(growable: false);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    final song = _ref
        .read(queueProvider)
        .where((s) => s.id == mediaItem.id)
        .firstOrNull;
    if (song != null) await _ref.read(playerActionsProvider).play(song);
  }

  Future<void> _dispatchClick(int count) async {
    final cfg = _ref.read(headsetClicksProvider);
    final action = switch (count) {
      2 => cfg.doubleTap,
      3 => cfg.triple,
      _ => cfg.single,
    };
    switch (action) {
      case HeadsetAction.playPause:
        _player.playing ? await pause() : await play();
      case HeadsetAction.next:
        await skipToNext();
      case HeadsetAction.previous:
        await skipToPrevious();
      case HeadsetAction.toggleStar:
        await _toggleStarCurrent();
    }
  }

  Future<void> _toggleStarCurrent() async {
    final song = _ref.read(currentSongProvider);
    if (song == null || localSongPath(song) != null) return;
    final before = song;
    final updated = song.copyWith(starred: !song.starred);
    _ref.read(currentSongProvider.notifier).state = updated;
    _ref.read(queueProvider.notifier).replaceSong(song.id, updated);
    final ok =
        await _ref
            .read(serverAdapterProvider)
            ?.setStar(song.id, updated.starred) ??
        false;
    if (!ok) {
      // 服务端失败回滚乐观更新
      _ref.read(currentSongProvider.notifier).state = before;
      _ref.read(queueProvider.notifier).replaceSong(song.id, before);
    }
  }

  // ---------- 状态广播 ----------

  void _syncMediaItem(Song? song) {
    mediaItem.add(song == null ? null : _mediaItemFor(song));
    unawaited(HomeWidgetSync.push(song: song, playing: _player.playing));
  }

  MediaItem _mediaItemFor(Song song) {
    final adapter = _ref.read(serverAdapterProvider);
    final coverSrc = adapter?.coverImage(song.albumId);
    final localCover = song.localCoverPath;
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: (song.duration * 1000).round()),
      // 本地歌曲用内嵌封面文件；服务器歌曲带鉴权头（蓝牙/车机拉取封面必需）
      artUri: localCover != null
          ? Uri.file(localCover)
          : (coverSrc != null ? Uri.parse(coverSrc.url) : null),
      artHeaders:
          (localCover == null &&
              coverSrc != null &&
              coverSrc.headers.isNotEmpty)
          ? coverSrc.headers
          : null,
      playable: true,
    );
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }
}

/// 全局唯一的后台播放处理器（main 中 AudioService.init 消费）
final audioHandlerProvider = Provider<AppAudioHandler>(
  (ref) => AppAudioHandler(ref),
);
