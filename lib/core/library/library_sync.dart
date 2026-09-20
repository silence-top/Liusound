import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../api/adapter_provider.dart'
    show activeServerIdProvider, serverAdapterProvider;
import '../api/server_adapter.dart';
import '../models/models.dart';
import '../storage/app_db.dart';
import '../platform/isolate_runner.dart';

/// RefReader：统一 Ref / WidgetRef 的 read tear-off
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// 曲库版本快照同步（versionedSnapshot，P0-03 语义正名）：
/// 用服务端轻量变更标记（Subsonic lastModified /
/// Plex updatedAt / Jellyfin+Emby 最新专辑时间+总数）对比本地 SQLite 快照。
/// 标记未变 → 直接读快照（冷启动免全量拉取）；标记变化 → 全量拉取并更新快照。
/// 这是版本快照（Versioned Snapshot），不是 delta 增量同步；
/// 后端不提供标记（versionedSnapshot=false，如 Audio Station）→ 每次全量，如实降级。
abstract final class LibrarySync {
  static final _inFlight = <_LibraryLoadKey, Future<List<Object?>>>{};

  /// 曲库歌曲列表（资料库「歌曲」入口；全量快照，展示顺序由 UI 侧决定）
  static Future<List<Song>> songs(RefReader read) async {
    final adapter = read(serverAdapterProvider);
    if (adapter == null) return <Song>[];
    return _load<Song>(
      adapter: adapter,
      serverId: read(activeServerIdProvider),
      // v2：旧快照可能是 getRandomSongs 随机子集（全库枚举上线前所存），
      // 而 libraryVersion 未变时永远命中旧数据，需换 kind 作废重拉
      kind: 'songs_all_v2',
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
    if (adapter == null) return <Album>[];
    return _load<Album>(
      adapter: adapter,
      serverId: read(activeServerIdProvider),
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

  static Future<List<T>> _load<T>({
    required ServerAdapter adapter,
    required String serverId,
    required String kind,
    required Future<List<T>> Function() fetch,
    required String Function(List<T>) encode,
    required List<T> Function(String) decode,
  }) async {
    // 捕获会话并合并整个任务，失效后不再读取旧 Ref。
    final key = _LibraryLoadKey(adapter, serverId, kind);
    final pending = _inFlight.putIfAbsent(
      key,
      () =>
          _loadSnapshot<T>(
            adapter: adapter,
            serverId: serverId,
            kind: kind,
            fetch: fetch,
            encode: encode,
            decode: decode,
          ).whenComplete(() {
            _inFlight.remove(key);
          }),
    );
    // 调用者会原地排序：只共享在途工作，不共享返回的可变集合。
    return List<T>.of(await (pending as Future<List<T>>));
  }

  static Future<List<T>> _loadSnapshot<T>({
    required ServerAdapter adapter,
    required String serverId,
    required String kind,
    required Future<List<T>> Function() fetch,
    required String Function(List<T>) encode,
    required List<T> Function(String) decode,
  }) async {
    if (!adapter.capabilities.versionedSnapshot) return fetch();
    String? cachedPayload;
    var fetched = false;
    try {
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
      fetched = true;
      final fresh = await fetch();
      // 快照写库失败不能吞掉成功的拉取结果：fresh 已是当前能拿到的最优
      // 数据，直接返回；快照留待下次进入补写
      try {
        await db.insert('library_snapshot', {
          'server_key': serverId,
          'kind': kind,
          'version': current,
          'payload': await _encodePayload(encode, fresh),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {}
      return fresh;
    } catch (_) {
      // 数据库/网络任一环节失败时优先旧快照，避免离线时发起第二次全量请求。
      if (cachedPayload != null) {
        try {
          return await _decodePayload(decode, cachedPayload);
        } catch (_) {}
      }
      // fetch 已失败过一次就不再立即重试：弱网下第二次全量请求只会加倍等待，
      // 直接抛出让调用方进入错误态，由下拉刷新/下次进入重试
      if (fetched) rethrow;
      return fetch();
    }
  }
}

class _LibraryLoadKey {
  const _LibraryLoadKey(this.adapter, this.serverId, this.kind);

  final ServerAdapter adapter;
  final String serverId;
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is _LibraryLoadKey &&
      identical(adapter, other.adapter) &&
      serverId == other.serverId &&
      kind == other.kind;

  @override
  int get hashCode => Object.hash(identityHashCode(adapter), serverId, kind);
}

/// 大 JSON 快照编解码必须在后台 isolate 完成（P0-LIB-01），
/// 避免十万级歌曲列表的 jsonDecode/jsonEncode 阻塞主 isolate
const _payloadIsolateThreshold = 256 * 1024;

Future<List<T>> _decodePayload<T>(
  List<T> Function(String) decode,
  String raw,
) async {
  if (raw.length > _payloadIsolateThreshold) {
    return runInIsolate(() => decode(raw));
  }
  return decode(raw);
}

Future<String> _encodePayload<T>(
  String Function(List<T>) encode,
  List<T> list,
) async {
  // 编码前无法预知 payload 体积，用条目数近似阈值（>1000 条必然 >256KB）
  if (list.length > 1000) {
    return runInIsolate(() => encode(list));
  }
  return encode(list);
}
