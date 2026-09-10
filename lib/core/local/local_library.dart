import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/models.dart';
import '../storage/app_db.dart';

/// 本地歌曲 id 前缀：与服务器歌曲 id 天然不冲突。
/// id 格式为 local:{fingerprint}——fingerprint 由文件大小 + mtime + 头部 16KB +
/// 元数据派生，移动/重命名文件不改变歌曲身份（路径变化仍记录在 Song.path）
const localSongIdPrefix = 'local:';

/// 从本地歌曲 id 解出 fingerprint（非本地歌曲返回 null）
String? localSongFingerprint(Song song) => song.id.startsWith(localSongIdPrefix)
    ? song.id.substring(localSongIdPrefix.length)
    : null;

/// 本地歌曲的磁盘路径（非本地歌曲返回 null）
String? localSongPath(Song song) =>
    song.id.startsWith(localSongIdPrefix) ? song.path : null;

const _audioExts = {'.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav'};

/// 下载产物命名标记（download_service：`歌手 - 标题--<16位指纹>.<ext>`，
/// 指纹为 sha256(songId) 前 16 位十六进制）：下载落盘目录（Android 公共
/// Music/流声、Windows 音乐库\流声）与本地扫描目录重叠，按文件名标记排除，
/// 避免同一首歌既作为服务器歌曲离线副本、又以 local: 身份重复入库。
/// 用户自放文件几乎不会匹配该模式，误伤概率可忽略。
final RegExp _downloadArtifactPattern = RegExp(
  r'--[0-9a-f]{16}\.[A-Za-z0-9]+$',
);

/// 是否应用自身下载产物（扫描排除用；公开以便测试与排查）
bool isDownloadedArtifact(String path) =>
    _downloadArtifactPattern.hasMatch(p.basename(path));

/// 指纹参与的头部分块大小（固定小块，禁止整文件 hash——大 FLAC/APE 曲库不可接受）
const _fingerprintHeadBytes = 16 * 1024;

/// 音频文件访问权限（Android 13+ READ_MEDIA_AUDIO，低版本回退存储权限）
Future<bool> ensureAudioPermission() async {
  if (!Platform.isAndroid) return true;
  final audio = await Permission.audio.request();
  if (audio.isGranted) return true;
  final storage = await Permission.storage.request();
  return storage.isGranted;
}

/// 本地音乐扫描：递归扫公共音乐目录，audio_metadata_reader 读标签
/// （标题/歌手/专辑/时长/内嵌 LRC/内嵌封面）。
/// 内嵌 LRC 写入本地歌词表（播放页自动命中），内嵌封面抽到应用封面目录。
/// 目录遍历与标签解析在后台 isolate 执行，结果落 SQLite 快照。
Future<List<Song>> scanLocalLibrary() async {
  if (!await ensureAudioPermission()) {
    throw StateError('未授予音乐文件访问权限，请到系统设置开启');
  }
  final dirPaths = <String>[
    if (Platform.isAndroid) ...[
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ] else if (Platform.isWindows)
      ...[Platform.environment['USERPROFILE']]
          .whereType<String>()
          .map((home) => '$home\\Music'),
  ];
  final coverPath = (await _coverDir()).path;
  final result = await Isolate.run(() => _scanIsolate(dirPaths, coverPath));
  // sqflite 走平台通道，只能在主 isolate 写库
  for (final (song, content) in result.lyrics) {
    try {
      await AppDb.saveLyrics(
        lookupKey: AppDb.lyricsLocalKey(localSongFingerprint(song)!),
        fallbackKey: AppDb.lyricsFallbackKey(song.title, song.artist),
        title: song.title,
        artist: song.artist,
        content: content,
      );
    } catch (_) {
      // 歌词落库失败不影响歌曲本身
    }
  }
  await _saveLocalCache(result.songs);
  return result.songs;
}

/// 扫描 isolate 产物：歌曲 + 待落库的内嵌歌词（携带 song 供派生歌词键）
typedef _ScanResult = ({List<Song> songs, List<(Song, String)> lyrics});

/// 目录遍历 + 标签解析（纯 Dart IO，可在后台 isolate 运行）
_ScanResult _scanIsolate(List<String> dirPaths, String coverDirPath) {
  final coverDir = Directory(coverDirPath);
  final files = <File>[];
  for (final dirPath in dirPaths) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    try {
      for (final entry in dir.listSync(recursive: true, followLinks: false)) {
        if (entry is! File) continue;
        if (!_audioExts.contains(p.extension(entry.path).toLowerCase())) {
          continue;
        }
        // 排除自身下载产物（落公共 Music/流声 的离线副本，身份是服务器歌曲）
        if (isDownloadedArtifact(entry.path)) continue;
        files.add(entry);
      }
    } catch (_) {
      continue; // 单目录不可读不阻断整体扫描
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final songs = <Song>[];
  final lyrics = <(Song, String)>[];
  for (final file in files) {
    try {
      final r = _buildLocalSong(file, coverDir);
      songs.add(r.song);
      final lrc = r.lyrics;
      if (lrc != null) lyrics.add(lrc);
    } catch (_) {
      continue; // 单文件解析失败（损坏/被占用）跳过
    }
  }
  return (songs: songs, lyrics: lyrics);
}

Future<Directory> _coverDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}covers');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

({Song song, (Song, String)? lyrics}) _buildLocalSong(
  File file,
  Directory coverDir,
) {
  AudioMetadata meta;
  try {
    meta = readMetadata(file, getImage: true);
  } catch (_) {
    meta = AudioMetadata(file: file); // 无标签：靠文件名回退
  }
  final name = p.basenameWithoutExtension(file.path);
  // 「歌手 - 标题」文件名回退（与离线下载命名规则一致）
  final parts = name.split(' - ');
  final title = (meta.title?.isNotEmpty ?? false)
      ? meta.title!
      : (parts.length > 1 ? parts.sublist(1).join(' - ') : name);
  final artist = (meta.artist?.isNotEmpty ?? false)
      ? meta.artist!
      : (parts.length > 1 ? parts.first : '未知歌手');
  final album = meta.album ?? '';

  final lyricsText = (meta.lyrics?.isNotEmpty ?? false) ? meta.lyrics : null;

  String? coverPath;
  final picture = meta.pictures.isEmpty ? null : meta.pictures.first;
  if (picture != null && picture.bytes.isNotEmpty) {
    final coverFile = File(
      p.join(coverDir.path, '${file.lengthSync()}_${name.hashCode}.img'),
    );
    try {
      if (!coverFile.existsSync()) {
        coverFile.writeAsBytesSync(picture.bytes, flush: true);
      }
      coverPath = coverFile.path;
    } catch (_) {
      // 封面抽取失败按无封面处理
    }
  }

  final durationMs = meta.duration?.inMilliseconds ?? 0;
  final fingerprint = _fileFingerprint(
    file,
    title: title,
    artist: artist,
    durationMs: durationMs,
  );

  final song = Song(
    id: '$localSongIdPrefix$fingerprint',
    title: title,
    artist: artist,
    album: album,
    albumId: '',
    artistId: '',
    duration: durationMs.toDouble(),
    playCount: 0,
    starred: false,
    size: file.lengthSync(),
    rating: 0,
    suffix: p.extension(file.path).replaceFirst('.', ''),
    codec: null,
    bitRate: meta.bitrate,
    sampleRate: meta.sampleRate,
    bitDepth: null,
    path: file.path,
    localCoverPath: coverPath,
  );
  return (song: song, lyrics: lyricsText == null ? null : (song, lyricsText));
}

/// 轻量身份指纹（非完整性校验）：
/// md5(文件大小 + mtime + 头部固定 16KB + 归一化标题/歌手 + 时长)。
/// 只读头部固定小块，不随文件大小线性增长 IO；在扫描 isolate 内执行
String _fileFingerprint(
  File file, {
  required String title,
  required String artist,
  required int durationMs,
}) {
  var head = const <int>[];
  try {
    final raf = file.openSync();
    try {
      head = raf.readSync(_fingerprintHeadBytes);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    // 头部不可读时退化为 size+mtime+metadata 指纹
  }
  return md5.convert(<int>[
    ...utf8.encode('${file.lengthSync()}'),
    ...utf8.encode('${file.lastModifiedSync().millisecondsSinceEpoch}'),
    ...head,
    ...utf8.encode(title.trim().toLowerCase()),
    ...utf8.encode(artist.trim().toLowerCase()),
    ...utf8.encode('$durationMs'),
  ]).toString();
}

// ---------- 快照缓存：进页面先读 SQLite 秒开，后台限流重扫 ----------

/// 后台重扫发现文件变化时 bump，驱动 localSongsProvider 重读快照
final localScanVersionProvider = StateProvider<int>((ref) => 0);

/// 下载完成信号：downloadSongFile 落盘并登记索引后由调用方 bump，
/// 驱动 localSongsProvider 的「已下载」段实时进入列表（与本地音乐合并展示）
final downloadIndexVersionProvider = StateProvider<int>((ref) => 0);

DateTime? _lastScanFinishedAt;

/// 已下载的服务器歌曲（download_index.payload 快照反序列化）：
/// 身份保持服务器 id——列表点播经 player_source_resolver 自动命中离线文件，
/// 收藏/评分/歌词等继续命中服务器歌曲，与扫描的 local: 歌曲天然不重。
/// payload 为空的历史下载（旧版本所下）无法还原元数据，跳过。
Future<List<Song>> loadDownloadedSongs() async {
  try {
    final db = await AppDb.instance();
    final rows = await db.query(
      'download_index',
      columns: ['payload'],
      orderBy: 'created_at DESC',
    );
    final songs = <Song>[];
    for (final row in rows) {
      final raw = row['payload'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        songs.add(Song.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // 单条快照损坏跳过，不影响其余
      }
    }
    return songs;
  } catch (_) {
    return const [];
  }
}

/// 本地音乐列表（资料库「本地音乐」入口）：
/// 扫描的本地歌曲 + 已下载的服务器歌曲合并展示；
/// 首次进页面同步扫描；之后读 SQLite 快照秒开，后台限流重扫（5 分钟内不重复），
/// 文件有增删时 bump 版本自动刷新列表；下载完成由调用方 bump
/// downloadIndexVersionProvider 实时补入已下载段。
final localSongsProvider = FutureProvider<List<Song>>((ref) async {
  ref.watch(localScanVersionProvider);
  ref.watch(downloadIndexVersionProvider);
  final cached = await loadLocalSongsCache();
  final List<Song> local;
  if (cached != null && cached.isNotEmpty) {
    _rescanInBackground(ref, cached);
    local = cached;
  } else {
    local = await scanLocalLibrary();
    _lastScanFinishedAt = DateTime.now();
  }
  final downloaded = await loadDownloadedSongs();
  return [...local, ...downloaded];
});

/// 强制重扫磁盘（本地音乐下拉刷新）：绕过 5 分钟限流直扫文件系统，
/// 结果直接覆盖 SQLite 快照；调用方随后 invalidate localSongsProvider
/// 重读缓存即可拿到最新数据。
Future<void> forceLocalRescan() async {
  await scanLocalLibrary();
  _lastScanFinishedAt = DateTime.now();
}

void _rescanInBackground(Ref ref, List<Song> served) {
  final last = _lastScanFinishedAt;
  if (last != null &&
      DateTime.now().difference(last) < const Duration(minutes: 5)) {
    return;
  }
  _lastScanFinishedAt = DateTime.now();
  Future<void> run() async {
    try {
      final fresh = await scanLocalLibrary();
      if (!_sameSongs(fresh, served)) {
        ref.read(localScanVersionProvider.notifier).state++;
      }
    } catch (_) {
      // 权限被回收等场景静默保留快照
    }
  }

  unawaited(run());
}

/// 快照对比只看关键元数据：数量或任一文件的大小/时长/标签变了才算变化
bool _sameSongs(List<Song> a, List<Song> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.size != y.size ||
        x.duration != y.duration ||
        x.title != y.title ||
        x.artist != y.artist) {
      return false;
    }
  }
  return true;
}

Future<List<Song>?> loadLocalSongsCache() async {
  try {
    final db = await AppDb.instance();
    final rows = await db.query(
      'library_snapshot',
      where: "server_key = 'local' AND kind = 'local_songs_v2'",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String;
    return await _decodeSongsPayload(raw);
  } catch (_) {
    return null;
  }
}

/// 大 JSON 快照编解码阈值（超过则强制后台 isolate，避免主 isolate 卡顿）
const _snapshotIsolateThreshold = 256 * 1024;

/// payload 解码：大于阈值时在 Isolate.run 中执行
Future<List<Song>> _decodeSongsPayload(String raw) async {
  if (raw.length > _snapshotIsolateThreshold) {
    return Isolate.run(() => _decodeSongs(raw));
  }
  return _decodeSongs(raw);
}

List<Song> _decodeSongs(String raw) => [
  for (final j in jsonDecode(raw) as List)
    Song.fromJson(j as Map<String, dynamic>),
];

Future<void> _saveLocalCache(List<Song> songs) async {
  try {
    final db = await AppDb.instance();
    final payload = songs.length > 1000
        ? await Isolate.run(
            () => jsonEncode(songs.map((s) => s.toJson()).toList()),
          )
        : jsonEncode(songs.map((s) => s.toJson()).toList());
    await db.insert('library_snapshot', {
      'server_key': 'local',
      'kind': 'local_songs_v2',
      'version': DateTime.now().toIso8601String(),
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // 旧格式（路径 id）缓存行清理——纯可再生缓存，无用户数据
    await db.delete(
      'library_snapshot',
      where: "server_key = 'local' AND kind = 'local_songs'",
    );
  } catch (_) {
    // 缓存失败只影响下次秒开，不影响本次结果
  }
}
