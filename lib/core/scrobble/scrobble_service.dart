import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      await db.insert('scrobble_queue', {
        'server_id': serverId,
        'song_id': songId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // 存储异常静默（上报失败不应影响播放）
    }
  }

  /// 按时间戳顺序补发；成功即删行，失败保留待下轮（避免重复上报丢失）
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
      final rows = await db.query(
        'scrobble_queue',
        where: 'server_id = ?',
        whereArgs: [serverId],
        orderBy: 'created_at ASC',
        limit: 50,
      );
      for (final row in rows) {
        try {
          final ok = await adapter.scrobble(row['song_id'] as String);
          if (!ok) return;
          await db.delete(
            'scrobble_queue',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {
          return; // 网络/服务端异常：本轮停止，队列原样保留
        }
      }
    } catch (_) {}
  }
}

final scrobbleServiceProvider = Provider<ScrobbleService>((ref) {
  final service = ScrobbleService(ref.read);
  ref.onDispose(service.dispose);
  return service;
});
