import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

import '../api/server_adapter.dart';
import '../models/models.dart';
import '../settings/streaming_prefs.dart';

/// web 端下载：Dio 拉取字节流 → Blob → a[download] 触发浏览器保存。
/// 代理/自签证书/hosts 映射不适用浏览器网络栈，仅应用超时与鉴权头生效。
/// 反查恒 null——浏览器无本地离线文件，web 播放恒走服务端流。
Future<String> downloadSongFile({
  required PlaybackSource source,
  required Song song,
  String serverId = '',
  NetworkSettings networkSettings = const NetworkSettings(),
  void Function(int received, int total)? onProgress,
}) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
      headers: source.headers.isNotEmpty ? source.headers : null,
    ),
  );
  try {
    final response = await dio.get<List<int>>(
      source.url,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgress,
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw Exception('下载内容为空');
    }
    // 按源文件真实容器命名（FLAC/M4A 等），无 suffix 时回退 mp3
    final suffix = song.suffix?.trim().toLowerCase() ?? '';
    final ext = suffix.isEmpty ? 'mp3' : suffix;
    final fileName = '${_safeName('${song.artist} - ${song.title}')}.$ext';

    final bytes = Uint8List.fromList(data);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..click();
    // 立即 revoke 可能打断尚未开始的下载，延迟回收
    unawaited(
      Future<void>.delayed(const Duration(minutes: 1), () {
        web.URL.revokeObjectURL(url);
      }),
    );
    return fileName;
  } finally {
    dio.close();
  }
}

/// 与 io 端同规则：文件名非法字符替换为下划线
String _safeName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

Future<String?> findDownloadedSong(Song song) async => null;
