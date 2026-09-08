import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../../settings/streaming_prefs.dart';
import '../../subsonic/subsonic.dart';
import '../adapter_log.dart';
import '../server_adapter.dart';

/// Subsonic 协议共享层：SubsonicAdapter（纯 Subsonic）与 NavidromeAdapter
/// （全兼容 Subsonic API）共用的资料库扩展 / 媒体直链 / 转码探测实现。
/// 子类提供 [dio]、[auth]、[api]（返回解包后的 subsonic-response，失败抛异常）
/// 与 [parseSong]（歌曲 JSON 映射，两端的字段惯例略有差异）。
abstract class SubsonicProtocolAdapter implements ServerAdapter {
  SubsonicProtocolAdapter();

  Dio get dio;

  SubsonicAuth get auth;

  /// 请求 Subsonic endpoint 并返回解包后的 subsonic-response；失败抛异常
  Future<Map<String, dynamic>> api(String endpoint, Map<String, String> extra);

  /// 歌曲 JSON → Song（Subsonic 用 _toSong 扩展映射；Navidrome 用 Song.fromJson）
  Song parseSong(Map<String, dynamic> json);

  // ---------- 媒体 ----------

  @override
  Future<PlaybackSource> resolveStream(
    Song song, {
    QualityHint? quality,
  }) async {
    final hint = quality;
    return PlaybackSource(
      url: Subsonic.streamUrl(
        auth,
        song.id,
        maxBitRate: hint?.transcode == true ? hint!.quality.bitRate : null,
        format: hint?.transcode == true ? hint!.format.name : null,
      ),
    );
  }

  @override
  Future<PlaybackSource> resolveDownload(Song song) async =>
      PlaybackSource(url: Subsonic.downloadUrl(auth, song.id));

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    if (!auth.isValid || albumId.isEmpty) return null;
    return ImageSource(url: Subsonic.coverArtUrl(auth, albumId, size: size));
  }

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    if (!auth.isValid || albumId.isEmpty) return null;
    try {
      final url = Subsonic.coverArtUrl(auth, albumId, size: size);
      final resp = await dio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      return resp.data;
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  // ---------- 转码探测 ----------

  bool? _transcodeProbe;

  @override
  Future<bool> supportsTranscode() async {
    final cached = _transcodeProbe;
    if (cached != null) return cached;
    // 先读持久化结果，避免每次冷启动首播前重探（探测要发 2 个网络请求）
    final persisted = await TranscodeProbeCache.get(
      auth.serverUrl,
      auth.username,
    );
    if (persisted != null) {
      _transcodeProbe = persisted;
      return persisted;
    }
    final result = await _probeTranscode();
    _transcodeProbe = result;
    unawaited(TranscodeProbeCache.set(auth.serverUrl, auth.username, result));
    return result;
  }

  /// 静默探测转码能力：取一首歌请求 64kbps 转码流，只读响应头不下载内容。
  /// 响应是音频流 → 支持；返回 JSON 错误/HTTP 错误 → 服务端缺转码器（如未装 ffmpeg）。
  /// 探测异常（网络抖动/曲库为空）放行，交由播放侧回退兜底
  Future<bool> _probeTranscode() async {
    try {
      final songs = await fetchSongs(
        const SongQuery(sort: SongSort.random, limit: 1),
      );
      if (songs.isEmpty) return true;
      final resp = await dio.get<ResponseBody>(
        Subsonic.streamUrl(auth, songs.first.id, maxBitRate: 64, format: 'mp3'),
        options: Options(
          responseType: ResponseType.stream,
          // 非 200 也要拿到响应体类型用于判别，不进异常路径
          validateStatus: (_) => true,
        ),
      );
      // 取消订阅关闭底层连接，避免服务端转码流不支持 Range 时整首下载
      final sub = resp.data!.stream.listen((_) {});
      await sub.cancel();
      final typeHeader = resp.headers.value('content-type') ?? '';
      return resp.statusCode == 200 && typeHeader.startsWith('audio/');
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return true;
    }
  }

  // ---------- 资料库扩展 ----------

  @override
  Future<List<Artist>?> fetchArtists() async {
    try {
      final data = await api('getIndexes', {});
      final indexes = data['indexes']?['index'] as List<dynamic>? ?? const [];
      return [for (final index in indexes) ..._artistsOfIndex(index)];
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  @override
  Future<List<Artist>?> fetchAlbumArtists() async {
    try {
      final data = await api('getArtists', {});
      final indexes = data['artists']?['index'] as List<dynamic>? ?? const [];
      return [for (final index in indexes) ..._artistsOfIndex(index)];
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  List<Artist> _artistsOfIndex(dynamic index) {
    if (index is! Map<String, dynamic>) return const [];
    final artists = index['artist'] as List<dynamic>? ?? const [];
    return [
      for (final a in artists)
        if (a is Map<String, dynamic>)
          Artist(
            id: _str(a, 'id'),
            name: _str(a, 'name', '未知歌手'),
            albumCount: _int(a, 'albumCount'),
            songCount: _int(a, 'songCount'),
          ),
    ];
  }

  @override
  Future<List<Genre>?> fetchGenres() async {
    try {
      final data = await api('getGenres', {});
      final genres = data['genres']?['genre'] as List<dynamic>? ?? const [];
      return [
        for (final g in genres)
          if (g is Map<String, dynamic>)
            Genre(
              // 流派名是 XML 文本内容，JSON 化后落在 value；部分服务器用 name/genre
              value: _firstStr(g, const ['value', 'name', 'genre']) ?? '',
              songCount: _int(g, 'count'),
              albumCount: _int(g, 'albumCount'),
            ),
      ].where((g) => g.value.isNotEmpty).toList();
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  @override
  Future<List<RadioStation>?> fetchRadioStations() async {
    try {
      final data = await api('getInternetRadioStations', {});
      final stations =
          data['internetRadioStations']?['station'] as List<dynamic>? ??
          const [];
      return [
        for (final s in stations)
          if (s is Map<String, dynamic>)
            RadioStation(
              id: _str(s, 'id'),
              name: _str(s, 'name', '未命名电台'),
              streamUrl: _str(s, 'streamUrl'),
              homePageUrl: _firstStr(s, const ['homePageUrl']),
            ),
      ];
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  @override
  Future<List<Song>?> fetchGenreSongs(String genre, {int limit = 100}) async {
    try {
      final data = await api('getSongsByGenre', {
        'genre': genre,
        'count': '$limit',
      });
      final songs = data['songsByGenre']?['song'] as List<dynamic>? ?? const [];
      return [
        for (final s in songs)
          if (s is Map<String, dynamic>) parseSong(s),
      ];
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  /// OpenSubsonic getLyricsBySongId（Navidrome 等支持；老服务器返回非 ok 即 null）
  @override
  Future<String?> fetchLyrics(String songId) async {
    try {
      final data = await api('getLyricsBySongId', {'id': songId});
      final list = data['lyricsList']?['structuredLyrics'] as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      return jsonEncode(list);
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  @override
  Future<String?> libraryVersion() async {
    try {
      final data = await api('getMusicFolders', {});
      return Subsonic.musicFoldersVersion(data);
    } catch (err, st) {
      adapterSwallowLog(type.name, err, st);
      return null;
    }
  }

  // ---------- JSON 小工具（与子类各自的映射工具语义一致） ----------

  static String _str(Map<String, dynamic> j, String k, [String d = '']) =>
      Json.str(j, k, d);
  static int _int(Map<String, dynamic> j, String k) => Json.intOf(j, k);

  static String? _firstStr(Map<String, dynamic> j, List<String> keys) =>
      Json.firstStr(j, keys);
}
