import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_fs.dart';

final class LocalFsIo implements LocalFs {
  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  Future<String?> copyToAppDocuments(String fileName, String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}${Platform.pathSeparator}$fileName';
      await File(sourcePath).copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> writeTempFile(String fileName, List<int> bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readTextFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

LocalFs createLocalFs() => LocalFsIo();
