import 'local_fs.dart';

/// web 端无本地文件系统：恒不存在/不支持（Phase 2 视需求接 IndexedDB/OPFS）
final class LocalFsWeb implements LocalFs {
  @override
  bool fileExists(String path) => false;

  @override
  Future<String?> copyToAppDocuments(
    String fileName,
    String sourcePath,
  ) async => null;

  @override
  Future<String?> writeTempFile(String fileName, List<int> bytes) async => null;

  @override
  Future<String?> readTextFile(String path) async => null;

  @override
  Future<void> deleteFile(String path) async {}
}

LocalFs createLocalFs() => LocalFsWeb();
