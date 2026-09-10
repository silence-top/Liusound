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
  }) async => null; // 文件复制由 download_service 统一处理（本地文件系统）

  @override
  Future<String?> publicMusicDir() async {
    final home = AppPlatform.env('HOME');
    if (home == null || home.isEmpty) return null;
    return '$home/Music/$publicMusicDirName';
  }
}
