import 'dart:typed_data';

import '../models/models.dart';
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
  Future<SearchResult> search(String query);
  Future<int> fetchSongCount();

  Future<bool> setStar(String id, bool starred);
  Future<bool> setRating(String id, int rating);
  Future<bool> addToPlaylist(String playlistId, String songId);

  Future<PlaybackSource> resolveStream(Song song);
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
  });
  final bool ratings;
  final bool similarSongs;
  final bool likedSongs;
  final bool download;
  final bool lyrics;
}

enum AlbumSort {
  recentlyAdded,
  recentlyPlayed,
  mostPlayed,
  random,
  name,
  year,
}

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

enum SongSort { title, random, rating, recentlyAdded, recentlyPlayed, mostPlayed, track }

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
