import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/api/server_adapter.dart';
import '../../core/models/models.dart';
import '../auth/auth_controller.dart';
import 'player_controller.dart';

/// audio_service 后台播放处理器：
/// - 包装全局 AudioPlayer，向系统媒体通知栏广播播放状态/歌曲元数据
/// - 承接耳机线控 / 通知栏 / 锁屏的播放控制
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
    // 当前歌曲 → 通知栏元数据（切歌即刷新）
    _ref.listen<Song?>(currentSongProvider, (_, song) => _syncMediaItem(song));
    _syncMediaItem(_ref.read(currentSongProvider));
  }

  final Ref _ref;
  late final AudioPlayer _player;

  // ---------- 系统控制回调 → 全局播放器 ----------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() =>
      _ref.read(playerActionsProvider).playNext();

  @override
  Future<void> skipToPrevious() =>
      _ref.read(playerActionsProvider).playPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  // ---------- 状态广播 ----------

  void _syncMediaItem(Song? song) {
    if (song == null) {
      mediaItem.add(null);
      return;
    }
    final adapter = _ref.read(serverAdapterProvider);
    final ImageSource? coverSrc = adapter?.coverImage(song.albumId);
    mediaItem.add(MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: (song.duration * 1000).round()),
      artUri: coverSrc != null ? Uri.parse(coverSrc.url) : null,
    ));
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
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
    ));
  }
}

/// 全局唯一的后台播放处理器（main 中 AudioService.init 消费）
final audioHandlerProvider =
    Provider<AppAudioHandler>((ref) => AppAudioHandler(ref));
