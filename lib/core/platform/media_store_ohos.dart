import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'media_store.dart';

/// 鸿蒙（OpenHarmony）：公共音乐目录经 ArkTS 原生侧查询（沙箱外公共
/// 目录访问需原生 API）。通道协议对齐 Android media_store：ArkTS 侧
/// 实现 `publicMusicDir` 返回绝对路径（含 流声/ 子目录）；
/// 未实现/异常一律返回 null，download_service 回退私有 Documents/Music。
/// ⚠️ ArkTS 原生侧待 ohos/ 目录生成后补齐（Phase 6 环境限制）。
final class MediaStoreOhos implements MediaStore {
  static const _channel = MethodChannel(
    'com.silencetop.liusound/media_store_ohos',
  );

  @override
  Future<String?> saveToPublicMusic({
    required String sourcePath,
    required String fileName,
    required String title,
    required String artist,
    String album = '',
    int durationMs = 0,
  }) async {
    final dirPath = await publicMusicDir();
    if (dirPath == null) return null;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final target = File(p.join(dir.path, fileName));
      if (await target.exists()) await target.delete();
      final source = File(sourcePath);
      await source.rename(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> publicMusicDir() async {
    try {
      return await _channel.invokeMethod<String>('publicMusicDir');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
