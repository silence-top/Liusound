import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/models.dart';
import '../storage/app_db.dart';

/// 本地歌曲 id 前缀：与服务器歌曲 id 天然不冲突，路径直接编码在 id 里
const localSongIdPrefix = 'local:';

/// 从本地歌曲 id 解出文件路径（非本地歌曲返回 null）
String? localSongPath(Song song) => song.id.startsWith(localSongIdPrefix)
    ? song.id.substring(localSongIdPrefix.length)
    : null;

const _audioExts = {'.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav'};

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
  for (final (title, artist, content) in result.lyrics) {
    try {
      await AppDb.saveLocalLyrics(title, artist, content);
    } catch (_) {
      // 歌词落库失败不影响歌曲本身
    }
  }
  await _saveLocalCache(result.songs);
  return result.songs;
}

/// 扫描 isolate 产物：歌曲 + 待落库的内嵌歌词
typedef _ScanResult = ({
  List<Song> songs,
  List<(String, String, String)> lyrics,
});

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
        if (_audioExts.contains(p.extension(entry.path).toLowerCase())) {
          files.add(entry);
        }
      }
    } catch (_) {
      continue; // 单目录不可读不阻断整体扫描
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final songs = <Song>[];
  final lyrics = <(String, String, String)>[];
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

({Song song, (String, String, String)? lyrics}) _buildLocalSong(
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

  final song = Song(
    id: '$localSongIdPrefix${file.path}',
    title: title,
    artist: artist,
    album: album,
    albumId: '',
    artistId: '',
    duration: meta.duration?.inMilliseconds.toDouble() ?? 0,
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
  return (
    song: song,
    lyrics: lyricsText == null ? null : (title, artist, lyricsText),
  );
}

// ---------- 快照缓存：进页面先读 SQLite 秒开，后台限流重扫 ----------

/// 后台重扫发现文件变化时 bump，驱动 localSongsProvider 重读快照
final localScanVersionProvider = StateProvider<int>((ref) => 0);

DateTime? _lastScanFinishedAt;

/// 本地音乐列表（资料库「本地音乐」入口）：
/// 首次进页面同步扫描；之后读 SQLite 快照秒开，后台限流重扫（5 分钟内不重复），
/// 文件有增删时 bump 版本自动刷新列表。
final localSongsProvider = FutureProvider<List<Song>>((ref) async {
  ref.watch(localScanVersionProvider);
  final cached = await loadLocalSongsCache();
  if (cached != null && cached.isNotEmpty) {
    _rescanInBackground(ref, cached);
    return cached;
  }
  final scanned = await scanLocalLibrary();
  _lastScanFinishedAt = DateTime.now();
  return scanned;
});

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
      where: "server_key = 'local' AND kind = 'local_songs'",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String;
    return [
      for (final j in jsonDecode(raw) as List)
        Song.fromJson(j as Map<String, dynamic>),
    ];
  } catch (_) {
    return null;
  }
}

Future<void> _saveLocalCache(List<Song> songs) async {
  try {
    final db = await AppDb.instance();
    await db.insert('library_snapshot', {
      'server_key': 'local',
      'kind': 'local_songs',
      'version': DateTime.now().toIso8601String(),
      'payload': jsonEncode(songs.map((s) => s.toJson()).toList()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } catch (_) {
    // 缓存失败只影响下次秒开，不影响本次结果
  }
}
