import '../platform/app_platform.dart';
import 'local_scan_dirs.dart';

/// Windows：扫用户音乐库目录
final class LocalScanDirsWindows implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async {
    final home = AppPlatform.env('USERPROFILE');
    if (home == null || home.isEmpty) return const [];
    return ['$home\\Music'];
  }
}
