import 'dart:io';

import 'package:flutter/services.dart';

/// 下载歌曲的「公共音乐目录」落盘支持（让用户在文件管理器/其他播放器
/// 能看到并拷贝下载的歌曲）：
/// - Android 10+（API 29+）：经 MainActivity 的 media_store channel，
///   MediaStore 贡献式写入 /sdcard/Music/流声/，无需存储权限；
/// - Windows：用户音乐库下 流声\ 子目录（%USERPROFILE%\Music\流声）；
/// - 其余场景（iOS / Android 9- / channel 不可用 / 写入失败）：返回 null，
///   调用方回退应用私有 Documents/Music（旧行为）。
///
/// 公共目录与本地音乐扫描目录重叠，扫描侧按文件名指纹标记排除
/// （见 local_library.isDownloadedArtifact），避免同一首歌重复入库。
abstract final class PublicMusicStore {
  static const _channel = MethodChannel('com.silencetop.liusound/media_store');

  /// 公共目录下的应用子目录名（Android RELATIVE_PATH 与 Windows 同名）
  static const publicDirName = '流声';

  /// Android 10+ 通过 MediaStore 把下载临时文件落进公共 Music。
  /// 成功返回系统落盘的物理路径（临时文件由调用方删除）；
  /// 系统不支持 / channel 异常 / 写入失败一律返回 null（回退私有目录）。
  static Future<String?> saveToPublicMusic({
    required String sourcePath,
    required String fileName,
    required String title,
    required String artist,
    String album = '',
    int durationMs = 0,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('saveToMusic', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'relativePath': 'Music/$publicDirName',
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Windows 公共落盘目录（用户音乐库\流声）；非 Windows 返回 null
  static Directory? windowsPublicMusicDir() {
    if (!Platform.isWindows) return null;
    final home = Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    return Directory('$home\\Music\\$publicDirName');
  }
}
