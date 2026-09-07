import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../storage/app_db.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';

/// RefReader：统一 Ref / WidgetRef 的 read tear-off
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// Scrobble 上报服务：
/// 播放达 50% 或满 2 分钟（先到先触发）向服务端上报一次；
/// 失败/离线入 SQLite 队列，网络恢复后按时间戳顺序补发。
/// 后端不支持 Scrobble（capabilities.scrobbling=false，如 Audio Station）
/// 时不上报也不入队（能力矩阵如实降级）。
class ScrobbleService {
  ScrobbleService(this._read) {
    _subs.add(_read(audioPlayerProvider).positionStream.listen(_onPosition));
    _subs.add(
      Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) _flush();
      }),
    );
    unawaited(_flush()); // 启动补发上次未上报完的
  }

  final RefReader _read;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _songId;
  bool _submitted = false;

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }

  Future<void> _onPosition(Duration pos) async {
    // 冷启动恢复（RESTORING）期间的 position 事件不是真实播放，必须忽略
    if (!_read(playerReadyProvider)) return;
    final song = _read(currentSongProvider);
    if (song == null) return;
    if (song.id != _songId) {
      _songId = song.id;
      _submitted = false;
    }
    if (_submitted) return;
    final dur = _read(audioPlayerProvider).duration;
    if (dur == null || dur <= Duration.zero) return;
    if (pos < dur * 0.5 && pos < const Duration(minutes: 2)) return;
    _submitted = true;
    await _report(song.id);
  }

  Future<void> _report(String songId) async {
    final adapter = _read(serverAdapterProvider);
    final serverId = _read(authControllerProvider).activeServerId;
    if (adapter == null ||
        serverId == null ||
        !adapter.capabilities.scrobbling) {
      return;
    }
    try {
      if (await adapter.scrobble(songId)) return;
    } catch (_) {}
    await _enqueue(serverId, songId);
  }

  Future<void> _enqueue(String serverId, String songId) async {
    try {
      final db = await AppDb.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('scrobble_queue', {
        'server_id': serverId,
        'song_id': songId,
        'played_at': now,
        'created_at': now,
      });
    } catch (_) {
      // 存储异常静默（上报失败不应影响播放）
    }
  }

  /// 单条记录最大重试次数；超过后从 pending 队列移除，避免永久阻塞后续记录
  static const _maxRetries = 5;

  /// 指数退避补发：只处理 next_retry_at 到期的记录，成功即删行；
  /// 失败按 1/2/4/8/16 分钟退避，单条不可恢复记录不得阻塞整条队列
  Future<void> _flush() async {
    final adapter = _read(serverAdapterProvider);
    final serverId = _read(authControllerProvider).activeServerId;
    if (adapter == null ||
        serverId == null ||
        !adapter.capabilities.scrobbling) {
      return;
    }
    try {
      final db = await AppDb.instance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await db.query(
        'scrobble_queue',
        where:
            'server_id = ? AND (next_retry_at IS NULL OR next_retry_at <= ?)',
        whereArgs: [serverId, now],
        orderBy: 'created_at ASC',
        limit: 50,
      );
      for (final row in rows) {
        final id = row['id'] as int;
        final retryCount = (row['retry_count'] as int?) ?? 0;
        try {
          final ok = await adapter.scrobble(row['song_id'] as String);
          if (!ok) {
            await _markFailed(db, id, retryCount, 'server rejected');
            return; // 服务端拒绝：本轮停止，队列原样保留（到期记录除外）
          }
          await db.delete('scrobble_queue', where: 'id = ?', whereArgs: [id]);
        } catch (e) {
          await _markFailed(db, id, retryCount, e.toString());
          return; // 网络/服务端异常：本轮停止
        }
      }
    } catch (_) {}
  }

  Future<void> _markFailed(
    Database db,
    int id,
    int retryCount,
    String error,
  ) async {
    if (retryCount + 1 >= _maxRetries) {
      // 超过最大重试次数：归档（移出 pending 队列），不再无限重试
      await db.delete('scrobble_queue', where: 'id = ?', whereArgs: [id]);
      return;
    }
    final backoffMinutes = 1 << retryCount; // 1/2/4/8/16 分钟指数退避
    try {
      await db.update(
        'scrobble_queue',
        {
          'retry_count': retryCount + 1,
          'last_error': error.length > 200 ? error.substring(0, 200) : error,
          'next_retry_at': DateTime.now()
              .add(Duration(minutes: backoffMinutes))
              .millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }
}

final scrobbleServiceProvider = Provider<ScrobbleService>((ref) {
  final service = ScrobbleService(ref.read);
  ref.onDispose(service.dispose);
  return service;
});
