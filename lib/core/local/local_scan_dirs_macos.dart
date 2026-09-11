import 'package:path_provider/path_provider.dart';

import '../platform/app_platform.dart';
import 'local_scan_dirs.dart';

/// macOS：扫真实音乐目录与下载目录（沙盒 assets.music / files.downloads
/// 授权；下载产物由指纹规则排除）
final class LocalScanDirsMacos implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async {
    final dirs = <String>[];
    final home = AppPlatform.env('HOME');
    if (home != null && home.isNotEmpty) dirs.add('$home/Music');
    final downloads = await getDownloadsDirectory();
    if (downloads != null) dirs.add(downloads.path);
    return dirs;
  }
}
