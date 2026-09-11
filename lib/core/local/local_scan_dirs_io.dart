import '../platform/app_platform.dart';
import 'local_scan_dirs.dart';
import 'local_scan_dirs_android.dart';
import 'local_scan_dirs_ios.dart';
import 'local_scan_dirs_linux.dart';
import 'local_scan_dirs_macos.dart';
import 'local_scan_dirs_ohos.dart';
// ignore: unnecessary_import
import 'local_scan_dirs_stub.dart';
import 'local_scan_dirs_windows.dart';

LocalScanDirs createLocalScanDirs() {
  if (AppPlatform.isAndroid) return LocalScanDirsAndroid();
  if (AppPlatform.isIOS) return LocalScanDirsIos();
  if (AppPlatform.isWindows) return LocalScanDirsWindows();
  if (AppPlatform.isMacOS) return LocalScanDirsMacos();
  if (AppPlatform.isLinux) return LocalScanDirsLinux();
  if (AppPlatform.isOhos) return LocalScanDirsOhos();
  return LocalScanDirsStub();
}
