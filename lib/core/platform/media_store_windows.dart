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
  }) async => null; // 文件复制由 download_service 统一处理（本地文件系统）

  @override
  Future<String?> publicMusicDir() async {
    final home = AppPlatform.env('USERPROFILE');
    if (home == null || home.isEmpty) return null;
    return '$home\\Music\\$publicMusicDirName';
  }
}
