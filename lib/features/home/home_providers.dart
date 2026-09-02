import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../auth/auth_controller.dart';

/// 随机 seed：使 Navidrome 的 random 排序在每次刷新时真正随机（对标 1.x makeSeed）
String makeSeed() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

/// 随机 seed 状态：下拉刷新时更换以触发随机分区重取
final randomSeedProvider = StateProvider<String>((ref) => makeSeed());

/// 首页五分区（参数与 1.x HomeScreen 逐字段对齐）
/// 使用 keepAlive 的 FutureProvider：切 Tab 返回时零网络等待
final latestAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getAlbums(const {
    '_start': 0,
    '_end': 20,
    '_sort': 'recently_added',
    '_order': 'DESC',
  });
});

final recentlyPlayedProvider = FutureProvider<List<Album>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getAlbums(const {
    '_start': 0,
    '_end': 20,
    '_sort': 'play_date',
    '_order': 'DESC',
    'recently_played': true,
  });
});

final mostPlayedProvider = FutureProvider<List<Album>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getAlbums(const {
    '_start': 0,
    '_end': 20,
    '_sort': 'play_count',
    '_order': 'DESC',
  });
});

final randomAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final seed = ref.watch(randomSeedProvider);
  final client = ref.watch(navidromeClientProvider);
  return client.getAlbums({
    '_start': 0,
    '_end': 20,
    '_sort': 'random',
    '_order': 'ASC',
    'seed': seed,
  });
});

/// 每日推荐：随机歌曲 50 首（对标 1.x dailyRecommendResponse）
final dailySongsProvider = FutureProvider<List<Song>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getSongs(const {
    '_start': 0,
    '_end': 50,
    '_sort': 'random',
    '_order': 'ASC',
  });
});

/// 我的歌单列表（负一屏 + 添加到歌单弹窗共用）
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getPlaylists();
});

/// 专辑内歌曲（详情页按 albumId 异步加载）
final albumSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, albumId) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getAlbumSongs(albumId);
});

/// 歌单内歌曲（详情页按 playlistId 异步加载）
final playlistSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, playlistId) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getPlaylistSongs(playlistId);
});

/// 曲库歌曲总数（负一屏服务器卡片展示）
final songTotalProvider = FutureProvider<int>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getSongTotal();
});

/// 我喜欢的歌曲（负一屏入口）
final likedSongsProvider = FutureProvider<List<Song>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getLikedSongs();
});

/// 曲库歌曲列表（负一屏「歌曲」/「本地音乐」入口）
final librarySongsProvider = FutureProvider<List<Song>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getSongs(const {
    '_start': 0,
    '_end': 200,
    '_sort': 'title',
  });
});

/// 专辑列表（负一屏「专辑」入口）
final libraryAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final client = ref.watch(navidromeClientProvider);
  return client.getAlbums(const {
    '_start': 0,
    '_end': 100,
    '_sort': 'name',
  });
});
