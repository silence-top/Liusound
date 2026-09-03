import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/server_adapter.dart';
import '../../core/models/models.dart';
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

final queueProvider =
    NotifierProvider<QueueNotifier, List<Song>>(QueueNotifier.new);

/// 播放模式
enum PlayMode { order, shuffle, repeatOne }

final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.order);

/// 播放速度（0.5-3.0，歌曲操作菜单调整，随播放状态持久化）
final playbackSpeedProvider = StateProvider<double>((ref) => 1.0);

/// 循环播放（队列播完回首）；关闭时播完队列即停止（设置页开关）
final loopPlaybackProvider = StateProvider<bool>((ref) => true);

/// 启动后自动播放（恢复上次队列与进度并直接播放）
final autoPlayProvider = StateProvider<bool>((ref) => false);

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

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, Duration?>(SleepTimerNotifier.new);

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
          mode == PlayMode.repeatOne ? LoopMode.one : LoopMode.off);
      _schedulePersist();
    });
    _ref.listen<double>(playbackSpeedProvider, (_, speed) {
      player.setSpeed(speed);
    });
    _ref.listen<Song?>(currentSongProvider, (_, _) => _schedulePersist());
    _ref.listen<List<Song>>(queueProvider, (_, _) => _schedulePersist());
    _restore();
  }

  final Ref _ref;
  Timer? _persistDebounce;
  bool _restored = false;
  int _resumePositionMs = 0; // 冷启动待恢复进度（首播时一次性消费）
  final _random = Random();

  AudioPlayer get _player => _ref.read(audioPlayerProvider);
  ServerAdapter? get _adapter => _ref.read(serverAdapterProvider);

  // ---------- 播放控制 ----------

  /// 播放指定歌曲（替换当前曲目）
  Future<void> play(Song song) async {
    final adapter = _adapter;
    if (adapter == null) return;
    _ref.read(currentSongProvider.notifier).state = song;
    try {
      final source = await adapter.resolveStream(song);
      await _player.setUrl(source.url, headers: source.headers);
      await _player.play();
    } catch (_) {
      // 流加载失败不中断 UI（网络抖动场景，状态保持可重试）
    }
  }

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

  Future<void> seek(Duration position) => _player.seek(position);

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
        'queue':
            _ref.read(queueProvider).take(100).map((s) => s.toJson()).toList(),
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
          _ref.read(playModeProvider.notifier).state =
              PlayMode.values.firstWhere(
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
            (((saved['currentTime'] as num?)?.toDouble() ?? 0) * 1000)
                .round();

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

final playerActionsProvider =
    Provider<PlayerActions>((ref) => PlayerActions(ref));
