import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 应用级 SQLite（Scrobble 离线队列 / 曲库增量同步快照）。
/// 懒初始化单例；表结构随 version 升级在 onUpgrade 迁移
abstract final class AppDb {
  static Database? _db;

  static Future<Database> instance() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'liusound.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE scrobble_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            song_id TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE library_snapshot(
            server_key TEXT NOT NULL,
            kind TEXT NOT NULL,
            version TEXT,
            payload TEXT NOT NULL,
            PRIMARY KEY(server_key, kind)
          )
        ''');
      },
    );
    _db = db;
    return db;
  }
}
