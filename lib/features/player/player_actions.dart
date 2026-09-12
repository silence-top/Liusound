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
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _fading = false; // 交叉淡化进行中（防重入）
  int _resumePositionMs = 0; // 冷启动待恢复进度（首播时一次性消费）
  int _playGeneration = 0; // 播放代数：连点切歌时旧加载流程作废，避免竞争
  final _random = Random();

  /// 长音频断点阈值（>10min 的曲目单独记进度，有声书/长录音续播用）
  static const _longTrack = Duration(minutes: 10);

  static String _breakpointKey(String songId) => 'breakpoint_$songId';

  AudioPlayer get _player => _ref.read(audioPlayerProvider);
  ServerAdapter? get _adapter => _ref.read(serverAdapterProvider);
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
      _schedulePersist();
    });
    _ref.listen<double>(playbackSpeedProvider, (_, speed) {
      _ref.read(audioPlayerProvider).setSpeed(speed);
    });
    _ref.listen<Song?>(currentSongProvider, (_, song) {
      if (song != null) _syncShufflePos(song.id);
      _ref.read(abLoopProvider.notifier).state = ABLoopState.disabled;
      _schedulePersist();
    });
    _ref.listen<List<Song>>(queueProvider, (_, queue) {
      _syncShuffleOrder(queue);
      _schedulePersist();
    });
    unawaited(_initialize());
  }

  /// 严格初始化顺序（P0-PLAYER-01）：
  /// RESTORING（恢复队列→当前歌→进度）→ 绑定播放器事件 → READY。
  /// READY 之前禁止自动播放 / crossfade / 自动切歌；
  /// 恢复失败安全降级到空队列，不允许无限 restore loop
  Future<void> _initialize() async {
    if (_restoring || _restored) return;
    _restoring = true;
    try {
      await _restore();
    } catch (_) {
      // 损坏的持久化数据按无状态处理
    } finally {
      _restored = true;
      _restoring = false;
    }
    _bindPlayerEvents();
    _ref.read(playerReadyProvider.notifier).state = true;
    // READY 之后才允许恢复后自动播放（用户显式开启的 auto_play 行为保持不变）
    if (_ref.read(autoPlayProvider.notifier).state) {
      final song = _ref.read(currentSongProvider);
      final resumeMs = _resumePositionMs;
      _resumePositionMs = 0;
      if (song != null && _adapter != null) {
        await play(song);
        if (resumeMs > 0) {
          try {
            await _player.seek(Duration(milliseconds: resumeMs));
          } catch (_) {}
        }
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
            if (!_restored) return; // READY 之前不自动切歌
            unawaited(playNext());
          }),
    );
    _subs.add(player.positionStream.listen(_tickCrossfade));
    _subs.add(player.positionStream.listen(_tickABLoop));
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
    final ids = <String>{for (final s in queue) s.id};
    final prev = _ref.read(shuffleOrderProvider);
    final order = prev.order.where(ids.contains).toList();
    final currentId = _ref.read(currentSongProvider)?.id;
    final pos = currentId == null ? -1 : order.indexOf(currentId);
    final fresh = ids.where((id) => !order.contains(id)).toList()
      ..shuffle(_random);
    for (final id in fresh) {
      final insertAt = pos < 0
          ? _random.nextInt(order.length + 1)
          : pos + 1 + _random.nextInt(order.length - pos);
      order.insert(insertAt, id);
    }
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
    final ids =
        _ref
            .read(queueProvider)
            .map((s) => s.id)
            .where((id) => id != songId)
            .toList()
          ..shuffle(_random);
    _ref.read(shuffleOrderProvider.notifier).state = ShuffleOrderState(
      order: [songId, ...ids],
      pos: 0,
    );
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
      if (song == null || dur == null || dur < PlayerActionsBase._longTrack) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        PlayerActionsBase._breakpointKey(song.id),
        position.inMilliseconds,
      );
    } catch (_) {}
  }

  // ---------- A-B 循环 ----------

  /// 位置监听：looping 阶段到达 B 点时回到 A 点
  void _tickABLoop(Duration pos) {
    final ab = _ref.read(abLoopProvider);
    if (ab.phase != ABLoopPhase.looping) return;
    if (pos.inMilliseconds >= ab.bMs!) {
      unawaited(_player.seek(Duration(milliseconds: ab.aMs!)));
    }
  }

  /// 循环 A-B：off → 标记 A → 标记 B（开始循环）→ 清除
  void cycleABLoop() {
    final ab = _ref.read(abLoopProvider);
    final posMs = _player.position.inMilliseconds;
    switch (ab.phase) {
      case ABLoopPhase.off:
        _ref.read(abLoopProvider.notifier).state = ABLoopState.disabled.markA(posMs);
      case ABLoopPhase.setA:
        if (posMs <= ab.aMs!) {
          // B 必须大于 A，否则重置
          _ref.read(abLoopProvider.notifier).state = ABLoopState.disabled.markA(posMs);
        } else {
          _ref.read(abLoopProvider.notifier).state = ab.markB(posMs);
        }
      case ABLoopPhase.looping:
        _ref.read(abLoopProvider.notifier).state = ABLoopState.disabled;
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
