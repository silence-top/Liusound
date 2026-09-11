import 'package:path_provider/path_provider.dart';

import 'local_scan_dirs.dart';

/// iOS：无公共音乐目录，扫应用 Documents（开启文件共享后用户可从
/// 「文件」App 放入音频；下载产物由指纹规则排除）
final class LocalScanDirsIos implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async {
    final docs = await getApplicationDocumentsDirectory();
    return [docs.path];
  }
}
