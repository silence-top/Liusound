part of 'player_actions.dart';

/// 播放状态持久化（P1-Persistence）：对标 1.x——队列前 100 + 当前歌 + 模式 + 进度，
/// 500ms 防抖聚合写回；恢复过程中不回写
mixin PlayerPersistence on PlayerActionsBase {
  void _schedulePersist() {
    if (!_restored) return; // 恢复过程中不回写
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      final payload = <String, dynamic>{
        'queue': _ref
            .read(queueProvider)
            .take(100)
            .map((s) => s.toJson())
            .toList(),
        'currentSong': _ref.read(currentSongProvider)?.toJson(),
        'playMode': _ref.read(playModeProvider).name,
        'speed': _ref.read(playbackSpeedProvider),
        'loopPlayback': _ref.read(loopPlaybackProvider),
        'shuffleOrder': _ref.read(shuffleOrderProvider).order,
        'shufflePos': _ref.read(shuffleOrderProvider).pos,
        'currentTime': _player.position.inMilliseconds / 1000.0,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_playerStateKey, jsonEncode(payload));
    } catch (_) {
      // 持久化失败静默（存储异常不应影响播放）
    }
  }
}
