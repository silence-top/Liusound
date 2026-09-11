import 'local_scan_dirs.dart';

/// Android：扫公共音乐目录与下载目录
final class LocalScanDirsAndroid implements LocalScanDirs {
  @override
  Future<List<String>> getScanDirectories() async => const [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
  ];
}
