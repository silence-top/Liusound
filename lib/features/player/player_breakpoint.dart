part of 'player_actions.dart';

/// 切歌前同步取得完整旧源快照；异步存储期间不再读 UI 歌曲或播放器。
class _BreakpointSnapshot {
  const _BreakpointSnapshot(this.playback, this.duration, this.position);

  final LoadedPlayback playback;
  final Duration duration;
  final Duration position;
}

/// 长音频断点（>10min），按服务器和歌曲隔离。
mixin PlayerBreakpoint on PlayerActionsBase {
  _BreakpointSnapshot? _captureLongTrackBreakpoint() {
    // 切服监听触发时 activeServerId 已变，但仍须保存旧源自己的归属。
    final loaded = _ref.read(loadedPlaybackProvider);
    if (loaded == null || !loaded.ownsPlayer(_player)) return null;
    final duration = loaded.effectiveDuration(_player);
    if (duration == null || duration <= PlayerActionsBase._longTrack) {
      return null;
    }
    return _BreakpointSnapshot(loaded, duration, _player.position);
  }

  Future<void> _saveLongTrackBreakpoint(_BreakpointSnapshot? snapshot) async {
    if (snapshot == null) return;
    try {
      final key = PlayerActionsBase._breakpointKey(
        snapshot.playback.serverId,
        snapshot.playback.song.id,
      );
      final prefs = await SharedPreferences.getInstance();
      if (snapshot.position < const Duration(seconds: 30) ||
          snapshot.position >= snapshot.duration) {
        // 播完/回到开头不保留更早的断点。
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, snapshot.position.inMilliseconds);
      }
    } catch (_) {
      // 存储异常静默（断点只是增强能力）
    }
  }

  /// 装源后、起播前续播；prefs 等待后重新核对会话/代数/用户 seek。
  Future<void> _resumeLongTrack(LoadedPlayback loaded) async {
    try {
      final seekGen = _seekGeneration;
      if (!_isCurrentPlayback(loaded)) return;
      final duration = loaded.effectiveDuration(_player);
      if (duration == null || duration <= PlayerActionsBase._longTrack) return;
      if (_player.position > Duration.zero) return;
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentPlayback(loaded) || seekGen != _seekGeneration) return;
      if (_player.position > Duration.zero) return;
      final saved = prefs.getInt(
        PlayerActionsBase._breakpointKey(loaded.serverId, loaded.song.id),
      );
      final latestDuration = loaded.effectiveDuration(_player);
      if (saved == null ||
          saved < 60000 ||
          latestDuration == null ||
          latestDuration <= PlayerActionsBase._longTrack ||
          saved >= latestDuration.inMilliseconds) {
        return;
      }
      await _player.seek(Duration(milliseconds: saved));
      if (!_isCurrentPlayback(loaded) || seekGen != _seekGeneration) return;
      _ref.read(resumeNoticeProvider.notifier).state =
          '已从上次进度继续：${loaded.song.title}';
    } catch (_) {}
  }
}
