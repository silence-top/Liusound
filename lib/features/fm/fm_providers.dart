import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/adapter_provider.dart'
    show activeServerIdProvider, serverAdapterProvider;
import '../../core/api/server_adapter.dart';
import '../../core/history/play_history.dart';
import '../../core/models/models.dart';
import '../player/player_controller.dart';

/// 私人 FM：复用全局播放队列（replaceAll + add），FM 只负责
/// 「抽一批新歌」与「队列将尽时补一批」，播放/切歌全走既有 PlayerActions。
/// 抽歌走 SongSort.random（七后端均已实现），排除近 7 天听过的歌曲。
final fmLoadingProvider = StateProvider<bool>((ref) => false);

class FmController {
  FmController(this._ref);

  final Ref _ref;

  static const _batchSize = 20;

  /// 抽一批歌：两轮随机（第一轮严格排除近 7 天听过，第二轮放宽只去重），
  /// 曲库很小时保证仍有歌可播
  Future<List<Song>> _draw() async {
    final adapter = _ref.read(serverAdapterProvider);
    final serverId = _ref.read(activeServerIdProvider);
    if (adapter == null || serverId.isEmpty) return const [];
    final existing = _ref.read(queueProvider).map((s) => s.id).toSet();
    final currentId = _ref.read(currentSongProvider)?.id;
    final recent = await PlayHistory.recentSongIds(serverId);
    final batch = <Song>[];
    for (var round = 0; round < 2 && batch.length < _batchSize; round++) {
      final List<Song> songs;
      try {
        songs = await adapter.fetchSongs(
          const SongQuery(sort: SongSort.random, limit: 50),
        );
      } catch (_) {
        break;
      }
      for (final s in songs) {
        if (s.id == currentId) continue;
        if (existing.contains(s.id)) continue;
        if (batch.any((b) => b.id == s.id)) continue;
        if (round == 0 && recent.contains(s.id)) continue;
        batch.add(s);
      }
    }
    return batch;
  }

  /// 开始漫游：替换队列为一批新歌并立即播放
  Future<bool> start() async {
    if (_ref.read(fmLoadingProvider)) return false;
    _ref.read(fmLoadingProvider.notifier).state = true;
    try {
      final batch = await _draw();
      if (batch.isEmpty) return false;
      final actions = _ref.read(playerActionsProvider);
      actions.replaceQueue(batch);
      await actions.play(batch.first);
      return true;
    } finally {
      _ref.read(fmLoadingProvider.notifier).state = false;
    }
  }

  /// 队列剩余不足时（当前曲之后 ≤3 首）补一批到队尾
  Future<void> refillIfNeeded() async {
    final queue = _ref.read(queueProvider);
    final current = _ref.read(currentSongProvider);
    final index = current == null
        ? -1
        : queue.indexWhere((s) => s.id == current.id);
    if (queue.length - index - 1 > 3) return;
    final batch = await _draw();
    if (batch.isNotEmpty) {
      _ref.read(queueProvider.notifier).add(batch);
    }
  }

  /// 不喜欢：跳下一首并把当前曲移出队列（不再回来）
  Future<void> skipDislike() async {
    final dislikedId = _ref.read(currentSongProvider)?.id;
    await _ref.read(playerActionsProvider).playNext();
    if (dislikedId != null) {
      _ref.read(queueProvider.notifier).remove(dislikedId);
    }
  }

  /// 收藏当前曲（乐观更新，失败回滚）
  Future<void> likeCurrent() async {
    final song = _ref.read(currentSongProvider);
    if (song == null) return;
    final target = !song.starred;
    _ref.read(currentSongProvider.notifier).state = song.copyWith(
      starred: target,
    );
    final ok = await _ref.read(serverAdapterProvider)?.setStar(song.id, target);
    if (ok != true) {
      _ref.read(currentSongProvider.notifier).state = song;
    }
  }
}

final fmControllerProvider = Provider<FmController>((ref) => FmController(ref));
