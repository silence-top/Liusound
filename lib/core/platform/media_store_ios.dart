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
  }) async => null; // 文件复制由 download_service 统一处理（本地文件系统）

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
