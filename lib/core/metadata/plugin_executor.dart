import 'package:dio/dio.dart';

import 'metadata_plugin.dart';
import 'plugin_descriptor.dart';

/// JSON 拉取抽象：生产实现走 Dio（复用 NetworkRuntime 的代理/超时/证书
/// 配置），测试注入 fake。返回已解码的 Map/List；任何失败返回 null。
typedef JsonFetcher = Future<Object?> Function(
  Uri uri,
  Map<String, String> headers,
);

JsonFetcher dioJsonFetcher(Dio dio) => (uri, headers) async {
  try {
    final res = await dio.get<dynamic>(
      uri.toString(),
      options: Options(
        headers: headers,
        responseType: ResponseType.json,
        // 外部源内容各异，非 2xx/非 JSON 一律按无数据处理
        validateStatus: (code) => code != null && code >= 200 && code < 300,
      ),
    );
    final data = res.data;
    return (data is Map || data is List) ? data : null;
  } catch (_) {
    return null;
  }
};

/// 执行声明式描述的插件实现：官方模板与用户导入的第三方描述共用此类。
class DescriptorPlugin implements MetadataPlugin {
  DescriptorPlugin({
    required this.descriptor,
    required this.fetch,
    required this.readKey,
  });

  final PluginDescriptor descriptor;
  final JsonFetcher fetch;
  final Future<String?> Function() readKey;

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.name;

  @override
  Future<String?> fetchArtistAvatar(String artistName) async {
    final step = descriptor.avatar;
    if (step == null) return null;
    final prepared = await _prepare(step.url, artistName);
    if (prepared == null) return null;
    final value = extractJsonPath(
      await fetch(prepared.uri, prepared.headers),
      step.path,
    );
    final url = value?.toString() ?? '';
    return url.startsWith('https://') ? url : null;
  }

  @override
  Future<List<String>> fetchSimilarArtistNames(String artistName) async {
    final step = descriptor.similar;
    if (step == null) return const [];
    final first = await _prepare(step.url, artistName);
    if (first == null) return const [];
    final idValue =
        extractJsonPath(
          await fetch(first.uri, first.headers),
          step.idPath,
        )?.toString() ??
        '';
    if (idValue.isEmpty) return const [];
    final second = await _prepare(step.fetchUrl, artistName, idValue: idValue);
    if (second == null) return const [];
    final value = extractJsonPath(
      await fetch(second.uri, second.headers),
      step.path,
    );
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item != null && item.toString().isNotEmpty) item.toString(),
    ].take(step.limit).toList();
  }

  @override
  Future<String?> fetchArtistBio(String artistName) async {
    final step = descriptor.bio;
    if (step == null) return null;
    final prepared = await _prepare(step.url, artistName);
    if (prepared == null) return null;
    var root = await fetch(prepared.uri, prepared.headers);
    if (step.idPath != null && step.fetchUrl != null) {
      final idValue = extractJsonPath(root, step.idPath!)?.toString() ?? '';
      if (idValue.isEmpty) return null;
      final second = await _prepare(
        step.fetchUrl!,
        artistName,
        idValue: idValue,
      );
      if (second == null) return null;
      root = await fetch(second.uri, second.headers);
    }
    final value = extractJsonPath(root, step.path);
    var text = _stripHtml(value?.toString() ?? '').trim();
    if (text.isEmpty) return null;
    if (text.length > step.maxLength) {
      text = '${text.substring(0, step.maxLength)}…';
    }
    return text;
  }

  /// 占位符替换 + auth 注入（query 拼 URL / header 进请求头）。
  /// 返回 null：auth.required 且 key 未填（短路，不打必败请求），或 URL 非法
  Future<({Uri uri, Map<String, String> headers})?> _prepare(
    String template,
    String artistName, {
    String? idValue,
  }) async {
    var url = template.replaceAll('{artist}', Uri.encodeComponent(artistName));
    if (url.contains('{id}')) {
      if (idValue == null || idValue.isEmpty) return null;
      url = url.replaceAll('{id}', idValue);
    }
    final headers = Map.of(descriptor.headers);
    final auth = descriptor.auth;
    if (auth != null) {
      final key = (await readKey())?.trim() ?? '';
      if (key.isEmpty) {
        if (auth.required) return null;
      } else if (auth.type == 'query') {
        // 字符串层拼接，避免 Uri.replace 对已编码的 %XX 二次编码
        url +=
            '${url.contains('?') ? '&' : '?'}'
            '${Uri.encodeComponent(auth.param)}=${Uri.encodeComponent(key)}';
      } else {
        headers[auth.param] = key;
      }
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return (uri: uri, headers: headers);
  }

  /// 轻量 HTML 清洗（外部源简介常自带链接标签）：去标签 + 常见实体
  static String _stripHtml(String raw) {
    var text = raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&nbsp;': ' ',
    };
    entities.forEach((k, v) => text = text.replaceAll(k, v));
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }
}
