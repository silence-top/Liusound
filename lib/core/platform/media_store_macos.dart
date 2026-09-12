import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_platform.dart';
import 'media_store.dart';

/// macOS：真实音乐目录下 流声/ 子目录（~/Music/流声）。
/// 沙盒下依赖 com.apple.security.assets.music 授权；目录不可写时
/// download_service 统一回退应用私有 Documents/Music。
/// （path_provider 未在 Dart 顶层暴露音乐目录，取 HOME 环境变量拼路径）
final class MediaStoreMacos implements MediaStore {
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
    final home = AppPlatform.env('HOME');
    if (home == null || home.isEmpty) return null;
    return '$home/Music/$publicMusicDirName';
  }
}
