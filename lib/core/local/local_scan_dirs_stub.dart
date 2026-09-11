import 'local_scan_dirs.dart';

/// Web / 未知平台占位：无文件系统访问能力，返回空列表
final class LocalScanDirsStub implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async => const [];
}

LocalScanDirs createLocalScanDirs() => LocalScanDirsStub();
