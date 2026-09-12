import 'package:flutter/services.dart';

import 'media_store.dart';

/// Android 10+（API 29+）：经 MainActivity 的 media_store channel，
/// MediaStore 贡献式写入 /sdcard/Music/流声/，无需存储权限。
final class MediaStoreAndroid implements MediaStore {
  static const _channel = MethodChannel('com.silencetop.liusound/media_store');

  @override
  Future<String?> saveToPublicMusic({
    required String sourcePath,
    required String fileName,
    required String title,
    required String artist,
    String album = '',
    int durationMs = 0,
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveToMusic', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'relativePath': 'Music/$publicMusicDirName',
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

  @override
  Future<bool> deleteFromPublicMusic({required String fileName}) async {
    try {
      final result = await _channel.invokeMethod<bool>('deleteFromMusic', {
        'fileName': fileName,
        'relativePath': 'Music/$publicMusicDirName',
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> publicMusicDir() async => null;
}
