import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/adapter_provider.dart' show activeServerIdProvider;
import '../models/models.dart';
import '../storage/app_db.dart';
import '../../features/player/player_controller.dart';

/// RefReader：统一 Ref / WidgetRef 的 read tear-off
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// 本地播放历史（听歌统计 / 私人 FM 去重）：
/// 每首歌每次实际播放（达 20 秒或时长一半，先到为准）记一行，
/// 歌名/歌手/专辑做快照——歌曲从曲库删除后历史仍可读。
/// 全后端统一记录（服务端无播放计数的 fnOS/Audio Station 也有统计）。
abstract final class PlayHistory {
  /// 单次播放的最小有效时长门槛（时长 < 40s 的短音频按一半算）
  static Duration _threshold(Duration dur) => dur >= const Duration(seconds: 40)
      ? const Duration(seconds: 20)
      : dur * 0.5;

  /// 历史最大保留行数（超限裁最旧，避免 DB 无限膨胀）
  static const _maxRows = 20000;

  static int _insertsSincePrune = 0;

  static Future<void> record({
    required String serverId,
    required Song song,
    required int durationMs,
  }) async {
    try {
      final db = await AppDb.instance();
      await db.insert('play_history', {
        'server_id': serverId,
        'song_id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'album_id': song.albumId,
        'duration_ms': durationMs,
        'played_at': DateTime.now().millisecondsSinceEpoch,
      });
      _insertsSincePrune++;
      if (_insertsSincePrune >= 100) {
        _insertsSincePrune = 0;
        await db.execute(
          'DELETE FROM play_history WHERE id NOT IN '
          '(SELECT id FROM play_history ORDER BY played_at DESC LIMIT $_maxRows)',
        );
      }
    } catch (_) {
      // 历史记录失败不影响播放
    }
  }

  /// 近 [days] 天播放过的歌曲 id（FM 抽歌排除用）
  static Future<Set<String>> recentSongIds(
    String serverId, {
    int days = 7,
  }) async {
    try {
      final db = await AppDb.instance();
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;
      final rows = await db.query(
        'play_history',
        columns: ['song_id'],
        where: 'server_id = ? AND played_at >= ?',
        whereArgs: [serverId, since],
      );
      return rows.map((r) => r['song_id'] as String).toSet();
    } catch (_) {
      return const {};
    }
  }

  static Future<StatsSummary> summary(String serverId) async {
    final db = await AppDb.instance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final day7 = now - 7 * 86400000;
    final day30 = now - 30 * 86400000;
    Future<int> count(String where, List<Object?> args) async {
      final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM play_history WHERE server_id = ? AND $where',
        [serverId, ...args],
      );
      return (r.first['c'] as int?) ?? 0;
    }

    final totals = await db.rawQuery(
      'SELECT COUNT(*) c, IFNULL(SUM(duration_ms), 0) ms,'
      ' COUNT(DISTINCT song_id) songs FROM play_history WHERE server_id = ?',
      [serverId],
    );
    return StatsSummary(
      totalPlays: (totals.first['c'] as int?) ?? 0,
      totalDurationMs: (totals.first['ms'] as int?) ?? 0,
      uniqueSongs: (totals.first['songs'] as int?) ?? 0,
      plays7d: await count('played_at >= ?', [day7]),
      plays30d: await count('played_at >= ?', [day30]),
    );
  }

  /// 按播放次数排序的最常听歌曲
  static Future<List<TopSongRow>> topSongs(
    String serverId, {
    int limit = 20,
  }) async {
    final db = await AppDb.instance();
    final rows = await db.rawQuery(
      'SELECT song_id, title, artist, album_id, COUNT(*) c'
      ' FROM play_history WHERE server_id = ?'
      ' GROUP BY song_id ORDER BY c DESC, MAX(played_at) DESC LIMIT ?',
      [serverId, limit],
    );
    return rows
        .map(
          (r) => TopSongRow(
            songId: r['song_id'] as String,
            title: r['title'] as String? ?? '',
            artist: r['artist'] as String? ?? '',
            albumId: r['album_id'] as String? ?? '',
            plays: (r['c'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// 按播放次数排序的最爱歌手（同名合并）
  static Future<List<TopArtistRow>> topArtists(
    String serverId, {
    int limit = 10,
  }) async {
    final db = await AppDb.instance();
    final rows = await db.rawQuery(
      'SELECT artist, COUNT(*) c FROM play_history WHERE server_id = ?'
      ' GROUP BY artist ORDER BY c DESC LIMIT ?',
      [serverId, limit],
    );
    return rows
        .map(
          (r) => TopArtistRow(
            artist: r['artist'] as String? ?? '',
            plays: (r['c'] as int?) ?? 0,
          ),
        )
        .toList();
  }
}

class StatsSummary {
  const StatsSummary({
    required this.totalPlays,
    required this.totalDurationMs,
    required this.uniqueSongs,
    required this.plays7d,
    required this.plays30d,
  });

  final int totalPlays;
  final int totalDurationMs;
  final int uniqueSongs;
  final int plays7d;
  final int plays30d;
}

class TopSongRow {
  const TopSongRow({
    required this.songId,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.plays,
  });

  final String songId;
  final String title;
  final String artist;
  final String albumId;
  final int plays;
}

class TopArtistRow {
  const TopArtistRow({required this.artist, required this.plays});

  final String artist;
  final int plays;
}

/// 播放历史记录服务：随 App 存活，监听播放位置，
/// 每首歌每次播放过门槛记一行（ScrobbleService 同款监听模式）
class PlayHistoryService {
  PlayHistoryService(this._read) {
    _subs.add(_read(audioPlayerProvider).positionStream.listen(_onPosition));
  }

  final RefReader _read;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _songId;
  bool _recorded = false;

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }

  Future<void> _onPosition(Duration pos) async {
    // 冷启动恢复（RESTORING）期间的 position 事件不是真实播放
    if (!_read(playerReadyProvider)) return;
    final song = _read(currentSongProvider);
    if (song == null) return;
    if (song.id != _songId) {
      _songId = song.id;
      _recorded = false;
    }
    if (_recorded) return;
    final dur = _read(audioPlayerProvider).duration;
    if (dur == null || dur <= Duration.zero) return;
    if (pos < PlayHistory._threshold(dur)) return;
    _recorded = true;
    await PlayHistory.record(
      serverId: _read(activeServerIdProvider),
      song: song,
      durationMs: dur.inMilliseconds,
    );
  }
}

final playHistoryServiceProvider = Provider<PlayHistoryService>((ref) {
  final service = PlayHistoryService(ref.read);
  ref.onDispose(service.dispose);
  return service;
});
