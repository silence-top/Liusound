import 'media_store.dart';

/// web 端：Phase 2 接浏览器下载（a[download] / File System Access API），
/// 当前回退应用内缓存。
final class MediaStoreWeb implements MediaStore {
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
  Future<bool> deleteFromPublicMusic({required String fileName}) async => false;

  @override
  Future<String?> publicMusicDir() async => null;
}

MediaStore createMediaStore() => MediaStoreWeb();
