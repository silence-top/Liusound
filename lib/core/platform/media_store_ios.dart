import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'media_store.dart';

/// iOS：应用 Documents 目录（Files.app「我的 iPhone→流声」可见，
/// 需 Info.plist 的 UIFileSharingEnabled/LSSupportsOpeningDocumentsInPlace）。
/// iOS 无跨应用公共音乐目录概念，Documents 即最佳可见落点。
final class MediaStoreIos implements MediaStore {
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
  Future<bool> deleteFromPublicMusic({
    required String fileName,
  }) async {
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
    try {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/$publicMusicDirName';
    } catch (_) {
      return null;
    }
  }
}
