import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/server_adapter.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/platform/app_platform.dart';
import '../../core/platform/local_fs.dart';
import '../../core/download/download_service.dart';
import '../../core/local/local_library.dart';
import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../core/settings/streaming_prefs.dart';
import '../auth/auth_controller.dart';
import 'player_controller.dart';

part 'player_breakpoint.dart';
part 'player_crossfade.dart';
part 'player_error_handler.dart';
part 'player_persistence.dart';
part 'player_restore.dart';
part 'player_source_resolver.dart';

/// 播放状态持久化 key（对标 1.x STORAGE_KEYS.PLAYER_STATE）
const _playerStateKey = 'player_state';

/// 共享私有状态基类：part 内各职责 mixin 通过 `on PlayerActionsBase`
/// 访问这些字段/Getter，避免 mixin 与宿主类互相循环约束
abstract class PlayerActionsBase {
  PlayerActionsBase(this._ref);

  final Ref _ref;
  Timer? _persistDebounce;
  bool _restored = false;
  bool _restoring = false; // 恢复防重入
  bool _eventsBound = false;
  bool _repeatEventsBound = false;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _fading = false; // 交叉淡化进行中（防重入）
  int _resumePositionMs = 0; // 冷启动待恢复进度（首播时一次性消费）
  // 首播前待 seek 的恢复进度：play() 装源完成后、起播前消费，
  // 避免「先从 0 播一段、暂停后才跳断点」（just_audio play() 完成语义所致）
  int _pendingResumeMs = 0;
  int _playGeneration = 0; // 播放代数：连点切歌时旧加载流程作废，避免竞争
  bool _disposed = false; // provider 已销毁（订阅/Timer 已清理）
  bool _wasPlaying = false; // playingStream 真转假判定（首帧不视为暂停）
  DateTime? _lastPositionPersistAt; // 播放中进度持久化节流
  final _random = Random();

  /// 长音频断点阈值（>10min 的曲目单独记进度，有声书/长录音续播用）
  static const _longTrack = Duration(minutes: 10);

  // 不读取旧的 song-only key：它没有服务器归属，迁移会把另一服断点带进来。
  static String _breakpointKey(String serverId, String songId) =>
      'breakpoint_v2_${jsonEncode([serverId, songId])}';

  int _seekGeneration = 0; // 用户 seek 使等待 prefs 的自动续播失效

  AudioPlayer get _player => _ref.read(audioPlayerProvider);
  ServerAdapter? get _adapter => _ref.read(serverAdapterProvider);

  bool _isCurrentRequest(int gen, String serverId) =>
      !_disposed &&
      serverId == _ref.read(activeServerIdProvider) &&
      gen == _playGeneration;

  bool _isCurrentPlayback(LoadedPlayback loaded) =>
      _isCurrentRequest(loaded.generation, loaded.serverId) &&
      identical(_ref.read(loadedPlaybackProvider), loaded) &&
      loaded.ownsPlayer(_player);

  LoadedPlayback? get _loadedPlayback {
    final loaded = _ref.read(loadedPlaybackProvider);
    return loaded != null && _isCurrentPlayback(loaded) ? loaded : null;
  }
}

/// 播放控制动作集合（切歌 / 模式 / 队列 / 持久化 / 恢复）。
/// P1 渐进式拆分：本类只保留初始化顺序、播放控制与队列/随机序维护，
/// 职责块按 part 拆出（错误处理/断点/持久化/恢复/源解析/交叉淡化）
class PlayerActions extends PlayerActionsBase
    with
        PlayerErrorHandler,
        PlayerBreakpoint,
        PlayerPersistence,
        PlayerRestore,
        PlayerSourceResolver,
        PlayerCrossfade {
  PlayerActions(super.ref) {
    // Provider 状态监听必须同步挂载（Riverpod 限制）；
    // 播放器事件流与恢复流程按严格顺序在 _initialize 中执行：
    // RESTORING（队列/当前歌/进度）→ 绑定事件 → READY → 自动播放
    _ref.listen<PlayMode>(playModeProvider, (_, mode) {
      _ref
          .read(audioPlayerProvider)
          .setLoopMode(
            mode == PlayMode.repeatOne ? LoopMode.one : LoopMode.off,
          );
      if (mode == PlayMode.repeatOne) _bindRepeatSessionEvents();
      _schedulePersist();
    });
    _ref.listen<double>(playbackSpeedProvider, (_, speed) {
      _ref.read(audioPlayerProvider).setSpeed(speed);
    });
    _ref.listen<Song?>(currentSongProvider, (_, song) {
      if (song != null) _syncShufflePos(song.id);
      _schedulePersist();
    });
    _ref.listen<List<Song>>(queueProvider, (_, queue) {
      _syncShuffleOrder(queue);
      _schedulePersist();
    });
    _ref.listen<LoadedPlayback?>(loadedPlaybackProvider, (_, loaded) {
      _lastPositionPersistAt = null;
      _schedulePersist();
    });
    _ref.listen<String>(activeServerIdProvider, (previous, next) {
      if (previous == next) return;
      final breakpoint = _captureLongTrackBreakpoint();
      ++_playGeneration;
      _pendingResumeMs = 0;
      _resumePositionMs = 0;
      _ref.read(loadedPlaybackProvider.notifier).state = null;
      _ref.read(currentQualityProvider.notifier).state = null;
      _ref.read(resumeNoticeProvider.notifier).state = null;
      unawaited(_saveLongTrackBreakpoint(breakpoint));
      unawaited(_player.pause());
    });
    _ref.onDispose(() {
      _disposed = true;
      _persistDebounce?.cancel();
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
    unawaited(_initialize());
  }

  /// 严格初始化顺序（P0-PLAYER-01）：
  /// RESTORING（恢复队列→当前歌→进度）→ 绑定播放器事件 → READY。
  /// READY 之前禁止自动播放 / crossfade / 自动切歌；
  /// 恢复失败安全降级到空队列，不允许无限 restore loop
  Future<void> _initialize() async {
    if (_restoring || _restored || _disposed) return;
    _restoring = true;
    try {
      await _restore();
    } catch (_) {
      // 损坏的持久化数据按无状态处理
    } finally {
      _restored = true;
      _restoring = false;
    }
    if (_disposed) return;
    _bindPlayerEvents();
    _ref.read(playerReadyProvider.notifier).state = true;
    // READY 之后才允许恢复后自动播放（用户显式开启的 auto_play 行为保持不变）
    if (_ref.read(autoPlayProvider.notifier).state) {
      final song = _ref.read(currentSongProvider);
      if (song != null && _adapter != null) {
        // 进度由 play() 在装源后、起播前 seek 恢复（_pendingResumeMs），
        // 不经过长音频断点恢复，也不等待 play() 的「暂停/播完」完成语义
        _pendingResumeMs = _resumePositionMs;
        _resumePositionMs = 0;
        await play(song);
      }
    }
  }

  /// 绑定播放器事件流（仅在恢复完成后执行一次）
  void _bindPlayerEvents() {
    if (_eventsBound) return;
    _eventsBound = true;
    final player = _player;
    // 播放结束自动切下一首（repeatOne 由 LoopMode.one 在内核层循环，不会触发 completed）
    _subs.add(
      player.processingStateStream
          .where((s) => s == ProcessingState.completed)
          .listen((_) {
            if (!_restored || _disposed || _loadedPlayback == null) return;
            // 旧源排队的 completed 事件不能推进刚装好的新歌。
            if (player.processingState != ProcessingState.completed) return;
            if (_fading) return; // 交叉淡化由 _runCrossfade 推进，避免双重切歌
            unawaited(playNext());
          }),
    );
    _subs.add(
      player.positionStream.listen((pos) {
        _tickCrossfade(pos);
        _tickPositionPersist(pos);
      }),
    );
    _subs.add(
      player.playingStream.listen((playing) {
        // 仅「真转假」视为暂停瞬间落盘。playingStream 是种子流：绑定瞬间
        // 就会吐出当前值 false——那是冷启动的初始态不是暂停，若落盘会把
        // 尚未加载音源的零进度写回，覆盖掉保存的断点
        final wasPlaying = _wasPlaying;
        _wasPlaying = playing;
        if (!playing && wasPlaying && _restored) _tickPausePersist();
      }),
    );
  }

  // 内核单曲循环不发 completed，以 autoAdvance 更新会话而不误判用户 seek。
  void _bindRepeatSessionEvents() {
    if (_repeatEventsBound) return;
    _repeatEventsBound = true;
    _subs.add(
      _player.positionDiscontinuityStream.listen((event) {
        if (_disposed ||
            !_restored ||
            event.reason != PositionDiscontinuityReason.autoAdvance ||
            _ref.read(playModeProvider) != PlayMode.repeatOne) {
          return;
        }
        final loaded = _loadedPlayback;
        if (loaded == null || !_player.playing) return;
        _ref.read(loadedPlaybackProvider.notifier).state = LoadedPlayback(
          song: loaded.song,
          serverId: loaded.serverId,
          generation: ++_playGeneration,
          source: loaded.source,
        );
      }),
    );
  }

  /// 播放/暂停切换；冷启动恢复后的首播会先加载流并跳到上次进度
  Future<void> toggle() async {
    final player = _player;
    if (player.playing) {
      await player.pause();
      return;
    }
    if (_loadedPlayback == null) {
      final song = _ref.read(currentSongProvider);
      if (song != null) {
        // 无已加载会话时必须重新装源，不能唤醒失败请求遗留的旧音源。
        _pendingResumeMs = _resumePositionMs;
        _resumePositionMs = 0;
        await play(song);
      }
      return;
    }
    await player.play();
  }

  /// 暂停（定时停止到点时调用）
  Future<void> pause() => _player.pause();

  /// 下一首（order：尾部循环回首；shuffle：沿遍历序前进，一轮播完重新洗牌；
  /// repeatOne：重播当前）
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
      final so = _ref.read(shuffleOrderProvider);
      if (so.order.isEmpty) return;
      var order = so.order;
      var nextPos = so.pos + 1;
      if (nextPos >= order.length) {
        // 本轮完整遍历结束：重新洗牌开启新一轮，避免与当前曲重复起头
        order = [...order]..shuffle(_random);
        nextPos = 0;
        if (order.length > 1 && order[0] == current.id) {
          final swap = 1 + _random.nextInt(order.length - 1);
          final tmp = order[0];
          order[0] = order[swap];
          order[swap] = tmp;
        }
      }
      _ref.read(shuffleOrderProvider.notifier).state = ShuffleOrderState(
        order: order,
        pos: nextPos,
      );
      final next = _songById(queue, order[nextPos]);
      if (next != null) await play(next);
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

  /// 上一首（order：首曲不动；shuffle：沿遍历序回退；repeatOne：重播当前）
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
      final so = _ref.read(shuffleOrderProvider);
      if (so.pos <= 0) return; // 本轮开头，无历史可回退
      _ref.read(shuffleOrderProvider.notifier).state = ShuffleOrderState(
        order: so.order,
        pos: so.pos - 1,
      );
      final prev = _songById(queue, so.order[so.pos - 1]);
      if (prev != null) await play(prev);
      return;
    }
    final index = queue.indexWhere((s) => s.id == current.id);
    if (index > 0) {
      await play(queue[index - 1]);
    }
  }

  Song? _songById(List<Song> queue, String id) {
    for (final s in queue) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---------- Shuffle 遍历序维护（P1-ShuffleOrder） ----------

  /// 队列变化时增量维护遍历序：剔除已删歌曲、新歌随机插入当前位之后，
  /// 保证本轮遍历仍完整覆盖队列且不重复
  void _syncShuffleOrder(List<Song> queue) {
    final remaining = <String>{for (final s in queue) s.id};
    final prev = _ref.read(shuffleOrderProvider);
    // Set.remove 同时过滤删除项、去重并求出新 ID，避免逐项扫描 order。
    final retained = [
      for (final id in prev.order)
        if (remaining.remove(id)) id,
    ];
    final currentId = _ref.read(currentSongProvider)?.id;
    final pos = currentId == null ? -1 : retained.indexOf(currentId);
    final fresh = remaining.toList()..shuffle(_random);
    if (fresh.isEmpty && pos == prev.pos && listEquals(retained, prev.order)) {
      return; // 收藏/元数据更新或队列重排不改变遍历序，不通知 shuffle 消费者。
    }

    // 加权合并保持旧歌曲相对顺序，新歌曲仅插入当前位之后，全程 O(N)。
    final order = retained.take(pos + 1).toList();
    var oldIndex = pos + 1;
    var freshIndex = 0;
    while (oldIndex < retained.length && freshIndex < fresh.length) {
      final oldLeft = retained.length - oldIndex;
      final freshLeft = fresh.length - freshIndex;
      if (_random.nextInt(oldLeft + freshLeft) < freshLeft) {
        order.add(fresh[freshIndex++]);
      } else {
        order.add(retained[oldIndex++]);
      }
    }
    order.addAll(retained.skip(oldIndex));
    order.addAll(fresh.skip(freshIndex));
    _ref.read(shuffleOrderProvider.notifier).state = ShuffleOrderState(
      order: order,
      pos: pos,
    );
  }

  /// 播放时对齐游标；当前歌不在遍历序中（队列外点播）则以它为起点重建全序
  void _syncShufflePos(String songId) {
    final prev = _ref.read(shuffleOrderProvider);
    final idx = prev.order.indexOf(songId);
    if (idx >= 0) {
      if (idx != prev.pos) {
        _ref.read(shuffleOrderProvider.notifier).state = ShuffleOrderState(
          order: prev.order,
          pos: idx,
        );
      }
      return;
    }
    final ids = {
      for (final song in _ref.read(queueProvider))
        if (song.id != songId) song.id,
    }.toList()..shuffle(_random);
    _ref.read(shuffleOrderProvider.notifier).state = ShuffleOrderState(
      order: [songId, ...ids],
      pos: 0,
    );
  }

  /// 单曲手动重播仍复用音源，但重建会话，统计不再按 song id 永久去重。
  Future<void> _restartCurrent() async {
    final loaded = _loadedPlayback;
    if (loaded == null) {
      final song = _ref.read(currentSongProvider);
      if (song != null) await play(song);
      return;
    }
    final gen = ++_playGeneration;
    _ref.read(loadedPlaybackProvider.notifier).state = null;
    await _player.seek(Duration.zero);
    if (!_isCurrentRequest(gen, loaded.serverId) ||
        !loaded.ownsPlayer(_player)) {
      return;
    }
    _ref.read(loadedPlaybackProvider.notifier).state = LoadedPlayback(
      song: loaded.song,
      serverId: loaded.serverId,
      generation: gen,
      source: loaded.source,
    );
    if (!_player.playing) unawaited(_player.play());
  }

  /// 切换播放模式：顺序 → 随机 → 单曲循环
  void cyclePlayMode() {
    final mode = _ref.read(playModeProvider);
    _ref.read(playModeProvider.notifier).state =
        PlayMode.values[(mode.index + 1) % PlayMode.values.length];
  }

  Future<void> seek(Duration position) async {
    ++_seekGeneration;
    final loaded = _loadedPlayback;
    if (loaded == null || position < Duration.zero) return;
    final duration = loaded.effectiveDuration(_player);
    if (duration != null && position > duration) return;
    await _player.seek(position);
    if (!_isCurrentPlayback(loaded)) return;
    await _saveLongTrackBreakpoint(_captureLongTrackBreakpoint());
  }

  // ---------- 队列管理 ----------

  void addToQueue(List<Song> songs) =>
      _ref.read(queueProvider.notifier).add(songs);

  /// 下一首播放：插到当前曲目之后
  void playNextInQueue(List<Song> songs) =>
      _ref.read(queueProvider.notifier).insertAfterCurrent(songs);

  void replaceQueue(List<Song> songs) {
    // 曲库/歌单整表播放退出 FM 漫游（FM start 在 replaceQueue 后重新置位）
    _ref.read(fmActiveProvider.notifier).state = false;
    _ref.read(queueProvider.notifier).replaceAll(songs);
  }

  void removeFromQueue(String songId) =>
      _ref.read(queueProvider.notifier).remove(songId);

  /// 拖动排序（队列弹窗）
  void reorderQueue(int oldIndex, int newIndex) =>
      _ref.read(queueProvider.notifier).reorder(oldIndex, newIndex);

  void clearQueue() => _ref.read(queueProvider.notifier).clear();

  /// 登出/切服默认清空状态；系统媒体 stop 保留原有队列/续播语义。
  Future<void> stop({bool clearState = true}) async {
    // 先使在途播放请求失效：旧 resolve/play 晚到不得再装源出声
    // （否则清空的队列之后还会响起旧服务器的歌）
    final breakpoint = _captureLongTrackBreakpoint();
    final resumeMs = _loadedPlayback == null
        ? _resumePositionMs
        : _player.position.inMilliseconds;
    final gen = ++_playGeneration;
    _ref.read(loadedPlaybackProvider.notifier).state = null;
    _ref.read(currentQualityProvider.notifier).state = null;
    unawaited(_saveLongTrackBreakpoint(breakpoint));
    _pendingResumeMs = 0;
    _ref.read(fmActiveProvider.notifier).state = false;
    _persistDebounce?.cancel();
    _resumePositionMs = clearState ? 0 : resumeMs;
    // 清除已加载会话后，暂停监听不会把旧/零进度计给 UI 选中的歌曲。
    if (clearState) _ref.read(currentSongProvider.notifier).state = null;
    await _player.stop();
    if (_disposed || gen != _playGeneration) return;
    if (!clearState) {
      await _persistNow();
      return;
    }
    _ref.read(queueProvider.notifier).clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || gen != _playGeneration) return;
      await prefs.remove(_playerStateKey);
    } catch (_) {}
    if (gen == _playGeneration) {
      _persistDebounce?.cancel(); // 防止 stop 触发的状态变化又写回空状态
    }
  }
}
