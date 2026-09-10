import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_factory.dart';

/// 应用级 SQLite（Scrobble 离线队列 / 曲库版本快照 / 本地导入歌词 / 下载索引）。
/// 懒初始化单例；表结构随 version 升级在 onUpgrade 迁移。
///
/// Migration 约束：只允许 ADD COLUMN / CREATE TABLE；
/// 破坏性操作仅限可再生缓存，且必须在迁移注释中说明影响。
abstract final class AppDb {
  static Database? _db;

  static Future<Database> instance() async {
    final existing = _db;
    if (existing != null) return existing;
    // web 端切 WASM 工厂（io 端 no-op），须在 openDatabase 前接线
    await configureDbFactory();
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'liusound.db'),
      version: 5,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE scrobble_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id TEXT NOT NULL,
            song_id TEXT NOT NULL,
            played_at INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            next_retry_at INTEGER
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
        await db.execute('''
          CREATE TABLE download_index(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id TEXT NOT NULL DEFAULT '',
            song_id TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            path TEXT NOT NULL,
            size INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            last_accessed_at INTEGER NOT NULL,
            payload TEXT
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_download_fingerprint'
          ' ON download_index(fingerprint)',
        );
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
        if (oldVersion < 4) {
          // scrobble_queue 增加重试防护字段（ played_at 缺失的历史行用 created_at 补齐）
          await db.execute(
            'ALTER TABLE scrobble_queue ADD COLUMN played_at INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE scrobble_queue ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE scrobble_queue ADD COLUMN last_error TEXT',
          );
          await db.execute(
            'ALTER TABLE scrobble_queue ADD COLUMN next_retry_at INTEGER',
          );
          await _createDownloadIndex(db);
        }
        if (oldVersion < 5) {
          // 下载索引增加 Song 元数据快照（本地音乐列表合并展示已下载歌曲用）
          await db.execute(
            'ALTER TABLE download_index ADD COLUMN payload TEXT',
          );
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

  /// 仅 onUpgrade v2→v4 路径使用：建 v4 时代的旧 schema（无 payload），
  /// payload 列由 v5 迁移统一 ALTER 补齐（避免重复加列）
  static Future<void> _createDownloadIndex(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS download_index(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT NOT NULL DEFAULT '',
        song_id TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        path TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_download_fingerprint'
      ' ON download_index(fingerprint)',
    );
  }

  // ---------- 歌词缓存键（P0-09：三种语义分开，旧键作兜底） ----------

  /// 服务器歌曲歌词键：lyrics:{serverId}:{songId}
  static String lyricsSongKey(String serverId, String songId) =>
      'lyrics:$serverId:$songId';

  /// 本地歌曲歌词键：lyrics:local:{fingerprint}（fingerprint 即 local: 前缀后的部分）
  static String lyricsLocalKey(String fingerprint) =>
      'lyrics:local:$fingerprint';

  /// 兜底键：「标题|歌手」归一化（v4 之前的历史行全是这种键，保留可命中）
  static String lyricsFallbackKey(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';

  /// 按优先级依次尝试多个键读歌词
  static Future<String?> loadLyrics(List<String> lookupKeys) async {
    final db = await instance();
    for (final key in lookupKeys) {
      final rows = await db.query(
        'lyrics_local',
        where: 'lookup_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['content'] as String?;
    }
    return null;
  }

  /// 写入歌词：同时落主键与「标题|歌手」兜底键，
  /// 保证文件 mtime 变化导致 fingerprint 变化后歌词仍可通过兜底键命中。
  static Future<void> saveLyrics({
    required String lookupKey,
    required String fallbackKey,
    required String title,
    required String artist,
    required String content,
  }) async {
    final db = await instance();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in {lookupKey, fallbackKey}) {
      await db.insert('lyrics_local', {
        'lookup_key': key,
        'title': title,
        'artist': artist,
        'content': content,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
