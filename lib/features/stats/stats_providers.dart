import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/adapter_provider.dart' show activeServerIdProvider;
import '../../core/history/play_history.dart';

/// 听歌统计（本地 play_history 表，按当前服务器隔离）；
/// watch activeServerIdProvider → 切服自动重取
final statsSummaryProvider = FutureProvider<StatsSummary?>((ref) async {
  final serverId = ref.watch(activeServerIdProvider);
  if (serverId.isEmpty) return null;
  return PlayHistory.summary(serverId);
});

final statsTopSongsProvider = FutureProvider<List<TopSongRow>>((ref) async {
  final serverId = ref.watch(activeServerIdProvider);
  if (serverId.isEmpty) return const [];
  return PlayHistory.topSongs(serverId, limit: 20);
});

final statsTopArtistsProvider = FutureProvider<List<TopArtistRow>>((ref) async {
  final serverId = ref.watch(activeServerIdProvider);
  if (serverId.isEmpty) return const [];
  return PlayHistory.topArtists(serverId, limit: 10);
});
