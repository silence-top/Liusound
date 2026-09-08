// Navidrome REST / Subsonic 数据模型（对标 1.x src/types/api.ts，fromJson 容错缺失字段）

abstract final class Json {
  static String str(
    Map<String, dynamic> j,
    String key, [
    String fallback = '',
  ]) => j[key]?.toString() ?? fallback;

  /// 依次取第一个非空字段（新版 Navidrome /api/album 已移除 artist/artistId，
  /// 只返回 albumArtist/albumArtistId，需回退兼容旧版）
  static String strOf(
    Map<String, dynamic> j,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final k in keys) {
      final v = j[k]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    return fallback;
  }

  static int intOf(Map<String, dynamic> j, String key, [int fallback = 0]) =>
      (j[key] as num?)?.toInt() ?? fallback;

  static double doubleOf(
    Map<String, dynamic> j,
    String key, [
    double fallback = 0,
  ]) => (j[key] as num?)?.toDouble() ?? fallback;

  static bool boolOf(
    Map<String, dynamic> j,
    String key, [
    bool fallback = false,
  ]) => j[key] is bool ? j[key] as bool : fallback;

  /// 依次取第一个非空字段，全缺时返回 null（可选元数据用，不能用 fallback 版）
  static String? strOrNull(Map<String, dynamic> j, List<String> keys) {
    final v = strOf(j, keys);
    return v.isEmpty ? null : v;
  }

  /// 依次取第一个可解析为数值的字段；兼容后端把数字返回成字符串，全缺返回 null
  static double? doubleOrNull(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static int? intOrNull(Map<String, dynamic> j, List<String> keys) =>
      Json.doubleOrNull(j, keys)?.round();

  /// 单键取整数（仅接受 num，不做字符串解析；其他类型返回 null）
  static int? intOfOrNull(Map<String, dynamic> j, String key) {
    final v = j[key];
    return v is num ? v.toInt() : null;
  }

  /// 按候选键顺序取第一个非空（trim 后）字符串；全缺返回 null
  static String? firstStr(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }
}

/// 采样率统一为 Hz：Subsonic 系的 samplingRate 单位是 kHz（44.1），
/// Jellyfin / Plex 的 sampleRate 是 Hz（44100）。真实音频不存在 1kHz 以下的
/// 采样率，以 1000 为界做单位归一，避免两种后端展示差三个数量级。
int? _sampleRateHz(Map<String, dynamic> j) {
  final raw = Json.doubleOrNull(j, const ['samplingRate', 'sampleRate']);
  if (raw == null || raw <= 0) return null;
  return raw < 1000 ? (raw * 1000).round() : raw.round();
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
    required this.size,
    required this.rating,
    this.lyrics,
    this.suffix,
    this.codec,
    this.bitRate,
    this.sampleRate,
    this.bitDepth,
    this.albumArtist,
    this.year,
    this.discNumber,
    this.trackNumber,
    this.path,
    this.lastPlayed,
    this.created,
    this.replayGain,
    this.localCoverPath,
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
  final int size; // 文件字节数（详情页计算码率展示用，对齐 1.x SongResponse.size）
  final int rating; // 评分 0-5（Subsonic setRating）
  final String? lyrics; // Navidrome JSON 歌词原文

  // 音频元数据：六种后端能力不一，取不到即留空，展示层负责降级
  final String? suffix; // 容器/编码后缀，如 flac / mp3 / m4a
  final String? codec; // 解码器名，如 FLAC / AAC
  final int? bitRate; // kbps
  final int? sampleRate; // Hz（已由 _sampleRateHz 归一）
  final int? bitDepth; // 位深，如 16 / 24

  // 歌曲详情页扩展元数据（Subsonic child / 各后端等价字段，缺省 null）
  final String? albumArtist; // 专辑艺术家名
  final int? year; // 年代
  final int? discNumber; // 碟号
  final int? trackNumber; // 音轨号
  final String? path; // 服务端文件路径
  final String? lastPlayed; // 上次播放时间（ISO8601 原文）
  final String? created; // 入库时间（ISO8601 原文）
  final ReplayGain? replayGain; // 回放增益（专辑/音轨的增益与峰值）

  // 本地歌曲专属：内嵌封面已抽取到文件的路径（服务端歌曲恒为 null）
  final String? localCoverPath;

  factory Song.fromJson(Map<String, dynamic> j) => Song(
    id: Json.str(j, 'id'),
    title: Json.str(j, 'title', '未知歌曲'),
    artist: Json.str(j, 'artist', '未知歌手'),
    album: Json.str(j, 'album'),
    albumId: Json.str(j, 'albumId'),
    artistId: Json.str(j, 'artistId'),
    duration: Json.doubleOf(j, 'duration'),
    playCount: Json.intOf(j, 'playCount'),
    starred: Json.boolOf(j, 'starred'),
    size: Json.intOf(j, 'size'),
    rating: Json.intOf(j, 'rating'),
    lyrics: j['lyrics'] as String?,
    suffix: Json.strOrNull(j, const [
      'suffix',
      'transcodedSuffix',
      'contentType',
    ]),
    codec: Json.strOrNull(j, const ['codec', 'transcodedCodec']),
    bitRate: Json.intOrNull(j, const ['bitRate', 'bitrate']),
    sampleRate: _sampleRateHz(j),
    bitDepth: Json.intOrNull(j, const ['bitDepth']),
    albumArtist: Json.strOrNull(j, const ['albumArtist', 'albumArtistName']),
    year: Json.intOrNull(j, const ['year']),
    discNumber: Json.intOrNull(j, const ['discNumber']),
    trackNumber: Json.intOrNull(j, const ['trackNumber', 'track']),
    path: Json.strOrNull(j, const ['path', 'filePath']),
    lastPlayed: Json.strOrNull(j, const [
      'played',
      'lastPlayed',
      'lastPlayedAt',
    ]),
    created: Json.strOrNull(j, const [
      'created',
      'createdAt',
      'created_at',
      'dateCreated',
    ]),
    replayGain: j['replayGain'] is Map<String, dynamic>
        ? ReplayGain.fromJson(j['replayGain'] as Map<String, dynamic>)
        : null,
  );

  Song copyWith({bool? starred, int? rating, String? lyrics}) => Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    albumId: albumId,
    artistId: artistId,
    duration: duration,
    playCount: playCount,
    starred: starred ?? this.starred,
    size: size,
    rating: rating ?? this.rating,
    lyrics: lyrics ?? this.lyrics,
    suffix: suffix,
    codec: codec,
    bitRate: bitRate,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    albumArtist: albumArtist,
    year: year,
    discNumber: discNumber,
    trackNumber: trackNumber,
    path: path,
    lastPlayed: lastPlayed,
    created: created,
    replayGain: replayGain,
    localCoverPath: localCoverPath,
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
    'size': size,
    'rating': rating,
    // 音频元数据一并落盘：冷启动恢复队列后音质徽标不会退化成空
    if (suffix != null) 'suffix': suffix,
    if (codec != null) 'codec': codec,
    if (bitRate != null) 'bitRate': bitRate,
    if (sampleRate != null) 'sampleRate': sampleRate,
    if (bitDepth != null) 'bitDepth': bitDepth,
    if (albumArtist != null) 'albumArtist': albumArtist,
    if (year != null) 'year': year,
    if (discNumber != null) 'discNumber': discNumber,
    if (trackNumber != null) 'trackNumber': trackNumber,
    if (path != null) 'path': path,
    if (lastPlayed != null) 'lastPlayed': lastPlayed,
    if (created != null) 'created': created,
    if (localCoverPath != null) 'localCoverPath': localCoverPath,
    'replayGain': ?replayGain,
  };
}

/// 回放增益（OpenSubsonic replayGain 对象）；单位 dB / 线性峰值
class ReplayGain {
  const ReplayGain({
    this.albumGain,
    this.albumPeak,
    this.trackGain,
    this.trackPeak,
  });

  final double? albumGain;
  final double? albumPeak;
  final double? trackGain;
  final double? trackPeak;

  factory ReplayGain.fromJson(Map<String, dynamic> j) => ReplayGain(
    albumGain: Json.doubleOrNull(j, const ['albumGain']),
    albumPeak: Json.doubleOrNull(j, const ['albumPeak']),
    trackGain: Json.doubleOrNull(j, const ['trackGain']),
    trackPeak: Json.doubleOrNull(j, const ['trackPeak']),
  );

  Map<String, dynamic> toJson() => {
    if (albumGain != null) 'albumGain': albumGain,
    if (albumPeak != null) 'albumPeak': albumPeak,
    if (trackGain != null) 'trackGain': trackGain,
    if (trackPeak != null) 'trackPeak': trackPeak,
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
    required this.rating,
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
  final int rating; // 评分 0-5
  final int? year;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
    id: Json.str(j, 'id'),
    name: Json.strOf(j, const ['name', 'title', 'album'], '未知专辑'),
    artist: Json.strOf(j, const ['artist', 'albumArtist'], '未知歌手'),
    artistId: Json.strOf(j, const ['artistId', 'albumArtistId']),
    songCount: Json.intOf(j, 'songCount'),
    duration: Json.doubleOf(j, 'duration'),
    playCount: Json.intOf(j, 'playCount'),
    starred: Json.boolOf(j, 'starred'),
    rating: Json.intOf(j, 'rating'),
    year: (j['maxYear'] as num?)?.toInt() ?? (j['year'] as num?)?.toInt(),
  );

  static List<Album> listFromJson(dynamic json) => (json as List<dynamic>)
      .map((e) => Album.fromJson(e as Map<String, dynamic>))
      .toList();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'artist': artist,
    'artistId': artistId,
    'songCount': songCount,
    'duration': duration,
    'playCount': playCount,
    'starred': starred,
    'rating': rating,
    'year': ?year,
  };
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
    id: Json.str(j, 'id'),
    name: Json.str(j, 'name', '未知歌手'),
    albumCount: Json.intOf(j, 'albumCount'),
    songCount: Json.intOf(j, 'songCount'),
  );

  static List<Artist> listFromJson(dynamic json) => (json as List<dynamic>)
      .map((e) => Artist.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// 流派（Subsonic getGenres / 各后端等价接口；value 为流派名）
class Genre {
  const Genre({required this.value, this.songCount = 0, this.albumCount = 0});

  final String value;
  final int songCount;
  final int albumCount;
}

/// 网络电台（Subsonic getInternetRadioStations 列表项）
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.homePageUrl,
  });

  final String id;
  final String name;
  final String streamUrl;
  final String? homePageUrl;
}

/// 歌单（Navidrome /api/playlist 列表项）
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.songCount,
    this.coverArt,
    this.owner,
  });

  final String id;
  final String name;
  final int songCount;
  final String? coverArt; // 封面 id（getCoverArt 用）
  final String? owner; // 所有者用户名（区分「我的歌单 / 全部歌单」）

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    id: Json.str(j, 'id'),
    name: Json.str(j, 'name', '未命名歌单'),
    songCount: Json.intOf(j, 'songCount'),
    coverArt: j['coverArt']?.toString(),
    // Navidrome 返回 owner（用户名）/ownerName（显示名）两个字段，兼容取其一
    owner: (j['owner'] ?? j['ownerName'])?.toString(),
  );

  static List<Playlist> listFromJson(dynamic json) => (json as List<dynamic>)
      .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
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
