import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/adapter_provider.dart'
    show activeServerIdProvider, serverAdapterProvider;
import '../local/local_library.dart' show downloadIndexVersionProvider;
import '../models/models.dart';
import '../settings/streaming_prefs.dart';
import 'download_service.dart';

/// 后台下载队列（§3.2）：歌曲操作弹窗的「下载」只负责入列与提示，
/// 任务在后台顺序落盘，用户无需停在进度对话框上等待。
/// 任务状态经 [downloadQueueProvider] 暴露给下载列表弹层与设置入口。
enum DownloadTaskStatus { waiting, running, completed, failed }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.song,
    required this.serverId,
    required this.status,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  /// 'serverId|songId'：跨 async 去重与定位键
  final String id;
  final Song song;
  final String serverId;
  final DownloadTaskStatus status;
  final int received;
  final int total;
  final String? error;

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  DownloadTask copyWith({
    DownloadTaskStatus? status,
    int? received,
    int? total,
    String? error,
  }) {
    return DownloadTask(
      id: id,
      song: song,
      serverId: serverId,
      status: status ?? this.status,
      received: received ?? this.received,
      total: total ?? this.total,
      error: error ?? this.error,
    );
  }
}

class DownloadQueueController extends Notifier<List<DownloadTask>> {
  @override
  List<DownloadTask> build() => const [];

  bool _pumping = false;
  bool _completedSinceDrain = false;
  final Map<String, int> _lastProgressAt = {};

  /// 入列一批歌曲，返回实际新增数（同任务已在队列/进行中时去重）
  int enqueue(List<Song> songs, String serverId) {
    var added = 0;
    final next = [...state];
    for (final song in songs) {
      final id = '$serverId|${song.id}';
      if (next.any((t) => t.id == id)) continue;
      next.add(
        DownloadTask(
          id: id,
          song: song,
          serverId: serverId,
          status: DownloadTaskStatus.waiting,
        ),
      );
      added++;
    }
    if (added > 0) {
      state = next;
      unawaited(_pump());
    }
    return added;
  }

  /// 重试失败任务：重建为干净的等待态（清除错误与旧进度）
  void retry(String id) {
    final idx = state.indexWhere((t) => t.id == id);
    if (idx < 0 || state[idx].status != DownloadTaskStatus.failed) return;
    final t = state[idx];
    final rebuilt = DownloadTask(
      id: t.id,
      song: t.song,
      serverId: t.serverId,
      status: DownloadTaskStatus.waiting,
    );
    state = [...state]..[idx] = rebuilt;
    unawaited(_pump());
  }

  /// 移除任务：仅限非运行中（运行中的下载无法中途取消，等它自然结束）
  void remove(String id) {
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task == null || task.status == DownloadTaskStatus.running) return;
    state = state.where((t) => t.id != id).toList();
  }

  /// 清掉已完成与已失败的任务，保留排队/进行中
  void clearFinished() {
    state = state
        .where(
          (t) =>
              t.status == DownloadTaskStatus.waiting ||
              t.status == DownloadTaskStatus.running,
        )
        .toList();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    _completedSinceDrain = false;
    try {
      while (true) {
        final idx = state.indexWhere(
          (t) => t.status == DownloadTaskStatus.waiting,
        );
        if (idx < 0) break;
        final task = state[idx];
        _patch(task.id, status: DownloadTaskStatus.running);
        await _runTask(task);
      }
      // 队列排空统一 bump 一次「本地音乐」合并展示：逐首 bump 会让
      // localSongsProvider 在批量下载期间连续全量重读（同 auto_download 收尾策略）
      if (_completedSinceDrain) {
        ref.read(downloadIndexVersionProvider.notifier).state++;
      }
    } finally {
      _pumping = false;
      _lastProgressAt.clear();
    }
  }

  Future<void> _runTask(DownloadTask task) async {
    try {
      // 任务可能排队很久：起跑时校验服务器身份，切服后旧任务不得继续
      if (ref.read(activeServerIdProvider) != task.serverId) {
        _patch(
          task.id,
          status: DownloadTaskStatus.failed,
          error: '服务器已切换，任务取消',
        );
        return;
      }
      // 已下载过的不重复落盘（重复点击下载直接标记完成）
      if (await findDownloadedSong(task.song, task.serverId) != null) {
        _complete(task.id);
        return;
      }
      final source = await ref
          .read(serverAdapterProvider)!
          .resolveDownload(task.song);
      await downloadSongFile(
        source: source,
        song: task.song,
        serverId: task.serverId,
        networkSettings: ref.read(networkSettingsProvider),
        onProgress: (received, total) => _progress(task.id, received, total),
      );
      _complete(task.id);
    } on DioException {
      _patch(task.id, status: DownloadTaskStatus.failed, error: '网络错误');
    } catch (_) {
      _patch(task.id, status: DownloadTaskStatus.failed, error: '下载失败');
    }
  }

  void _complete(String id) {
    _patch(
      id,
      status: DownloadTaskStatus.completed,
      received: 1,
      total: 1,
      error: null,
    );
    _completedSinceDrain = true;
  }

  void _progress(String id, int received, int total) {
    if (total <= 0) return;
    final last = _lastProgressAt[id] ?? 0;
    // ≥2% 步进才重建列表（onProgress 每个数据块都会回调）
    if (received < total && received - last < total * 0.02) return;
    _lastProgressAt[id] = received;
    _patch(id, received: received, total: total);
  }

  static const _absent = Object();

  void _patch(
    String id, {
    DownloadTaskStatus? status,
    int? received,
    int? total,
    Object? error = _absent,
  }) {
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(
            status: status,
            received: received,
            total: total,
            error: error == _absent ? t.error : error as String?,
          )
        else
          t,
    ];
  }
}

final downloadQueueProvider =
    NotifierProvider<DownloadQueueController, List<DownloadTask>>(
      DownloadQueueController.new,
    );
