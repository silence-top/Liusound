import 'media_store.dart';

/// 暂无公共音乐目录实现的平台（macOS/Linux/鸿蒙待各平台阶段补齐）
final class MediaStoreStub implements MediaStore {
  @override
  Future<String?> saveToPublicMusic({
    required String sourcePath,
    required String fileName,
    required String title,
    required String artist,
    String album = '',
    int durationMs = 0,
  }) async => null;

  @override
  Future<String?> publicMusicDir() async => null;
}
