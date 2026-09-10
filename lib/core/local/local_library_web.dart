import '../models/models.dart';

/// web 端本地扫描占位：浏览器无文件系统访问（Phase 2 评估
/// File System Access API 选目录扫描），当前本地音乐段为空。
Future<List<Song>> scanLocalLibrary() async => const [];

Future<bool> ensureAudioPermission() async => true;
