import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_platform.dart';
import 'media_store.dart';

/// Windows：用户音乐库下 流声\ 子目录（%USERPROFILE%\Music\流声）
final class MediaStoreWindows implements MediaStore {
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
  Future<bool> deleteFromPublicMusic({required String fileName}) async {
    final dirPath = await publicMusicDir();
    if (dirPath == null) return false;
    try {
      final target = File(p.join(dirPath, fileName));
      if (!await target.exists()) return false;
      await target.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> publicMusicDir() async {
    final home = AppPlatform.env('USERPROFILE');
    if (home == null || home.isEmpty) return null;
    return '$home\\Music\\$publicMusicDirName';
  }
}
