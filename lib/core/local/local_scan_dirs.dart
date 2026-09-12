/// 本地音乐扫描目录门面（按平台提供默认扫描路径）。
/// 实现按平台分文件：
/// - Android：/storage/emulated/0/Music、/storage/emulated/0/Download
/// - iOS：应用 Documents 目录（文件共享后用户可从「文件」App 放入音频）
/// - Windows：%USERPROFILE%\Music
/// - macOS：~/Music、~/Downloads
/// - Linux：~/Music、~/Downloads
/// - 鸿蒙：应用沙箱 Documents 目录
/// - web：浏览器无文件系统访问，返回空列表
library;

import 'local_scan_dirs_stub.dart'
    if (dart.library.io) 'local_scan_dirs_io.dart'
    show createLocalScanDirs;
export 'local_scan_dirs_stub.dart'
    if (dart.library.io) 'local_scan_dirs_io.dart';

/// 全局单例（业务侧直接 `localScanDirs.getScanDirectories()`）
final LocalScanDirs localScanDirs = createLocalScanDirs();

/// 提供本地音乐扫描目录列表。
/// 平台不支持或无权限时返回空列表。
abstract interface class LocalScanDirs {
  Future<List<String>> getScanDirectories();
}
