part of 'player_actions.dart';

/// 冷启动恢复（P0-PLAYER-01 的 RESTORING 阶段）：恢复持久化的
/// 队列/当前歌/模式/进度。对齐 1.x：恢复的歌曲不自动播放，由用户点击继续
mixin PlayerRestore on PlayerActionsBase {
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ref.read(autoPlayProvider.notifier).state =
          prefs.getBool('auto_play') ?? false;
      final raw = prefs.getString(_playerStateKey);
      if (raw != null && raw.isNotEmpty) {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        final queue = (saved['queue'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Song.fromJson)
            .toList();
        if (queue.isNotEmpty) {
          _ref.read(queueProvider.notifier).replaceAll(queue);
          final songJson = saved['currentSong'] as Map<String, dynamic>?;
          // 仅当当前歌曲仍在队列中才恢复（对齐 1.x）
          if (songJson != null) {
            final song = Song.fromJson(songJson);
            if (queue.any((s) => s.id == song.id)) {
              _ref.read(currentSongProvider.notifier).state = song;
            }
          }
          final savedMode = saved['playMode'] as String?;
          _ref.read(playModeProvider.notifier).state = PlayMode.values
              .firstWhere(
                (m) => m.name == savedMode,
                orElse: () => PlayMode.order,
              );
          final savedSpeed = (saved['speed'] as num?)?.toDouble() ?? 1.0;
          if (savedSpeed > 0) {
            _ref.read(playbackSpeedProvider.notifier).state = savedSpeed;
          }
          _ref.read(loopPlaybackProvider.notifier).state =
              saved['loopPlayback'] as bool? ?? true;
        }
        _resumePositionMs =
            (((saved['currentTime'] as num?)?.toDouble() ?? 0) * 1000).round();
      }
    } catch (_) {
      // 损坏的持久化数据按无状态处理（空队列降级），由 _initialize 完成 READY
    }
  }
}
