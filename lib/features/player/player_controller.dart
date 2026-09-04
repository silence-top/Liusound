import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/server_adapter.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/download/auto_download.dart';
import '../../core/download/download_service.dart';
import '../../core/local/local_library.dart';
import '../../core/models/models.dart';
import '../../core/settings/streaming_prefs.dart';
import '../auth/auth_controller.dart';

/// 全局唯一 AudioPlayer（App 生命周期持有，页面切换不销毁）
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// 当前歌曲 —— 仅切歌时变化，依赖它的组件才重建
final currentSongProvider = StateProvider<Song?>((ref) => null);

/// 播放队列
class QueueNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() => const [];

  void add(List<Song> songs) => state = [...state, ...songs];

  void replaceAll(List<Song> songs) => state = songs;

  void clear() => state = const [];

  void remove(String songId) =>
      state = state.where((s) => s.id != songId).toList();

  /// 原地更新某首歌（收藏乐观更新等），id 不存在时忽略
  void replaceSong(String songId, Song song) =>
      state = [for (final s in state) s.id == songId ? song : s];

  /// 拖动排序（onReorderItem 语义：newIndex 已完成移除位修正，直接插入）
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex < 0 || newIndex > state.length) return;
    final queue = [...state];
    final song = queue.removeAt(oldIndex);
    queue.insert(newIndex.clamp(0, queue.length), song);
    state = queue;
  }

  /// 下一首播放：插到当前曲目之后（去重）；无当前曲目则插到队首
  void insertAfterCurrent(List<Song> songs) {
    final current = ref.read(currentSongProvider);
    final queue = [...state]
      ..removeWhere((s) => songs.any((n) => n.id == s.id));
    final anchor = current == null
        ? -1
        : queue.indexWhere((s) => s.id == current.id);
    queue.insertAll(anchor < 0 ? 0 : anchor + 1, songs);
    state = queue;
  }
}

final queueProvider = NotifierProvider<QueueNotifier, List<Song>>(
  QueueNotifier.new,
);

/// 下一首预判（触底文案 {nTitle} 占位符用）：与交叉淡化的下一首逻辑一致，
/// 单曲循环返回 null（下一首仍是当前曲）、随机取其余一首、顺序取下一条
final nextSongProvider = Provider<Song?>((ref) {
  final queue = ref.watch(queueProvider);
  final current = ref.watch(currentSongProvider);
  if (current == null || queue.isEmpty) return null;
  switch (ref.watch(playModeProvider)) {
    case PlayMode.repeatOne:
      return null;
    case PlayMode.shuffle:
      final others = queue.where((s) => s.id != current.id).toList();
      return others.isEmpty ? null : others.first;
    case PlayMode.order:
      final index = queue.indexWhere((s) => s.id == current.id);
      if (index >= 0 && index < queue.length - 1) return queue[index + 1];
      return ref.watch(loopPlaybackProvider) ? queue.first : null;
  }
});

/// 播放模式
enum PlayMode { order, shuffle, repeatOne }

final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.order);

/// 播放速度（0.5-3.0，歌曲操作菜单调整，随播放状态持久化）
final playbackSpeedProvider = StateProvider<double>((ref) => 1.0);

/// 循环播放（队列播完回首）；关闭时播完队列即停止（设置页开关）
final loopPlaybackProvider = StateProvider<bool>((ref) => true);

/// 启动后自动播放（恢复上次队列与进度并直接播放）
final autoPlayProvider = StateProvider<bool>((ref) => false);

/// 交叉淡入淡出时长（秒，0=关闭，上限 10；持久化）
class CrossfadeSecondsNotifier extends Notifier<int> {
  static const _key = 'crossfade_seconds';

  @override
  int build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getInt(_key) ?? 0;
      if (v != state) state = v;
    });
    return 0;
  }

  void set(int seconds) {
    state = seconds.clamp(0, 10);
    SharedPreferences.getInstance().then((p) => p.setInt(_key, state));
  }
}

final crossfadeSecondsProvider =
    NotifierProvider<CrossfadeSecondsNotifier, int>(
      CrossfadeSecondsNotifier.new,
    );

/// 点击歌曲后自动打开全屏播放页（持久化，默认开）
class AutoOpenPlayerNotifier extends Notifier<bool> {
  static const _key = 'auto_open_player';

  @override
  bool build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_key) ?? true;
      if (v != state) state = v;
    });
    return true;
  }

  void set(bool v) {
    state = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_key, v));
  }
}

final autoOpenPlayerProvider = NotifierProvider<AutoOpenPlayerNotifier, bool>(
  AutoOpenPlayerNotifier.new,
);

/// 续播提示（长音频断点命中时由常驻 UI 层消费弹出 SnackBar）
final resumeNoticeProvider = StateProvider<String?>((ref) => null);

/// 定时停止播放（展示剩余倒计时；到点暂停，null 未启用，不持久化）
class SleepTimerNotifier extends Notifier<Duration?> {
  Timer? _timer;
  DateTime? _deadline;

  @override
  Duration? build() {
    ref.onDispose(_stopTimer);
    return null;
  }

  void start(Duration duration) {
    _deadline = DateTime.now().add(duration);
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remain = _deadline!.difference(DateTime.now());
      if (remain <= Duration.zero) {
        cancel();
        ref.read(audioPlayerProvider).pause();
      } else {
        state = remain;
      }
    });
  }

  void cancel() {
    _stopTimer();
    _deadline = null;
    state = null;
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, Duration?>(
  SleepTimerNotifier.new,
);

// ---------- 细粒度流式状态（事件驱动，替代 1.x 的 100ms 轮询） ----------
// 消费端用 ref.watch(...select) 或在最小组件内 watch，
// 首页/搜索页不订阅这些 provider → 播放期间零重建（架构性能红线）

final isPlayingProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(audioPlayerProvider)
      .playerStateStream
      .map((s) => s.playing)
      .distinct();
});

/// 播放进度（just_audio positionStream 内部节流 ~200ms，暂停时无事件）
final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioPlayerProvider).positionStream,
);

final durationProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(audioPlayerProvider).durationStream,
);

/// 播放状态持久化 key（对标 1.x STORAGE_KEYS.PLAYER_STATE）
const _playerStateKey = 'player_state';

/// 歌词偏移持久化 key 前缀（对标 1.x LYRIC_OFFSET_PREFIX）
const lyricOffsetKeyPrefix = 'lyricOffset_';

/// 双语歌词开关持久化 key（全局，默认开启）
const bilingualLyricsKey = 'lyrics_bilingual_enabled';

/// 播放控制动作集合（切歌 / 模式 / 队列 / 持久化 / 恢复）
class PlayerActions {
  PlayerActions(this._ref) {
    final player = _ref.read(audioPlayerProvider);
    // 播放结束自动切下一首（repeatOne 由 LoopMode.one 在内核层循环，不会触发 completed）
    player.processingStateStream
        .where((s) => s == ProcessingState.completed)
        .listen((_) => playNext());
    _ref.listen<PlayMode>(playModeProvider, (_, mode) {
      player.setLoopMode(
        mode == PlayMode.repeatOne ? LoopMode.one : LoopMode.off,
      );
      _schedulePersist();
    });
    _ref.listen<double>(playbackSpeedProvider, (_, speed) {
      player.setSpeed(speed);
    });
    _ref.listen<Song?>(currentSongProvider, (_, _) => _schedulePersist());
    _ref.listen<List<Song>>(queueProvider, (_, _) => _schedulePersist());
    player.positionStream.listen(_tickCrossfade);
    _restore();
    maybeAutoDownload(_ref.read);
  }

  final Ref _ref;
  Timer? _persistDebounce;
  bool _restored = false;
  bool _fading = false; // 交叉淡化进行中（防重入）
  int _resumePositionMs = 0; // 冷启动待恢复进度（首播时一次性消费）
  final _random = Random();

  /// 长音频断点阈值（>10min 的曲目单独记进度，有声书/长录音续播用）
  static const _longTrack = Duration(minutes: 10);

  AudioPlayer get _player => _ref.read(audioPlayerProvider);
  ServerAdapter? get _adapter => _ref.read(serverAdapterProvider);

  // ---------- 播放控制 ----------

  /// 播放指定歌曲（替换当前曲目）。
  /// 本地歌曲（id 为 local: 前缀）或已离线下载的歌曲直接走本地文件，
  /// 不消耗流量；否则按当前网络（Wi-Fi / 蜂窝）解析音质档位，
  /// 蜂窝下关闭传输开关则拒播
  Future<void> play(Song song) async {
    final localPath = localSongPath(song) ?? await findDownloadedSong(song);
    if (localPath != null && File(localPath).existsSync()) {
      await _playLocal(song, localPath);
      return;
    }
    final adapter = _adapter;
    if (adapter == null) return;
    final settings = _ref.read(streamingSettingsProvider);
    final quality = await resolveCurrentQuality(settings);
    if (quality == null) return;
    final hint = QualityHint(
      quality: quality,
      format: settings.transcodeFormat,
    );
    await _saveLongTrackBreakpoint();
    _ref.read(currentSongProvider.notifier).state = song;
    try {
      final source = await adapter.resolveStream(song, quality: hint);
      final cache = _ref.read(cacheSettingsProvider);
      if (cache.cacheWhileListen) {
        // 边听边存：走磁盘缓存源，断网可续播已缓存段落
        // LockCachingAudioSource 在 0.10 仍标记 experimental，API 或随版本变动
        await _player.setAudioSource(
          // ignore: experimental_member_use
          LockCachingAudioSource(
            Uri.parse(source.url),
            headers: source.headers.isNotEmpty ? source.headers : null,
          ),
        );
      } else {
        await _player.setUrl(source.url, headers: source.headers);
      }
      await _player.play();
      unawaited(AudioCache.enforceLimit(cache.limit));
      unawaited(_resumeLongTrack(song));
    } catch (_) {
      // 流加载失败不中断 UI（网络抖动场景，状态保持可重试）
    }
  }

  /// 本地文件播放（本地扫描歌曲 / 已离线下载歌曲）
  Future<void> _playLocal(Song song, String path) async {
    await _saveLongTrackBreakpoint();
    _ref.read(currentSongProvider.notifier).state = song;
    try {
      await _player.setAudioSource(AudioSource.file(path));
      await _player.play();
      unawaited(_resumeLongTrack(song));
    } catch (_) {
      // 文件被移动/删除等场景静默，状态保持可重试
    }
  }

  /// 切歌前：长音频（>10min）把当前进度按曲持久化
  Future<void> _saveLongTrackBreakpoint() async {
    try {
      final song = _ref.read(currentSongProvider);
      final dur = _player.duration;
      if (song == null || dur == null || dur < _longTrack) return;
      final pos = _player.position;
      if (pos < const Duration(seconds: 30)) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_breakpointKey(song.id), pos.inMilliseconds);
    } catch (_) {
      // 存储异常静默（断点只是增强能力）
    }
  }

  /// 播放开始后：长音频命中断点则跳过去并给出提示
  Future<void> _resumeLongTrack(Song song) async {
    try {
      final dur = _player.duration;
      if (dur == null || dur < _longTrack) return;
      if (_player.position > Duration.zero) return; // 已在续播（冷启动恢复）
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_breakpointKey(song.id));
      if (saved == null || saved < 60000) return;
      await _player.seek(Duration(milliseconds: saved));
      _ref.read(resumeNoticeProvider.notifier).state = '已从上次进度继续：${song.title}';
    } catch (_) {}
  }

  static String _breakpointKey(String songId) => 'breakpoint_$songId';

  /// 播放/暂停切换；冷启动恢复后的首播会先加载流并跳到上次进度
  Future<void> toggle() async {
    final player = _player;
    if (player.playing) {
      await player.pause();
      return;
    }
    if (_resumePositionMs > 0 &&
        player.processingState == ProcessingState.idle) {
      final song = _ref.read(currentSongProvider);
      if (song != null && _adapter != null) {
        final resumeMs = _resumePositionMs;
        _resumePositionMs = 0;
        await play(song);
        try {
          if (resumeMs > 0) {
            await player.seek(Duration(milliseconds: resumeMs));
          }
        } catch (_) {
          // 流加载失败时 seek 会抛错，静默保持可重试
        }
        return;
      }
    }
    await player.play();
  }

  /// 暂停（定时停止到点时调用）
  Future<void> pause() => _player.pause();

  /// 下一首（order：尾部循环回首；shuffle：排除当前随机；repeatOne：重播当前）
  Future<void> playNext() async {
    final queue = _ref.read(queueProvider);
    final current = _ref.read(currentSongProvider);
    if (current == null || queue.isEmpty) return;
    final mode = _ref.read(playModeProvider);
    if (mode == PlayMode.repeatOne) {
      await _restartCurrent();
      return;
    }
    if (mode == PlayMode.shuffle) {
      final others = queue.where((s) => s.id != current.id).toList();
      if (others.isNotEmpty) {
        await play(others[_random.nextInt(others.length)]);
      }
      return;
    }
    final index = queue.indexWhere((s) => s.id == current.id);
    if (index >= 0 && index < queue.length - 1) {
      await play(queue[index + 1]);
    } else if (_ref.read(loopPlaybackProvider)) {
      await play(queue.first);
    } else {
      // 循环播放关闭：播完队列后停止并回到开头
      await _player.seek(Duration.zero);
      await _player.pause();
    }
  }

  /// 上一首（order：首曲不动；shuffle：随机；repeatOne：重播当前）
  Future<void> playPrevious() async {
    final queue = _ref.read(queueProvider);
    final current = _ref.read(currentSongProvider);
    if (current == null || queue.isEmpty) return;
    final mode = _ref.read(playModeProvider);
    if (mode == PlayMode.repeatOne) {
      await _restartCurrent();
      return;
    }
    if (mode == PlayMode.shuffle) {
      final others = queue.where((s) => s.id != current.id).toList();
      if (others.isNotEmpty) {
        await play(others[_random.nextInt(others.length)]);
      }
      return;
    }
    final index = queue.indexWhere((s) => s.id == current.id);
    if (index > 0) {
      await play(queue[index - 1]);
    }
  }

  /// 单曲循环重播（对齐 1.x：seekTo(0) 后继续播放）
  Future<void> _restartCurrent() async {
    await _player.seek(Duration.zero);
    if (!_player.playing) {
      await _player.play();
    }
  }

  /// 切换播放模式：顺序 → 随机 → 单曲循环
  void cyclePlayMode() {
    final mode = _ref.read(playModeProvider);
    _ref.read(playModeProvider.notifier).state =
        PlayMode.values[(mode.index + 1) % PlayMode.values.length];
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    // 长音频：拖动进度也算有效断点
    try {
      final song = _ref.read(currentSongProvider);
      final dur = _player.duration;
      if (song == null || dur == null || dur < _longTrack) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_breakpointKey(song.id), position.inMilliseconds);
    } catch (_) {}
  }

  // ---------- 交叉淡入淡出（0–10s，音量自动化近似，just_audio 无原生 crossfade） ----------

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
    final next = _peekNextForCrossfade();
    if (next == null) return;
    _runCrossfade(seconds, next);
  }

  /// 交叉淡化的下一首预判（单曲循环/无后续不淡化，让其自然播完/循环）
  Song? _peekNextForCrossfade() {
    final queue = _ref.read(queueProvider);
    final current = _ref.read(currentSongProvider);
    if (current == null || queue.isEmpty) return null;
    switch (_ref.read(playModeProvider)) {
      case PlayMode.repeatOne:
        return null;
      case PlayMode.shuffle:
        final others = queue.where((s) => s.id != current.id).toList();
        return others.isEmpty ? null : others.first;
      case PlayMode.order:
        final index = queue.indexWhere((s) => s.id == current.id);
        if (index >= 0 && index < queue.length - 1) return queue[index + 1];
        return _ref.read(loopPlaybackProvider) ? queue.first : null;
    }
  }

  Future<void> _runCrossfade(int seconds, Song next) async {
    _fading = true;
    const steps = 24;
    final stepMs = seconds * 1000 ~/ steps;
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

  // ---------- 队列管理 ----------

  void addToQueue(List<Song> songs) =>
      _ref.read(queueProvider.notifier).add(songs);

  /// 下一首播放：插到当前曲目之后
  void playNextInQueue(List<Song> songs) =>
      _ref.read(queueProvider.notifier).insertAfterCurrent(songs);

  void replaceQueue(List<Song> songs) =>
      _ref.read(queueProvider.notifier).replaceAll(songs);

  void removeFromQueue(String songId) =>
      _ref.read(queueProvider.notifier).remove(songId);

  /// 拖动排序（队列弹窗）
  void reorderQueue(int oldIndex, int newIndex) =>
      _ref.read(queueProvider.notifier).reorder(oldIndex, newIndex);

  void clearQueue() => _ref.read(queueProvider.notifier).clear();

  // ---------- 播放状态持久化（对标 1.x：队列前 100 + 当前歌 + 模式 + 进度） ----------

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
        'currentTime': _player.position.inMilliseconds / 1000.0,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_playerStateKey, jsonEncode(payload));
    } catch (_) {
      // 持久化失败静默（存储异常不应影响播放）
    }
  }

  /// 冷启动恢复持久化的播放状态（队列/当前歌/模式/进度）。
  /// 对齐 1.x：恢复的歌曲不自动播放，由用户点击继续。
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

        // 启动后自动播放：直接播放恢复的歌曲并跳到上次进度
        if (_ref.read(autoPlayProvider.notifier).state) {
          final song = _ref.read(currentSongProvider);
          if (song != null && _adapter != null) {
            final resumeMs = _resumePositionMs;
            _resumePositionMs = 0;
            await play(song);
            if (resumeMs > 0) {
              try {
                await _player.seek(Duration(milliseconds: resumeMs));
              } catch (_) {
                // seek 失败静默
              }
            }
          }
        }
      }
    } catch (_) {
      // 损坏的持久化数据按无状态处理
    } finally {
      _restored = true;
    }
  }

  /// 登出等场景：清空播放器与持久化状态（对齐 1.x 清 PLAYER_STATE）
  Future<void> stop() async {
    _persistDebounce?.cancel();
    _resumePositionMs = 0;
    await _player.stop();
    _ref.read(currentSongProvider.notifier).state = null;
    _ref.read(queueProvider.notifier).clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_playerStateKey);
    } catch (_) {}
    _persistDebounce?.cancel(); // 防止 stop 触发的状态变化又写回空状态
  }
}

final playerActionsProvider = Provider<PlayerActions>(
  (ref) => PlayerActions(ref),
);
