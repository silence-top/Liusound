import 'package:path_provider/path_provider.dart';

import 'local_scan_dirs.dart';

/// 鸿蒙：扫应用沙箱 Documents（path_provider 经 ohos 移植提供；
/// 下载产物由指纹规则排除）
final class LocalScanDirsOhos implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async {
    final docs = await getApplicationDocumentsDirectory();
    return [docs.path];
  }
}
