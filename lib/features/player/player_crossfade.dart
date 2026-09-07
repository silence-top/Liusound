part of 'player_actions.dart';

/// 交叉淡入淡出（P1-Crossfade，0–10s，音量自动化近似，just_audio 无原生 crossfade）。
/// 语义：crossfadeSeconds 即实际淡化时长，100ms 步进派生步数；
/// 下一首预判与 playNext 共用 nextSongProvider，保证淡入的歌就是预判的歌
mixin PlayerCrossfade on PlayerActionsBase, PlayerSourceResolver {
  /// 进度流驱动的触发判定：剩余时长进入淡化窗口且有真实下一首才启动
  void _tickCrossfade(Duration pos) {
    if (_fading) return;
    final seconds = _ref.read(crossfadeSecondsProvider);
    if (seconds <= 0) return;
    final player = _player;
    if (!player.playing) return;
    final duration = player.duration;
    if (duration == null ||
        duration <= Duration(seconds: seconds * 2) ||
        duration - pos > Duration(seconds: seconds)) {
      return;
    }
    final next = _ref.read(nextSongProvider);
    if (next == null) return;
    _runCrossfade(seconds, next);
  }

  Future<void> _runCrossfade(int seconds, Song next) async {
    _fading = true;
    const stepMs = 100;
    final steps = seconds * 1000 ~/ stepMs;
    try {
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
        if (!_player.playing) {
          // 途中被暂停：恢复音量并放弃本次
          try {
            await _player.setVolume(1);
          } catch (_) {}
          return;
        }
        await _player.setVolume(1 - i / steps);
      }
      await play(next);
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
        await _player.setVolume(i / steps);
      }
      await _player.setVolume(1);
    } catch (_) {
      try {
        await _player.setVolume(1);
      } catch (_) {}
    } finally {
      _fading = false;
    }
  }
}
