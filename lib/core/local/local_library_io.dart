import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import '../platform/app_platform.dart';
import '../storage/app_db.dart';
import 'local_library.dart';

const _audioExts = {'.mp3', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wav'};

/// 音频文件访问权限（Android 13+ READ_MEDIA_AUDIO，低版本回退存储权限）
Future<bool> ensureAudioPermission() async {
  if (!AppPlatform.isAndroid) return true;
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
    if (AppPlatform.isAndroid) ...[
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ] else if (AppPlatform.isWindows)
      ...[AppPlatform.env('USERPROFILE')]
          .whereType<String>()
          .map((home) => '$home\\Music'),
  ];
  // iOS：无公共音乐目录，扫应用 Documents（开启文件共享后用户可从
  // 「文件」App 放入音频；下载产物由指纹规则排除）
  if (AppPlatform.isIOS) {
    dirPaths.add((await getApplicationDocumentsDirectory()).path);
  }
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
  await saveLocalScanCache(result.songs);
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
  final dir = Directory(p.join(docs.path, 'covers'));
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

/// 指纹参与的头部分块大小（固定小块，禁止整文件 hash——大 FLAC/APE 曲库不可接受）
const _fingerprintHeadBytes = 16 * 1024;
