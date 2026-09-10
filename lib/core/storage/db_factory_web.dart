import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

bool _configured = false;

/// web 端：切换到 WASM sqlite 工厂（worker 文件 web/sqflite_sw.js 由
/// `dart run sqflite_common_ffi_web:setup` 生成并随仓库提交）
Future<void> configureDbFactoryImpl() async {
  if (_configured) return;
  databaseFactory = databaseFactoryFfiWeb;
  _configured = true;
}
