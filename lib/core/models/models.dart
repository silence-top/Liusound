// Navidrome REST / Subsonic 数据模型（对标 1.x src/types/api.ts，fromJson 容错缺失字段）

abstract final class _Json {
  static String str(Map<String, dynamic> j, String key, [String fallback = '']) =>
      j[key]?.toString() ?? fallback;

  static int intOf(Map<String, dynamic> j, String key, [int fallback = 0]) =>
      (j[key] as num?)?.toInt() ?? fallback;

  static double doubleOf(Map<String, dynamic> j, String key, [double fallback = 0]) =>
      (j[key] as num?)?.toDouble() ?? fallback;

  static bool boolOf(Map<String, dynamic> j, String key, [bool fallback = false]) =>
      j[key] is bool ? j[key] as bool : fallback;
}

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.artistId,
    required this.duration,
    required this.playCount,
    required this.starred,
    this.lyrics,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String albumId;
  final String artistId;
  final double duration; // 秒
  final int playCount;
  final bool starred;
  final String? lyrics; // Navidrome JSON 歌词原文（Phase 2 解析）

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: _Json.str(j, 'id'),
        title: _Json.str(j, 'title', '未知歌曲'),
        artist: _Json.str(j, 'artist', '未知歌手'),
        album: _Json.str(j, 'album'),
        albumId: _Json.str(j, 'albumId'),
        artistId: _Json.str(j, 'artistId'),
        duration: _Json.doubleOf(j, 'duration'),
        playCount: _Json.intOf(j, 'playCount'),
        starred: _Json.boolOf(j, 'starred'),
        lyrics: j['lyrics'] as String?,
      );

  static List<Song> listFromJson(dynamic json) => (json as List<dynamic>)
      .map((e) => Song.fromJson(e as Map<String, dynamic>))
      .toList();

  /// 序列化（对标 1.x stripSong：剔除体积较大的内嵌歌词字段）
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'albumId': albumId,
        'artistId': artistId,
        'duration': duration,
        'playCount': playCount,
        'starred': starred,
      };
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.artistId,
    required this.songCount,
    required this.duration,
    required this.playCount,
    required this.starred,
    this.year,
  });

  final String id;
  final String name;
  final String artist;
  final String artistId;
  final int songCount;
  final double duration;
  final int playCount;
  final bool starred;
  final int? year;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: _Json.str(j, 'id'),
        name: _Json.str(j, 'name', '未知专辑'),
        artist: _Json.str(j, 'artist', '未知歌手'),
        artistId: _Json.str(j, 'artistId'),
        songCount: _Json.intOf(j, 'songCount'),
        duration: _Json.doubleOf(j, 'duration'),
        playCount: _Json.intOf(j, 'playCount'),
        starred: _Json.boolOf(j, 'starred'),
        year: (j['maxYear'] as num?)?.toInt(),
      );

  static List<Album> listFromJson(dynamic json) => (json as List<dynamic>)
      .map((e) => Album.fromJson(e as Map<String, dynamic>))
      .toList();
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.albumCount,
    required this.songCount,
  });

  final String id;
  final String name;
  final int albumCount;
  final int songCount;

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        id: _Json.str(j, 'id'),
        name: _Json.str(j, 'name', '未知歌手'),
        albumCount: _Json.intOf(j, 'albumCount'),
        songCount: _Json.intOf(j, 'songCount'),
      );

  static List<Artist> listFromJson(dynamic json) => (json as List<dynamic>)
      .map((e) => Artist.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// /search 接口的聚合结果
class SearchResult {
  const SearchResult({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
  });

  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;

  bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty;
}
