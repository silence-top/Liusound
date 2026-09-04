import 'dart:typed_data';

import '../models/models.dart';
import '../settings/streaming_prefs.dart';
import 'server_type.dart';

abstract class ServerAdapter {
  ServerType get type;
  AdapterCapabilities get capabilities;

  Future<List<Album>> fetchAlbums(AlbumQuery query);
  Future<List<Song>> fetchSongs(SongQuery query);
  Future<List<Song>> fetchAlbumSongs(String albumId);
  Future<List<Album>> fetchArtistAlbums(String artistId);
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30});
  Future<List<Playlist>> fetchPlaylists();
  Future<List<Song>> fetchPlaylistSongs(String playlistId);
  Future<List<Song>> fetchLikedSongs({int limit = 100});
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20});

  /// 歌手简介；后端不支持或没写简介时返回 null（UI 据此隐藏分区）
  Future<String?> fetchArtistBio(String artistId);

  Future<SearchResult> search(String query);
  Future<int> fetchSongCount();

  Future<bool> setStar(String id, bool starred);
  Future<bool> setRating(String id, int rating);
  Future<bool> addToPlaylist(String playlistId, String songId);

  /// Scrobble 完成上报（播放达 50%/2min 或播完）；后端不支持返回 false
  Future<bool> scrobble(String songId) => Future.value(false);

  /// 上报「正在播放」；后端不支持返回 false
  Future<bool> nowPlaying(String songId) => Future.value(false);

  /// 曲库变更标记（增量同步用，越轻量越好）。
  /// 返回 null 表示后端不提供（如 Audio Station），调用方需全量刷新
  Future<String?> libraryVersion() async => null;

  /// 在服务端新建一个空歌单；成功返回 true。
  /// 调用方自行 invalidate 歌单列表刷新，本方法不负责回传新歌单
  Future<bool> createPlaylist(String name);

  /// [quality] 为当前网络的质量提示；null 或 lossless 时返回原始流。
  /// 支持转码的后端（capabilities.transcoding）按提示追加服务端转码参数
  Future<PlaybackSource> resolveStream(Song song, {QualityHint? quality});
  Future<PlaybackSource> resolveDownload(Song song);
  ImageSource? coverImage(String albumId, {int size = 300});
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64});

  Future<bool> validateSession();
  void dispose();
}

class PlaybackSource {
  const PlaybackSource({required this.url, this.headers = const {}});
  final String url;
  final Map<String, String> headers;
}

class ImageSource {
  const ImageSource({required this.url, this.headers = const {}});
  final String url;
  final Map<String, String> headers;
}

class AuthRequest {
  const AuthRequest({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.deviceId = '',
    this.extra = const {},
  });
  final String serverUrl;
  final String username;
  final String password;
  final String deviceId;
  final Map<String, String> extra;
}

class AdapterSession {
  const AdapterSession({
    required this.secrets,
    this.meta = const {},
    this.displayName,
  });
  final Map<String, String> secrets;
  final Map<String, String> meta;
  final String? displayName;
}

class AdapterCapabilities {
  const AdapterCapabilities({
    this.ratings = false,
    this.similarSongs = false,
    this.likedSongs = true,
    this.download = true,
    this.lyrics = true,
    this.artistBio = false,
    this.transcoding = false,
    this.scrobbling = false,
    this.incrementalSync = false,
  });
  final bool ratings;
  final bool similarSongs;
  final bool likedSongs;
  final bool download;
  final bool lyrics;

  /// 服务端是否提供歌手简介（Audio Station 等无此接口）
  final bool artistBio;

  /// 服务端是否支持按码率/格式转码（附录·四 音质分档的前提）
  final bool transcoding;

  /// 服务端是否支持 Scrobble 上报（Audio Station 无接口）
  final bool scrobbling;

  /// 服务端是否提供曲库变更标记（增量同步的前提）
  final bool incrementalSync;
}

enum AlbumSort { recentlyAdded, recentlyPlayed, mostPlayed, random, name, year }

class AlbumQuery {
  const AlbumQuery({
    required this.sort,
    this.start = 0,
    this.limit = 20,
    this.seed,
    this.artistId,
    this.descending = true,
  });
  final AlbumSort sort;
  final int start;
  final int limit;
  final String? seed;
  final String? artistId;
  final bool descending;
}

enum SongSort {
  title,
  random,
  rating,
  recentlyAdded,
  recentlyPlayed,
  mostPlayed,
  track,
}

class SongQuery {
  const SongQuery({
    this.sort,
    this.start = 0,
    this.limit = 50,
    this.seed,
    this.artistId,
    this.albumId,
    this.starredOnly = false,
  });
  final SongSort? sort;
  final int start;
  final int limit;
  final String? seed;
  final String? artistId;
  final String? albumId;
  final bool starredOnly;
}
