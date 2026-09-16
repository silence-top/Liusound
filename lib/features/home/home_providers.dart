import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/server_adapter.dart';
import '../../core/library/library_sync.dart';
import '../../core/library/song_sorting.dart';
import '../../core/models/models.dart';
import '../../core/settings/prefs.dart';
import '../auth/auth_controller.dart';

/// 随机 seed：使 random 排序在每次刷新时真正随机（对标 1.x makeSeed）
String makeSeed() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

/// 随机 seed 状态：下拉刷新时更换以触发随机分区重取
final randomSeedProvider = StateProvider<String>((ref) => makeSeed());

/// 首页分区快照规格：磁盘缓存 key 前缀 + 拉取闭包 + 序列化对
class SectionSpec<T> {
  const SectionSpec({
    required this.cacheKey,
    required this.fetch,
    required this.encode,
    required this.decode,
  });

  /// 缓存 key 前缀，实际 key 为 '$cacheKey.$serverId'（多服务器数据隔离）
  final String cacheKey;

  /// 从服务器拉取本分区数据（read 用于读取 seed 等关联 provider）
  final Future<List<T>> Function(RefReader read, ServerAdapter adapter) fetch;
  final Map<String, dynamic> Function(T item) encode;
  final T Function(Map<String, dynamic> json) decode;
}

/// 首页分区控制器（SWR）：进入首页先同步回放磁盘快照（无加载圈），
/// 再每次进入后台重取最新数据；拉取失败保留旧数据不闪错误态。
/// 根因修复：旧 FutureProvider 是纯内存态，冷启动必然整轮转圈等网络
abstract class HomeSectionController<T> extends Notifier<AsyncValue<List<T>>> {
  SectionSpec<T> get spec;

  @override
  AsyncValue<List<T>> build() {
    final serverId = ref.watch(activeServerIdProvider);
    // watch 适配器：网络设置变更重建 adapter 时照旧整体重取（对齐旧 FutureProvider）
    ref.watch(serverAdapterProvider);
    List<T>? cached;
    try {
      final raw = ref
          .watch(sharedPrefsProvider)
          .getString('${spec.cacheKey}.$serverId');
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(spec.decode)
            .toList(growable: false);
        if (list.isNotEmpty) cached = list;
      }
    } catch (_) {
      // 快照损坏视为无缓存：走正常 loading → 拉取
    }
    // 首取推迟到 build 完成后（build 期同步改 state 会被 Riverpod 拒绝）
    Future.microtask(_fetch);
    final snapshot = cached;
    if (snapshot == null) return AsyncValue<List<T>>.loading();
    return AsyncValue.data(snapshot);
  }

  Future<void> _fetch() async {
    final serverId = ref.read(activeServerIdProvider);
    final adapter = ref.read(serverAdapterProvider);
    final List<T> fresh;
    try {
      fresh = adapter == null ? const [] : await spec.fetch(ref.read, adapter);
    } catch (e, st) {
      // 拉取失败：有缓存则静默保留旧数据，完全无缓存才进错误态
      if (state.isLoading) state = AsyncValue<List<T>>.error(e, st);
      return;
    }
    // 等待网络期间切服：丢弃旧服数据，避免覆盖新服快照回放
    if (serverId != ref.read(activeServerIdProvider)) return;
    state = AsyncValue<List<T>>.data(fresh);
    _persist(fresh, serverId);
  }

  Future<void> _persist(List<T> list, String serverId) async {
    try {
      await ref
          .read(sharedPrefsProvider)
          .setString(
            '${spec.cacheKey}.$serverId',
            jsonEncode(list.map(spec.encode).toList(growable: false)),
          );
    } catch (_) {
      // 快照写盘失败静默：内存数据已生效，下次成功拉取再补
    }
  }
}

/// 首页分区 provider 类型别名：状态为 AsyncValue，快照回放 + 后台刷新
typedef HomeSectionProvider<T> =
    NotifierProvider<HomeSectionController<T>, AsyncValue<List<T>>>;

/// 首页五分区（参数与 1.x HomeScreen 逐字段对齐），均走 SWR 控制器
final latestAlbumsProvider = HomeSectionProvider<Album>(
  LatestAlbumsController.new,
);

class LatestAlbumsController extends HomeSectionController<Album> {
  @override
  SectionSpec<Album> get spec => SectionSpec(
    cacheKey: 'home.latestAlbums',
    fetch: (read, adapter) => adapter.fetchAlbums(
      const AlbumQuery(sort: AlbumSort.recentlyAdded, limit: 20),
    ),
    encode: (a) => a.toJson(),
    decode: Album.fromJson,
  );
}

/// 最近播放歌曲（首页歌曲列表分区）
final recentlyPlayedSongsProvider = HomeSectionProvider<Song>(
  RecentlyPlayedSongsController.new,
);

class RecentlyPlayedSongsController extends HomeSectionController<Song> {
  @override
  SectionSpec<Song> get spec => SectionSpec(
    cacheKey: 'home.recentlyPlayed',
    fetch: (read, adapter) => adapter.fetchSongs(
      const SongQuery(sort: SongSort.recentlyPlayed, limit: 50),
    ),
    encode: (s) => s.toJson(),
    decode: Song.fromJson,
  );
}

/// 最常播放歌曲（首页歌曲列表分区）
final mostPlayedSongsProvider = HomeSectionProvider<Song>(
  MostPlayedSongsController.new,
);

class MostPlayedSongsController extends HomeSectionController<Song> {
  @override
  SectionSpec<Song> get spec => SectionSpec(
    cacheKey: 'home.mostPlayed',
    fetch: (read, adapter) => adapter.fetchSongs(
      const SongQuery(sort: SongSort.mostPlayed, limit: 50),
    ),
    encode: (s) => s.toJson(),
    decode: Song.fromJson,
  );
}

final randomAlbumsProvider = HomeSectionProvider<Album>(
  RandomAlbumsController.new,
);

class RandomAlbumsController extends HomeSectionController<Album> {
  @override
  SectionSpec<Album> get spec => SectionSpec(
    cacheKey: 'home.randomAlbums',
    fetch: (read, adapter) => adapter.fetchAlbums(
      AlbumQuery(
        sort: AlbumSort.random,
        limit: 20,
        seed: read(randomSeedProvider),
      ),
    ),
    encode: (a) => a.toJson(),
    decode: Album.fromJson,
  );
}

/// 每日推荐：随机歌曲 50 首（对标 1.x dailyRecommendResponse）
final dailySongsProvider = HomeSectionProvider<Song>(DailySongsController.new);

class DailySongsController extends HomeSectionController<Song> {
  @override
  SectionSpec<Song> get spec => SectionSpec(
    cacheKey: 'home.dailySongs',
    fetch: (read, adapter) =>
        adapter.fetchSongs(const SongQuery(sort: SongSort.random, limit: 50)),
    encode: (s) => s.toJson(),
    decode: Song.fromJson,
  );
}

/// 我的歌单列表（负一屏 + 添加到歌单弹窗共用）
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchPlaylists();
});

/// 专辑内歌曲（详情页按 albumId 异步加载）；autoDispose 防止长会话按 id 累积缓存
final albumSongsProvider = FutureProvider.autoDispose
    .family<List<Song>, String>((ref, albumId) async {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return [];
      return adapter.fetchAlbumSongs(albumId);
    });

/// 歌单内歌曲（详情页按 playlistId 异步加载）；autoDispose 同上
final playlistSongsProvider = FutureProvider.autoDispose
    .family<List<Song>, String>((ref, playlistId) async {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return [];
      return adapter.fetchPlaylistSongs(playlistId);
    });

/// 歌单拼贴封面：前 4 首歌的去重专辑 id（资料库歌单行 2×2 封面用）。
/// 会话级缓存（非 autoDispose）：每次进资料库都要为每个歌单拉一次全量
/// 曲目只为取 4 个专辑 id，重复进入不再重发；watch 服务器 id，切服即失效
final playlistCoverIdsProvider = FutureProvider.family<List<String>, String>((
  ref,
  playlistId,
) async {
  ref.watch(activeServerIdProvider);
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  final songs = await adapter.fetchPlaylistSongs(playlistId);
  final ids = <String>[];
  for (final s in songs) {
    if (ids.contains(s.albumId)) continue;
    ids.add(s.albumId);
    if (ids.length == 4) break;
  }
  return ids;
});

/// 曲库歌曲总数（负一屏服务器卡片展示）
final songTotalProvider = FutureProvider<int>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return 0;
  return adapter.fetchSongCount();
});

/// 我喜欢的歌曲（负一屏入口）
final likedSongsProvider = FutureProvider<List<Song>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchLikedSongs();
});

/// 曲库歌曲列表（资料库「歌曲」入口；全量快照，默认按加入时间倒序）
final librarySongsProvider = FutureProvider<List<Song>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  final songs = await LibrarySync.songs(ref.read);
  // 加入时间倒序（ISO8601 同源字符串可直接比较）；无入库时间的沉底按标题排
  int fallback(Song a, Song b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  songs.sort((a, b) {
    final ta = a.created;
    final tb = b.created;
    if (ta == null && tb == null) return fallback(a, b);
    if (ta == null) return 1;
    if (tb == null) return -1;
    final cmp = tb.compareTo(ta);
    return cmp != 0 ? cmp : fallback(a, b);
  });
  return songs;
});

/// 歌曲列表排序偏好（全局记忆，应用级存活）：
/// null = 各列表保持原始顺序（歌单的服务端编排顺序等）；选择后全列表生效并持久化
class SongSortController extends Notifier<SongSortPref?> {
  static const _key = 'songList.sort.v1';

  @override
  SongSortPref? build() {
    // 持久化读取推迟到 build 完成后（build 期同步改 state 会被 Riverpod 拒绝）；
    // Notifier 与 App 同生命周期，异步回来直接赋值安全
    Future.microtask(() async {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final parts = raw.split(':');
      final field = SongSort.values
          .where((v) => v.name == parts[0])
          .firstOrNull;
      if (field == null || !kSortableSongFields.contains(field)) return;
      state = SongSortPref(
        field: field,
        ascending: parts.elementAtOrNull(1) == 'asc',
      );
    });
    return null;
  }

  Future<void> set(SongSortPref? pref) async {
    state = pref;
    final prefs = await SharedPreferences.getInstance();
    if (pref == null) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      '${pref.field.name}:${pref.ascending ? 'asc' : 'desc'}',
    );
  }
}

final songSortPrefProvider =
    NotifierProvider<SongSortController, SongSortPref?>(SongSortController.new);

/// 专辑列表（负一屏「专辑」入口；走增量同步快照）
final libraryAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return LibrarySync.albums(ref.read);
});

/// 资料库专辑分页状态（滚动加载）
class AlbumPagedState {
  const AlbumPagedState({
    this.albums = const [],
    this.loading = true,
    this.error = false,
    this.noMore = false,
  });

  final List<Album> albums;
  final bool loading;
  final bool error;
  final bool noMore;

  AlbumPagedState copyWith({
    List<Album>? albums,
    bool? loading,
    bool? error,
    bool? noMore,
  }) => AlbumPagedState(
    albums: albums ?? this.albums,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    noMore: noMore ?? this.noMore,
  );
}

/// 专辑列表分页控制器：fetchAlbums 原生支持 start/limit，
/// 用真 offset 追加翻页（区别于艺人歌曲的累计 limit 重取策略）。
class LibraryAlbumsController extends AutoDisposeNotifier<AlbumPagedState> {
  static const _pageSize = 60;

  @override
  AlbumPagedState build() {
    // 首取推迟到 build 完成后（build 期同步改 state 会被 Riverpod 拒绝）
    Future.microtask(() => _fetch());
    return const AlbumPagedState();
  }

  Future<void> _fetch() async {
    final adapter = ref.read(serverAdapterProvider);
    state = state.copyWith(loading: true, error: false);
    try {
      final fetched = adapter == null
          ? const <Album>[]
          : await adapter.fetchAlbums(
              AlbumQuery(
                sort: AlbumSort.name,
                start: state.albums.length,
                limit: _pageSize,
              ),
            );
      state = state.copyWith(
        albums: [...state.albums, ...fetched],
        loading: false,
        noMore: fetched.length < _pageSize,
      );
    } catch (_) {
      state = state.copyWith(loading: false, error: true);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.error || state.noMore) return;
    await _fetch();
  }

  Future<void> retry() => _fetch();
}

final libraryAlbumsPagedProvider =
    NotifierProvider.autoDispose<LibraryAlbumsController, AlbumPagedState>(
      LibraryAlbumsController.new,
    );

/// 语义约定（P0-04）：null = 后端不支持该能力（入口隐藏）；
/// 请求失败直接 rethrow（AsyncError，UI 显示失败态，与「不支持」严格区分）。
/// 歌手列表（资料库入口）
final artistsProvider = FutureProvider<List<Artist>?>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return null;
  return adapter.fetchArtists();
});

/// 专辑艺术家列表（资料库入口；null = 后端不支持该能力）
final albumArtistsProvider = FutureProvider<List<Artist>?>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return null;
  return adapter.fetchAlbumArtists();
});

/// 流派列表（资料库入口；null = 后端不支持该能力）
final genresProvider = FutureProvider<List<Genre>?>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return null;
  return adapter.fetchGenres();
});

/// 电台列表（资料库入口；null = 后端不支持该能力）
final radioStationsProvider = FutureProvider<List<RadioStation>?>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return null;
  return adapter.fetchRadioStations();
});

/// 流派歌曲（流派二级页复用 SongListScreen；不支持流派歌曲的
/// 后端返回空列表，由页面空态兜底）
final genreSongsProvider = FutureProvider.autoDispose
    .family<List<Song>, String>((ref, genre) async {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return const [];
      return await adapter.fetchGenreSongs(genre) ?? const [];
    });

/// 艺人专辑（艺人详情页，按发行年降序）
final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<Album>, String>((ref, artistId) async {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return [];
      return adapter.fetchArtistAlbums(artistId);
    });

/// 艺人歌曲（艺人详情页，热门优先）分页状态
class ArtistSongsState {
  const ArtistSongsState({
    this.songs = const [],
    this.loading = true,
    this.error = false,
    this.noMore = false,
    this.limit = 30,
  });

  final List<Song> songs;
  final bool loading;
  final bool error;
  final bool noMore;
  final int limit;

  ArtistSongsState copyWith({
    List<Song>? songs,
    bool? loading,
    bool? error,
    bool? noMore,
    int? limit,
  }) => ArtistSongsState(
    songs: songs ?? this.songs,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    noMore: noMore ?? this.noMore,
    limit: limit ?? this.limit,
  );
}

/// 艺人歌曲分页控制器：「加载更多」采用累计 limit 策略——部分后端
/// （如 Subsonic getTopSongs）没有 offset，只能放大 count 重取后按 id 去重合并；
/// 返回条数少于请求量或没有新增时判定无更多。
class ArtistSongsController
    extends AutoDisposeFamilyNotifier<ArtistSongsState, String> {
  static const _pageSize = 30;

  @override
  ArtistSongsState build(String arg) {
    // 不能在 build() 返回前同步读写 state（Riverpod 会抛
    // StateError 且请求被吞掉，页面将永远停在初始 loading 态），
    // 因此用 microtask 把首取推迟到 build 完成之后。
    Future.microtask(() => _fetch(_pageSize));
    return const ArtistSongsState();
  }

  Future<void> _fetch(int limit) async {
    final adapter = ref.read(serverAdapterProvider);
    state = state.copyWith(loading: true, error: false, limit: limit);
    final prevCount = state.songs.length;
    try {
      final fetched = adapter == null
          ? const <Song>[]
          : await adapter.fetchArtistSongs(arg, limit: limit);
      final merged = <String, Song>{
        for (final s in state.songs) s.id: s,
        for (final s in fetched) s.id: s,
      };
      final songs = merged.values.toList(growable: false);
      state = state.copyWith(
        songs: songs,
        loading: false,
        noMore: fetched.length < limit || songs.length == prevCount,
      );
    } catch (_) {
      state = state.copyWith(loading: false, error: true);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.error || state.noMore) return;
    await _fetch(state.limit + _pageSize);
  }

  Future<void> retry() => _fetch(state.limit);
}

final artistSongsProvider = NotifierProvider.autoDispose
    .family<ArtistSongsController, ArtistSongsState, String>(
      ArtistSongsController.new,
    );
