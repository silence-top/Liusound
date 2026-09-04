import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_adapter.dart';
import '../../core/library/library_sync.dart';
import '../../core/models/models.dart';
import '../auth/auth_controller.dart';

/// 随机 seed：使 random 排序在每次刷新时真正随机（对标 1.x makeSeed）
String makeSeed() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

/// 随机 seed 状态：下拉刷新时更换以触发随机分区重取
final randomSeedProvider = StateProvider<String>((ref) => makeSeed());

/// 首页五分区（参数与 1.x HomeScreen 逐字段对齐）
/// 使用 keepAlive 的 FutureProvider：切 Tab 返回时零网络等待
final latestAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchAlbums(
    const AlbumQuery(sort: AlbumSort.recentlyAdded, limit: 20),
  );
});

/// 最近播放歌曲（首页歌曲列表分区）
final recentlyPlayedSongsProvider = FutureProvider<List<Song>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchSongs(
    const SongQuery(sort: SongSort.recentlyPlayed, limit: 50),
  );
});

/// 最常播放歌曲（首页歌曲列表分区）
final mostPlayedSongsProvider = FutureProvider<List<Song>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchSongs(
    const SongQuery(sort: SongSort.mostPlayed, limit: 50),
  );
});

final randomAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final seed = ref.watch(randomSeedProvider);
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchAlbums(
    AlbumQuery(sort: AlbumSort.random, limit: 20, seed: seed),
  );
});

/// 每日推荐：随机歌曲 50 首（对标 1.x dailyRecommendResponse）
final dailySongsProvider = FutureProvider<List<Song>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchSongs(const SongQuery(sort: SongSort.random, limit: 50));
});

/// 我的歌单列表（负一屏 + 添加到歌单弹窗共用）
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchPlaylists();
});

/// 专辑内歌曲（详情页按 albumId 异步加载）
final albumSongsProvider = FutureProvider.family<List<Song>, String>((
  ref,
  albumId,
) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchAlbumSongs(albumId);
});

/// 歌单内歌曲（详情页按 playlistId 异步加载）
final playlistSongsProvider = FutureProvider.family<List<Song>, String>((
  ref,
  playlistId,
) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return adapter.fetchPlaylistSongs(playlistId);
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

/// 曲库歌曲列表（负一屏「歌曲」/「本地音乐」入口；走增量同步快照）
final librarySongsProvider = FutureProvider<List<Song>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return LibrarySync.songs(ref.read);
});

/// 专辑列表（负一屏「专辑」入口；走增量同步快照）
final libraryAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return [];
  return LibrarySync.albums(ref.read);
});

/// 艺人专辑（艺人详情页，按发行年降序）
final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<Album>, String>((ref, artistId) async {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return [];
      return adapter.fetchArtistAlbums(artistId);
    });

/// 艺人歌曲（艺人详情页，热门优先）
final artistSongsProvider = FutureProvider.autoDispose
    .family<List<Song>, String>((ref, artistId) async {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return [];
      return adapter.fetchArtistSongs(artistId);
    });
