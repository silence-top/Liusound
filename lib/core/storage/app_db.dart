import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 应用级 SQLite（Scrobble 离线队列 / 曲库增量同步快照 / 本地导入歌词）。
/// 懒初始化单例；表结构随 version 升级在 onUpgrade 迁移
abstract final class AppDb {
  static Database? _db;

  static Future<Database> instance() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'liusound.db'),
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE scrobble_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id TEXT NOT NULL,
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
        await _createLyricsLocal(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 3) {
          // 历史记录没有归属服务器，继续补发会串到新账号；安全起见丢弃。
          await db.execute(
            "ALTER TABLE scrobble_queue ADD COLUMN server_id TEXT NOT NULL DEFAULT ''",
          );
          await db.delete('scrobble_queue', where: "server_id = ''");
        }
        await _createLyricsLocal(db);
      },
    );
    _db = db;
    return db;
  }

  static Future<void> _createLyricsLocal(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lyrics_local(
        lookup_key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// 本地歌词查找键：「标题|歌手」归一化（去空白 + 小写）
  static String lyricsKey(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  static Future<String?> loadLocalLyrics(String title, String artist) async {
    final db = await instance();
    final rows = await db.query(
      'lyrics_local',
      where: 'lookup_key = ?',
      whereArgs: [lyricsKey(title, artist)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  static Future<void> saveLocalLyrics(
    String title,
    String artist,
    String content,
  ) async {
    final db = await instance();
    await db.insert('lyrics_local', {
      'lookup_key': lyricsKey(title, artist),
      'title': title,
      'artist': artist,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
