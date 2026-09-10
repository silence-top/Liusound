/// SQLite 数据库工厂按平台接线：io 端用 sqflite 默认插件工厂（无需配置），
/// web 端切 databaseFactoryFfiWeb（WASM sqlite 在 dedicated worker 内执行，
/// 迁移/建表脚本随 AppDb 原逻辑运行，无需分叉）。
library;

import 'db_factory_web.dart'
    if (dart.library.io) 'db_factory_io.dart'
    show configureDbFactoryImpl;

/// 幂等接线：须在首次 [AppDb.instance] 前（AppDb 内部）调用
Future<void> configureDbFactory() => configureDbFactoryImpl();
