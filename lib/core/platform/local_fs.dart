/// 本地文件系统最小门面：供只做少量文件操作的业务文件使用，
/// 避免其直接 import 'dart:io'（web 编译断点）。
/// 重度文件系统逻辑（下载/本地扫描/缓存治理）放各能力自己的 _io 文件。
library;

import 'local_fs_web.dart' if (dart.library.io) 'local_fs_io.dart';
export 'local_fs_web.dart' if (dart.library.io) 'local_fs_io.dart';

abstract interface class LocalFs {
  /// 文件是否存在（web 恒 false——web 无文件系统路径语义）
  bool fileExists(String path);

  /// 把源文件复制到应用 Documents 目录，返回目标绝对路径；失败/不支持返回 null
  Future<String?> copyToAppDocuments(String fileName, String sourcePath);

  /// 写临时文件，返回绝对路径；失败/不支持返回 null
  Future<String?> writeTempFile(String fileName, List<int> bytes);

  /// 读取 UTF-8 文本文件；失败/不支持返回 null
  Future<String?> readTextFile(String path);

  /// 删除文件（静默容错）
  Future<void> deleteFile(String path);
}

final LocalFs localFs = createLocalFs();
