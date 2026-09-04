import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/auth/auth_controller.dart';
import '../api/server_adapter.dart';
import '../models/models.dart';
import '../storage/app_db.dart';

/// RefReader：统一 Ref / WidgetRef 的 read tear-off
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// 曲库增量同步（P1）：用服务端轻量变更标记（Subsonic lastModified /
/// Plex updatedAt / Jellyfin+Emby 最新专辑时间+总数）对比本地 SQLite 快照。
/// 标记未变 → 直接读快照（冷启动免全量拉取）；标记变化 → 全量拉取并更新快照。
/// 后端不提供标记（incrementalSync=false，如 Audio Station）→ 每次全量，如实降级。
abstract final class LibrarySync {
  /// 曲库歌曲列表（title 排序前 200）
  static Future<List<Song>> songs(RefReader read) async {
    final adapter = read(serverAdapterProvider);
    if (adapter == null) return const [];
    return _load<Song>(
      read,
      kind: 'songs_title',
      fetch: () =>
          adapter.fetchSongs(const SongQuery(sort: SongSort.title, limit: 200)),
      encode: (list) => jsonEncode(list.map((s) => s.toJson()).toList()),
      decode: (raw) => [
        for (final j in jsonDecode(raw) as List)
          Song.fromJson(j as Map<String, dynamic>),
      ],
    );
  }

  /// 专辑列表（name 排序前 100）
  static Future<List<Album>> albums(RefReader read) async {
    final adapter = read(serverAdapterProvider);
    if (adapter == null) return const [];
    return _load<Album>(
      read,
      kind: 'albums_name',
      fetch: () => adapter.fetchAlbums(
        const AlbumQuery(sort: AlbumSort.name, limit: 100),
      ),
      encode: (list) => jsonEncode(list.map((a) => a.toJson()).toList()),
      decode: (raw) => [
        for (final j in jsonDecode(raw) as List)
          Album.fromJson(j as Map<String, dynamic>),
      ],
    );
  }

  static Future<List<T>> _load<T>(
    RefReader read, {
    required String kind,
    required Future<List<T>> Function() fetch,
    required String Function(List<T>) encode,
    required List<T> Function(String) decode,
  }) async {
    final adapter = read(serverAdapterProvider)!;
    if (!adapter.capabilities.incrementalSync) return fetch();
    try {
      final serverId = read(authControllerProvider).activeServerId ?? 'none';
      final db = await AppDb.instance();
      final rows = await db.query(
        'library_snapshot',
        where: 'server_key = ? AND kind = ?',
        whereArgs: [serverId, kind],
      );
      final cached = rows.isEmpty ? null : rows.first;
      final cachedVersion = cached?['version'] as String?;
      final cachedPayload = cached?['payload'] as String?;

      // 轻量校验（5s 超时）；离线/慢网查不到标记时退回快照
      String? current;
      try {
        current = await adapter.libraryVersion().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        current = null;
      }
      if (cachedPayload != null &&
          current != null &&
          current == cachedVersion) {
        return decode(cachedPayload);
      }
      final fresh = await fetch();
      await db.insert('library_snapshot', {
        'server_key': serverId,
        'kind': kind,
        'version': current,
        'payload': encode(fresh),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return fresh;
    } catch (_) {
      // 快照链路任何异常（无库/离线且无快照）回退全量拉取，可用性优先
      return fetch();
    }
  }
}
