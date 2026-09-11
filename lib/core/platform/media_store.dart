/// 下载歌曲的「公共音乐目录」落盘门面（让用户在文件管理器/其他播放器
/// 能看到并拷贝下载的歌曲）。实现按平台分文件：
/// - Android：MediaStore 贡献式写入 /sdcard/Music/流声/（无需存储权限）
/// - Windows：用户音乐库下 流声\ 子目录
/// - macOS：真实音乐目录 ~/Music/流声（沙盒 assets.music 授权）
/// - Linux：XDG 音乐目录 ~/Music/流声
/// - web：浏览器下载已实现；iOS/Documents 已实现；鸿蒙经 ArkTS 通道（原生侧待补）
library;

import 'media_store_web.dart'
    if (dart.library.io) 'media_store_io.dart'
    show createMediaStore;
export 'media_store_web.dart' if (dart.library.io) 'media_store_io.dart';

/// 公共目录下的应用子目录名（各平台同名）
const publicMusicDirName = '流声';

/// 全局单例（业务侧直接 `mediaStore.xxx`）
final MediaStore mediaStore = createMediaStore();

/// 把下载临时文件落进公共音乐目录。
/// 成功返回系统落盘的物理路径（临时文件由调用方删除）；
/// 平台不支持 / 写入失败一律返回 null（调用方回退应用私有目录）。
abstract interface class MediaStore {
  Future<String?> saveToPublicMusic({
    required String sourcePath,
    required String fileName,
    required String title,
    required String artist,
    String album = '',
    int durationMs = 0,
  });

  /// 删除公共音乐目录中的指定文件。
  /// 成功返回 true；文件不存在/平台不支持/删除失败返回 false。
  Future<bool> deleteFromPublicMusic({
    required String fileName,
  });

  /// 公共音乐落盘目录的绝对路径（含应用子目录）；平台不支持返回 null
  Future<String?> publicMusicDir();
}
