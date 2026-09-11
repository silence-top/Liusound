import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_platform.dart';
import 'media_store.dart';

/// Linux：XDG 音乐目录下 流声/ 子目录（~/Music/流声，取 HOME 拼路径，
/// 与 macOS 同模式；XDG 用户目录非 Music 时由回退逻辑兜底）。
final class MediaStoreLinux implements MediaStore {
  @override
  Future<String?> saveToPublicMusic({
    required String sourcePath,
    required String fileName,
    required String title,
    required String artist,
    String album = '',
    int durationMs = 0,
  }) async {
    final dirPath = await publicMusicDir();
    if (dirPath == null) return null;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final target = File(p.join(dir.path, fileName));
      if (await target.exists()) await target.delete();
      final source = File(sourcePath);
      await source.rename(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> publicMusicDir() async {
    final home = AppPlatform.env('HOME');
    if (home == null || home.isEmpty) return null;
    return '$home/Music/$publicMusicDirName';
  }
}
