part of 'player_actions.dart';

/// 交叉淡入淡出（P1-Crossfade，0–10s，音量自动化近似，just_audio 无原生 crossfade）。
/// 语义：crossfadeSeconds 即实际淡化时长，100ms 步进派生步数；
/// 下一首预判与 playNext 共用 nextSongProvider，保证淡入的歌就是预判的歌。
/// 淡化期间音量由本文件托管（play() 内的 _applyReplayGain 在 _fading 时跳过），
/// 每步验证播放代数：用户手动切歌/暂停时立即放弃并恢复目标音量
mixin PlayerCrossfade on PlayerActionsBase, PlayerSourceResolver {
  /// 进度流驱动的触发判定：剩余时长进入淡化窗口且有真实下一首才启动
  void _tickCrossfade(Duration pos) {
    if (_fading || _disposed) return;
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
    final startGen = _playGeneration;
    Future<void> restoreVolume() async {
      try {
        final song = _ref.read(currentSongProvider);
        await _player.setVolume(
          song != null ? _replayGainTargetVolume(song) : 1.0,
        );
      } catch (_) {}
    }

    try {
      final startVolume = _player.volume;
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: stepMs));
        // 途中暂停或用户手动切歌（代数变化）：立即放弃，音量交还目标值
        if (!_player.playing || startGen != _playGeneration) {
          await restoreVolume();
          return;
        }
        await _player.setVolume(startVolume * (1 - i / steps));
      }
      if (startGen != _playGeneration || !_player.playing) {
        await restoreVolume();
        return;
      }
      // 淡出已到 0：play() 内的 _applyReplayGain 因 _fading 跳过，
      // 音量保持 0 从头淡入（否则新曲起播瞬间会以满音量爆音）
      await _player.setVolume(0);
      // 认领本次 play() 创建的代数：若装源期间用户手动切歌产生了更新代数，
      // play() 返回值就是过期代数——放弃淡化并恢复音量
      final fadeGen = await play(next);
      final target = _replayGainTargetVolume(next);
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: stepMs));
        if (fadeGen != _playGeneration) {
          await restoreVolume();
          return;
        }
        await _player.setVolume(target * i / steps);
      }
      if (fadeGen != _playGeneration) {
        await restoreVolume();
        return;
      }
      await _player.setVolume(target);
    } catch (_) {
      await restoreVolume();
    } finally {
      _fading = false;
    }
  }
}
