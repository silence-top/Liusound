import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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
Future<List<Song>> scanLocalLibrary() async {
  if (!await ensureAudioPermission()) {
    throw StateError('未授予音乐文件访问权限，请到系统设置开启');
  }
  final dirs = <Directory>[];
  if (Platform.isAndroid) {
    dirs.addAll([
      Directory('/storage/emulated/0/Music'),
      Directory('/storage/emulated/0/Download'),
    ]);
  } else if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'];
    if (home != null) dirs.add(Directory('$home\\Music'));
  }
  final files = <File>[];
  for (final dir in dirs) {
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

  final coverDir = await _coverDir();
  final songs = <Song>[];
  for (final file in files) {
    try {
      songs.add(await _buildLocalSong(file, coverDir));
    } catch (_) {
      continue; // 单文件解析失败（损坏/被占用）跳过
    }
  }
  return songs;
}

Future<Directory> _coverDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}covers');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

Future<Song> _buildLocalSong(File file, Directory coverDir) async {
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

  final lyrics = (meta.lyrics?.isNotEmpty ?? false) ? meta.lyrics : null;
  if (lyrics != null) {
    try {
      await AppDb.saveLocalLyrics(title, artist, lyrics);
    } catch (_) {
      // 歌词落库失败不影响歌曲本身
    }
  }

  String? coverPath;
  final picture = meta.pictures.isEmpty ? null : meta.pictures.first;
  if (picture != null && picture.bytes.isNotEmpty) {
    final coverFile = File(
      p.join(coverDir.path, '${file.lengthSync()}_${name.hashCode}.img'),
    );
    try {
      if (!coverFile.existsSync()) {
        await coverFile.writeAsBytes(picture.bytes, flush: true);
      }
      coverPath = coverFile.path;
    } catch (_) {
      // 封面抽取失败按无封面处理
    }
  }

  return Song(
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
}

/// 本地音乐列表（负一屏「本地音乐」入口）：权限申请 + 目录扫描 + 标签解析
final localSongsProvider = FutureProvider<List<Song>>(
  (_) => scanLocalLibrary(),
);
