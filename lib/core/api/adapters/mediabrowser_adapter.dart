import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../server_adapter.dart';

/// Jellyfin / Emby 共享基类（~80% API 相同）。
/// 子类仅需覆写 [authHeaders]（认证头格式）和 [login]（登录流程）。
abstract class MediaBrowserAdapter implements ServerAdapter {
  MediaBrowserAdapter({
    required String serverUrl,
    required Map<String, String> secrets,
  }) : _serverUrl = serverUrl,
       _userId = secrets['userId'] ?? '',
       _token = secrets['token'] ?? '' {
    _dio.options.baseUrl = serverUrl;
  }

  final String _serverUrl;
  final String _userId;
  final String _token;

  String get userId => _userId;
  String get token => _token;
  String get serverUrl => _serverUrl;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// 子类提供每请求认证头（Jellyfin: Token=; Emby: MediaBrowser Token= + X-Emby-Token）
  Map<String, String> get authHeaders;

  /// 客户端标识（子类覆写以区分 Jellyfin / Emby）
  String get clientName;

  /// 从登录响应提取 secrets（子类实现）
  Map<String, String> extractSecrets(Map<String, dynamic> loginResponse);

  // ========== ServerAdapter 接口默认实现 ==========

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
    ratings: false,
    similarSongs: false,
    likedSongs: true,
    download: true,
    lyrics: true,
    artistBio: true,
  );

  @override
  Future<List<Album>> fetchAlbums(AlbumQuery query) async {
    final sort = _albumSort(query.sort);
    final data = await _items({
      'IncludeItemTypes': 'MusicAlbum',
      'SortBy': sort,
      'SortOrder': query.descending ? 'Descending' : 'Ascending',
      'StartIndex': '${query.start}',
      'Limit': '${query.limit}',
      'Recursive': 'true',
      if (query.artistId != null) 'ArtistIds': query.artistId!,
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toAlbum)
        .toList();
  }

  @override
  Future<List<Song>> fetchSongs(SongQuery query) async {
    final params = <String, String>{
      'IncludeItemTypes': 'Audio',
      'StartIndex': '${query.start}',
      'Limit': '${query.limit}',
      'Recursive': 'true',
      'Fields': _songFields,
    };
    if (query.sort != null) {
      params['SortBy'] = switch (query.sort!) {
        SongSort.title => 'SortName',
        SongSort.random => 'Random',
        SongSort.rating => 'CommunityRating',
        SongSort.recentlyAdded => 'DateCreated',
        SongSort.recentlyPlayed => 'DatePlayed',
        SongSort.mostPlayed => 'PlayCount',
        SongSort.track => 'TrackNumber',
      };
      // 时间/热度类排序需要倒序（Jellyfin/Emby 默认升序）
      const descSorts = {
        SongSort.recentlyAdded,
        SongSort.recentlyPlayed,
        SongSort.mostPlayed,
      };
      if (descSorts.contains(query.sort)) params['SortOrder'] = 'Descending';
    }
    if (query.albumId != null) params['AlbumIds'] = query.albumId!;
    if (query.artistId != null) params['ArtistIds'] = query.artistId!;
    if (query.starredOnly) params['IsFavorite'] = 'true';
    final data = await _items(params);
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) async {
    final data = await _items({
      'ParentId': albumId,
      'IncludeItemTypes': 'Audio',
      'SortBy': 'SortName',
      'Fields': _songFields,
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) async {
    final data = await _items({
      'IncludeItemTypes': 'MusicAlbum',
      'ArtistIds': artistId,
      'SortBy': 'ProductionYear',
      'SortOrder': 'Descending',
      'Recursive': 'true',
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toAlbum)
        .toList();
  }

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) async {
    final data = await _items({
      'IncludeItemTypes': 'Audio',
      'ArtistIds': artistId,
      'SortBy': 'CommunityRating',
      'SortOrder': 'Descending',
      'Limit': '$limit',
      'Recursive': 'true',
      'Fields': _songFields,
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final data = await _items({
      'IncludeItemTypes': 'Playlist',
      'Recursive': 'true',
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => Playlist(
            id: _s(e, 'Id'),
            name: _s(e, 'Name', '未命名歌单'),
            songCount: _i(e, 'RunTimeTicks') > 0 ? _i(e, 'ChildCount') : 0,
          ),
        )
        .toList();
  }

  @override
  Future<List<Song>> fetchPlaylistSongs(String playlistId) async {
    final data = await _items({
      'ParentId': playlistId,
      'IncludeItemTypes': 'Audio',
      'Fields': _songFields,
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchLikedSongs({int limit = 100}) async {
    final data = await _items({
      'IncludeItemTypes': 'Audio',
      'IsFavorite': 'true',
      'Limit': '$limit',
      'Recursive': 'true',
      'Fields': _songFields,
    });
    return (data['Items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20}) async =>
      const [];

  @override
  Future<String?> fetchArtistBio(String artistId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Users/$_userId/Items/$artistId',
        queryParameters: const {'Fields': 'Overview'},
        options: Options(headers: _headers),
      );
      final bio = res.data?['Overview']?.toString().trim() ?? '';
      return bio.isEmpty ? null : bio;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> fetchSongCount() async {
    final data = await _items({
      'IncludeItemTypes': 'Audio',
      'Recursive': 'true',
      'Limit': '0',
    });
    return _i(data, 'TotalRecordCount');
  }

  @override
  Future<SearchResult> search(String query) async {
    final data = await _items({
      'SearchTerm': query,
      'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist',
      'Limit': '20',
      'Recursive': 'true',
      'Fields': _songFields,
    });
    final items = data['Items'] as List<dynamic>? ?? const [];
    final songs = <Song>[];
    final albums = <Album>[];
    final artists = <Artist>[];
    for (final e in items) {
      if (e is! Map<String, dynamic>) continue;
      switch (_s(e, 'Type')) {
        case 'Audio':
          songs.add(_toSong(e));
        case 'MusicAlbum':
          albums.add(_toAlbum(e));
        case 'MusicArtist':
          artists.add(
            Artist(
              id: _s(e, 'Id'),
              name: _s(e, 'Name', '未知歌手'),
              albumCount: _i(e, 'AlbumCount'),
              songCount: _i(e, 'SongCount'),
            ),
          );
      }
    }
    return SearchResult(songs: songs, albums: albums, artists: artists);
  }

  @override
  Future<bool> setStar(String id, bool starred) async {
    try {
      if (starred) {
        await _post('/Users/$_userId/FavoriteItems/$id', {});
      } else {
        await _delete('/Users/$_userId/FavoriteItems/$id');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setRating(String id, int rating) async => false;

  @override
  Future<bool> addToPlaylist(String playlistId, String songId) async {
    try {
      await _post('/Playlists/$playlistId/Items', {'Ids': songId});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Jellyfin/Emby 建歌单：Ids 传空数组即建空歌单，
  /// MediaType 必须显式给 Audio，否则服务端按混合媒体处理
  @override
  Future<bool> createPlaylist(String name) async {
    try {
      await _post('/Playlists', {
        'Name': name,
        'Ids': const <String>[],
        'UserId': _userId,
        'MediaType': 'Audio',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PlaybackSource> resolveStream(Song song) async {
    return PlaybackSource(
      url: '$_serverUrl/Audio/${song.id}/universal',
      headers: {...authHeaders, 'Accept': 'audio/*'},
    );
  }

  @override
  Future<PlaybackSource> resolveDownload(Song song) async {
    return PlaybackSource(
      url: '$_serverUrl/Items/${song.id}/Download',
      headers: authHeaders,
    );
  }

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    if (albumId.isEmpty) return null;
    return ImageSource(
      url: '$_serverUrl/Items/$albumId/Images/Primary?maxWidth=$size',
      headers: authHeaders,
    );
  }

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    if (albumId.isEmpty) return null;
    try {
      final url = '$_serverUrl/Items/$albumId/Images/Primary?maxWidth=$size';
      final resp = await _dio.get<Uint8List>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: authHeaders,
        ),
      );
      return resp.data;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateSession() async {
    try {
      await _items({
        'Limit': '1',
        'IncludeItemTypes': 'Audio',
        'Recursive': 'true',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _dio.close();

  // ========== 内部 HTTP ==========

  Map<String, String> get _headers => {
    'X-Emby-Authorization':
        'MediaBrowser Client="$clientName", Device="Flutter", DeviceId="liusound", Version="2.0"',
    ...authHeaders,
  };

  /// 取歌曲时必须显式请求，否则响应里没有 MediaSources（音质徽标的唯一数据源）
  static const String _songFields = 'MediaSources';

  Future<Map<String, dynamic>> _items(Map<String, String> params) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/Users/$_userId/Items',
      queryParameters: params,
      options: Options(headers: _headers),
    );
    return res.data ?? const {};
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: Options(headers: _headers),
    );
    return res.data ?? const {};
  }

  Future<void> _delete(String path) async {
    await _dio.delete(path, options: Options(headers: _headers));
  }

  // ========== JSON 映射 ==========

  Song _toSong(Map<String, dynamic> j) {
    final artistItems = j['ArtistItems'] as List<dynamic>? ?? const [];
    final albums = j['Album'] as String? ?? '';
    final albumId = j['AlbumId'] as String? ?? '';
    final artistId = artistItems.isNotEmpty
        ? artistItems[0]['Id']?.toString() ?? ''
        : '';
    final ticks = _i(j, 'RunTimeTicks');
    final audio = _audioStream(j);
    // Jellyfin/Emby 的 BitRate 单位是 bps，其余后端统一按 kbps 表达
    final bps = _i(audio, 'BitRate');
    return Song(
      id: _s(j, 'Id'),
      title: _s(j, 'Name', '未知歌曲'),
      artist: _s(j, 'Artists') is List
          ? ((j['Artists'] as List).isNotEmpty
                ? j['Artists'][0].toString()
                : '未知歌手')
          : '未知歌手',
      album: albums,
      albumId: albumId,
      artistId: artistId,
      duration: ticks > 0 ? ticks / 10000000 : 0,
      playCount: _i(j, 'PlayCount'),
      starred: _bool(j, 'UserData', 'IsFavorite'),
      size: 0,
      rating: (j['CommunityRating'] as num?)?.toInt() ?? 0,
      suffix: _s(j, 'Container').isEmpty ? null : _s(j, 'Container'),
      codec: _s(audio, 'Codec').isEmpty ? null : _s(audio, 'Codec'),
      bitRate: bps > 0 ? (bps / 1000).round() : null,
      sampleRate: _i(audio, 'SampleRate') > 0 ? _i(audio, 'SampleRate') : null,
      bitDepth: _i(audio, 'BitDepth') > 0 ? _i(audio, 'BitDepth') : null,
    );
  }

  /// MediaSources[].MediaStreams[] 里的第一条音频流；
  /// 未请求 Fields=MediaSources 时返回空 map，各字段自然退化为 null
  static Map<String, dynamic> _audioStream(Map<String, dynamic> j) {
    final sources = j['MediaSources'] as List<dynamic>? ?? const [];
    for (final s in sources) {
      if (s is! Map<String, dynamic>) continue;
      for (final st in s['MediaStreams'] as List<dynamic>? ?? const []) {
        if (st is Map<String, dynamic> && st['Type'] == 'Audio') return st;
      }
    }
    return const {};
  }

  Album _toAlbum(Map<String, dynamic> j) {
    final artistId = (j['AlbumArtists'] as List<dynamic>?)?.isNotEmpty == true
        ? (j['AlbumArtists'] as List)[0]['Id']?.toString() ?? ''
        : '';
    return Album(
      id: _s(j, 'Id'),
      name: _s(j, 'Name', '未知专辑'),
      artist: (j['AlbumArtist'] as String?) ?? '',
      artistId: artistId,
      songCount: _i(j, 'ChildCount'),
      duration: (_i(j, 'RunTimeTicks')) / 10000000,
      playCount: _i(j, 'PlayCount'),
      starred: _bool(j, 'UserData', 'IsFavorite'),
      rating: (j['CommunityRating'] as num?)?.toInt() ?? 0,
      year: _iOrNull(j, 'ProductionYear'),
    );
  }

  static String _s(Map<String, dynamic> j, String k, [String d = '']) =>
      j[k]?.toString() ?? d;
  static int _i(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt() ?? 0;
  static int? _iOrNull(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt();
  static bool _bool(Map<String, dynamic> j, String parent, String key) {
    final ud = j[parent] as Map<String, dynamic>?;
    return ud?[key] == true;
  }

  String _albumSort(AlbumSort sort) => switch (sort) {
    AlbumSort.recentlyAdded => 'DateCreated',
    AlbumSort.recentlyPlayed => 'DatePlayed',
    AlbumSort.mostPlayed => 'PlayCount',
    AlbumSort.random => 'Random',
    AlbumSort.name => 'SortName',
    AlbumSort.year => 'ProductionYear',
  };
}
