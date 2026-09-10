import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../platform/app_platform.dart';

/// Windows/Linux：sqflite 平台插件未覆盖，切 ffi 驱动（原生 sqlite 库由
/// sqlite3_flutter_libs 打包）；Android/iOS/macOS 用平台插件工厂即可
bool _configured = false;

Future<void> configureDbFactoryImpl() async {
  if (_configured) return;
  if (AppPlatform.isWindows || AppPlatform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _configured = true;
}
