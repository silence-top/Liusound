import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';
import '../../core/settings/streaming_prefs.dart';
import '../../core/settings/prefs.dart';
import 'player_actions.dart';

export 'player_actions.dart' show PlayerActions;

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

/// Shuffle 遍历序（P1-ShuffleOrder）：队列 id 的随机全排列 + 游标。
/// next 沿序前进、一轮完整遍历后重新洗牌，previous 沿序回退，
/// 一轮内不重复；nextSongProvider 预判与 playNext 实际取歌共用此序
class ShuffleOrderState {
  const ShuffleOrderState({this.order = const [], this.pos = -1});

  final List<String> order;
  final int pos; // 当前歌曲在 order 中的下标（-1 尚未开始/当前歌不在序中）
}

final shuffleOrderProvider = StateProvider<ShuffleOrderState>(
  (ref) => const ShuffleOrderState(),
);

/// 下一首预判（触底文案 {nTitle} 占位符与交叉淡化共用）：与 playNext 的
/// 实际取歌逻辑严格一致——单曲循环返回 null、随机走遍历序游标、顺序取下一条
final nextSongProvider = Provider<Song?>((ref) {
  final queue = ref.watch(queueProvider);
  final current = ref.watch(currentSongProvider);
  if (current == null || queue.isEmpty) return null;
  switch (ref.watch(playModeProvider)) {
    case PlayMode.repeatOne:
      return null;
    case PlayMode.shuffle:
      final so = ref.watch(shuffleOrderProvider);
      final nextPos = so.pos + 1;
      if (nextPos <= 0 || nextPos >= so.order.length) return null;
      final nextId = so.order[nextPos];
      for (final s in queue) {
        if (s.id == nextId) return s;
      }
      return null;
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

/// ReplayGain 归一化模式：off 不调整，track 按曲目增益，album 按专辑增益
enum ReplayGainMode { off, track, album }

final replayGainModeProvider = StateProvider<ReplayGainMode>(
  (ref) => ReplayGainMode.off,
);

/// A-B 循环：off 未启用 → setA 已标记 A 待设 B → looping A↔B 循环中
class ABLoopState {
  const ABLoopState({this.aMs, this.bMs});

  final int? aMs;
  final int? bMs;

  ABLoopPhase get phase {
    if (aMs == null) return ABLoopPhase.off;
    if (bMs == null) return ABLoopPhase.setA;
    return ABLoopPhase.looping;
  }

  static const disabled = ABLoopState();

  ABLoopState markA(int ms) => ABLoopState(aMs: ms);
  ABLoopState markB(int ms) => ABLoopState(aMs: aMs, bMs: ms);
  ABLoopState clear() => disabled;
}

enum ABLoopPhase { off, setA, looping }

final abLoopProvider = StateProvider<ABLoopState>(
  (ref) => ABLoopState.disabled,
);

/// 循环播放（队列播完回首）；关闭时播完队列即停止（设置页开关）
final loopPlaybackProvider = StateProvider<bool>((ref) => true);

/// 启动后自动播放（恢复上次队列与进度并直接播放）
final autoPlayProvider = StateProvider<bool>((ref) => false);

/// 交叉淡入淡出时长（秒，0=关闭，上限 10；持久化）
class CrossfadeSecondsNotifier extends Notifier<int> {
  static const _key = 'crossfade_seconds';

  @override
  int build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getInt(_key) ?? 0;
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
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getBool(_key) ?? true;
  }

  void set(bool v) {
    state = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_key, v));
  }
}

final autoOpenPlayerProvider = NotifierProvider<AutoOpenPlayerNotifier, bool>(
  AutoOpenPlayerNotifier.new,
);

/// 播放器恢复完成信号（冷启动恢复流程 READY 后置 true）。
/// Scrobble 等位置监听方必须忽略 READY 之前的 position 事件，
/// 避免恢复期间的加载进度被误当成真实播放
final playerReadyProvider = StateProvider<bool>((ref) => false);

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

/// 缓冲位置（已缓冲到的进度；进度条缓冲条用，体现边放边加载）
final bufferedPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioPlayerProvider).bufferedPositionStream,
);

/// 缓冲中（loading/buffering；播放键 spinner 用，网络慢时给出可见反馈）
final isBufferingProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(audioPlayerProvider)
      .processingStateStream
      .map(
        (s) => s == ProcessingState.buffering || s == ProcessingState.loading,
      )
      .distinct();
});

/// 当前曲目实际生效的音质档（含转码失败回退无损后的真实档）。
/// 本地/离线播放为 null，UI 不显示标签
final currentQualityProvider = StateProvider<StreamQuality?>((ref) => null);

/// 歌词偏移持久化 key 前缀（对标 1.x LYRIC_OFFSET_PREFIX）
const lyricOffsetKeyPrefix = 'lyricOffset_';

/// 双语歌词开关持久化 key（全局，默认开启）
const bilingualLyricsKey = 'lyrics_bilingual_enabled';

/// 双语歌词开关（响应式）：MiniBar 副标题与全屏歌词页共用同一状态源，
/// 切换即时刷新所有消费端（此前 MiniBar 非响应式读 prefs，切开关不刷新）
class BilingualLyricsNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getBool(bilingualLyricsKey) ?? true;
  }

  void set(bool v) {
    state = v;
    SharedPreferences.getInstance().then(
      (p) => p.setBool(bilingualLyricsKey, v),
    );
  }
}

final bilingualLyricsProvider = NotifierProvider<BilingualLyricsNotifier, bool>(
  BilingualLyricsNotifier.new,
);

/// 播放控制动作集合（P1 渐进式拆分后的门面：类体与职责块在 player_actions.dart，
/// 本文件保留全部 Provider 状态源与构造入口，外部导入路径不变）
final playerActionsProvider = Provider<PlayerActions>(
  (ref) => PlayerActions(ref),
);
