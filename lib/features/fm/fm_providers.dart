import 'dart:async';

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

  /// 队列身份签名：List 是引用相等，跨 async 间隙比对必须用字符串形态。
  /// 抽歌是两次网络请求，期间队列/当前曲可能被用户操作改写
  String _queueSignature() {
    final queue = _ref.read(queueProvider);
    return '${queue.length}|'
        '${queue.isEmpty ? '' : queue.first.id}|'
        '${queue.isEmpty ? '' : queue.last.id}|'
        '${_ref.read(currentSongProvider)?.id ?? ''}';
  }

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
      final serverId = _ref.read(activeServerIdProvider);
      final queueSig = _queueSignature();
      final batch = await _draw();
      // 抽歌期间切服务器/换队列会使本次会话作废：旧批量若照常 replaceQueue，
      // 会把旧服务器的歌倒进新服务器的队列
      if (batch.isEmpty ||
          _ref.read(activeServerIdProvider) != serverId ||
          _queueSignature() != queueSig) {
        return false;
      }
      final actions = _ref.read(playerActionsProvider);
      actions.replaceQueue(batch);
      // replaceQueue 会清除 FM 激活态（曲库整表播放语义），这里重新置位
      _ref.read(fmActiveProvider.notifier).state = true;
      await actions.play(batch.first);
      return true;
    } finally {
      _ref.read(fmLoadingProvider.notifier).state = false;
    }
  }

  bool _refilling = false;

  /// 队列剩余不足时（当前曲之后 ≤3 首）补一批到队尾；
  /// in-flight 守卫防并发切歌时重复补两批
  Future<void> refillIfNeeded() async {
    if (_refilling) return;
    _refilling = true;
    try {
      final queue = _ref.read(queueProvider);
      final current = _ref.read(currentSongProvider);
      final index = current == null
          ? -1
          : queue.indexWhere((s) => s.id == current.id);
      if (queue.length - index - 1 > 3) return;
      final serverId = _ref.read(activeServerIdProvider);
      final queueSig = _queueSignature();
      final batch = await _draw();
      // 抽歌是网络请求：期间退出 FM/切服务器/换队列后旧批量不得再追加，
      // 否则旧服务器的歌会混进新环境的队尾
      if (batch.isEmpty ||
          !_ref.read(fmActiveProvider) ||
          _ref.read(activeServerIdProvider) != serverId ||
          _queueSignature() != queueSig) {
        return;
      }
      _ref.read(queueProvider.notifier).add(batch);
    } finally {
      _refilling = false;
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

/// FM 队列余量守卫：随 App 存活，FM 激活期间切歌自动补批——
/// 此前只挂在 FM 页的 ref.listen 上，离开页面后队列耗尽漫游即停
class FmRefillService {
  FmRefillService(this._ref) {
    _sub = _ref.listen<Song?>(currentSongProvider, (_, _) {
      if (!_ref.read(fmActiveProvider)) return;
      unawaited(_ref.read(fmControllerProvider).refillIfNeeded());
    });
  }

  final Ref _ref;
  late final ProviderSubscription<Song?> _sub;

  void dispose() => _sub.close();
}

final fmRefillServiceProvider = Provider<FmRefillService>((ref) {
  final service = FmRefillService(ref);
  ref.onDispose(service.dispose);
  return service;
});
