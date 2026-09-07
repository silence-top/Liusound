import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/auth/auth_controller.dart';
import '../api/server_adapter.dart';
import '../models/models.dart';
import '../storage/app_db.dart';

/// RefReader：统一 Ref / WidgetRef 的 read tear-off
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// 曲库版本快照同步（versionedSnapshot，P0-03 语义正名）：
/// 用服务端轻量变更标记（Subsonic lastModified /
/// Plex updatedAt / Jellyfin+Emby 最新专辑时间+总数）对比本地 SQLite 快照。
/// 标记未变 → 直接读快照（冷启动免全量拉取）；标记变化 → 全量拉取并更新快照。
/// 这是版本快照（Versioned Snapshot），不是 delta 增量同步；
/// 后端不提供标记（versionedSnapshot=false，如 Audio Station）→ 每次全量，如实降级。
abstract final class LibrarySync {
  /// 曲库歌曲列表（资料库「歌曲」入口；全量快照，展示顺序由 UI 侧决定）
  static Future<List<Song>> songs(RefReader read) async {
    final adapter = read(serverAdapterProvider);
    if (adapter == null) return const [];
    return _load<Song>(
      read,
      kind: 'songs_all',
      fetch: () => adapter.fetchSongs(
        const SongQuery(sort: SongSort.title, limit: 100000),
      ),
      encode: (list) => jsonEncode(list.map((s) => s.toJson()).toList()),
      decode: (raw) => [
        for (final j in jsonDecode(raw) as List)
          Song.fromJson(j as Map<String, dynamic>),
      ],
    );
  }

  /// 专辑列表（全量 name 排序；上限 10000 对齐歌曲入口，
  /// 大曲库分页待专辑列表页支持加载更多后再拆）
  static Future<List<Album>> albums(RefReader read) async {
    final adapter = read(serverAdapterProvider);
    if (adapter == null) return const [];
    return _load<Album>(
      read,
      kind: 'albums_name_v2', // v2：上限 100→10000，旧快照只有 100 条需作废
      fetch: () => adapter.fetchAlbums(
        const AlbumQuery(sort: AlbumSort.name, limit: 10000),
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
    if (!adapter.capabilities.versionedSnapshot) return fetch();
    String? cachedPayload;
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
      cachedPayload = cached?['payload'] as String?;

      // 轻量校验（5s 超时）；离线/慢网查不到标记时退回快照
      String? current;
      try {
        current = await adapter.libraryVersion().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        current = null;
      }
      // 弱网或离线时版本标记不可用，已有快照就是最可靠的可用数据。
      if (cachedPayload != null &&
          (current == null || current == cachedVersion)) {
        return await _decodePayload(decode, cachedPayload);
      }
      final fresh = await fetch();
      await db.insert('library_snapshot', {
        'server_key': serverId,
        'kind': kind,
        'version': current,
        'payload': await _encodePayload(encode, fresh),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return fresh;
    } catch (_) {
      // 数据库/网络任一环节失败时优先旧快照，避免离线时发起第二次全量请求。
      if (cachedPayload != null) {
        try {
          return await _decodePayload(decode, cachedPayload);
        } catch (_) {}
      }
      return fetch();
    }
  }
}

/// 大 JSON 快照编解码必须在后台 isolate 完成（P0-LIB-01），
/// 避免十万级歌曲列表的 jsonDecode/jsonEncode 阻塞主 isolate
const _payloadIsolateThreshold = 256 * 1024;

Future<List<T>> _decodePayload<T>(
  List<T> Function(String) decode,
  String raw,
) async {
  if (raw.length > _payloadIsolateThreshold) {
    return Isolate.run(() => decode(raw));
  }
  return decode(raw);
}

Future<String> _encodePayload<T>(
  String Function(List<T>) encode,
  List<T> list,
) async {
  // 编码前无法预知 payload 体积，用条目数近似阈值（>1000 条必然 >256KB）
  if (list.length > 1000) {
    return Isolate.run(() => encode(list));
  }
  return encode(list);
}
