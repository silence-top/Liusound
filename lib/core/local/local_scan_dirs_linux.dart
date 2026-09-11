import '../platform/app_platform.dart';
import 'local_scan_dirs.dart';

/// Linux：扫 XDG 音乐目录与下载目录（下载产物由指纹规则排除）
final class LocalScanDirsLinux implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async {
    final home = AppPlatform.env('HOME');
    if (home == null || home.isEmpty) return const [];
    return ['$home/Music', '$home/Downloads'];
  }
}
