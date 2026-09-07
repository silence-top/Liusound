part of 'player_actions.dart';

/// 长音频断点（P1-Breakpoint）：>10min 的曲目按曲记进度，切歌/拖动时保存，
/// 开播时命中断点自动续播（有声书/长录音场景）
mixin PlayerBreakpoint on PlayerActionsBase {
  /// 切歌前：长音频（>10min）把当前进度按曲持久化
  Future<void> _saveLongTrackBreakpoint() async {
    try {
      final song = _ref.read(currentSongProvider);
      final dur = _player.duration;
      if (song == null || dur == null || dur < PlayerActionsBase._longTrack) {
        return;
      }
      final pos = _player.position;
      if (pos < const Duration(seconds: 30)) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        PlayerActionsBase._breakpointKey(song.id),
        pos.inMilliseconds,
      );
    } catch (_) {
      // 存储异常静默（断点只是增强能力）
    }
  }

  /// 播放开始后：长音频命中断点则跳过去并给出提示
  Future<void> _resumeLongTrack(Song song) async {
    try {
      final dur = _player.duration;
      if (dur == null || dur < PlayerActionsBase._longTrack) return;
      if (_player.position > Duration.zero) return; // 已在续播（冷启动恢复）
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(PlayerActionsBase._breakpointKey(song.id));
      if (saved == null || saved < 60000) return;
      await _player.seek(Duration(milliseconds: saved));
      _ref.read(resumeNoticeProvider.notifier).state = '已从上次进度继续：${song.title}';
    } catch (_) {}
  }
}
