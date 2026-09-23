import 'dart:async';

import 'package:dio/dio.dart';

import 'metadata_plugin.dart';
import 'plugin_descriptor.dart';

/// JSON 拉取抽象：返回已解码的 Map/List；失败必须抛出，不能伪装成空结果。
typedef JsonFetcher = Future<Object?> Function(
  Uri uri,
  Map<String, String> headers,
);

/// 不携带原始异常、URL、响应或请求头，防止 query/header 中的 key 泄漏。
class MetadataFetchException implements Exception {
  const MetadataFetchException();

  @override
  String toString() => 'Metadata plugin request failed';
}

JsonFetcher dioJsonFetcher(Dio dio, {CancelToken? cancelToken}) =>
    (uri, headers) async {
      try {
        final res = await dio
            .get<dynamic>(
              uri.toString(),
              cancelToken: cancelToken,
              options: Options(
                headers: headers,
                responseType: ResponseType.json,
                validateStatus: (code) =>
                    code != null && code >= 200 && code < 300,
              ),
            )
            .timeout(const Duration(seconds: 3));
        // 204 是明确的空响应；200 的非 JSON 响应是解析失败。
        if (res.statusCode == 204) return <String, Object?>{};
        return _validateResponse(res.data);
      } catch (_) {
        throw const MetadataFetchException();
      }
    };

Object _validateResponse(Object? data) {
  if (data is! Map && data is! List) throw const MetadataFetchException();
  if (data is Map) {
    bool hasError(Object? value) =>
        value != null &&
        value != false &&
        value != 0 &&
        value != '' &&
        !(value is Iterable && value.isEmpty) &&
        !(value is Map && value.isEmpty);
    // Last.fm / Deezer 等会用 HTTP 200 携带鉴权或上游错误。
    if (hasError(data['error']) ||
        hasError(data['errors']) ||
        data['success'] == false ||
        data['status'] == 'failed' ||
        data['status'] == 'error') {
      throw const MetadataFetchException();
    }
  }
  return data!;
}

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

  Future<Object> _fetch(Uri uri, Map<String, String> headers) async {
    try {
      return _validateResponse(await fetch(uri, headers));
    } catch (_) {
      throw const MetadataFetchException();
    }
  }

  String _text(Object? value) {
    if (value == null) return '';
    if (value is! String) throw const MetadataFetchException();
    return value.trim();
  }

  String _id(Object? value) {
    if (value == null) return '';
    if (value is! String && value is! num) {
      throw const MetadataFetchException();
    }
    return value.toString().trim();
  }

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
      await _fetch(prepared.uri, prepared.headers),
      step.path,
    );
    final url = _text(value);
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const MetadataFetchException();
    }
    return url;
  }

  @override
  Future<List<String>> fetchSimilarArtistNames(String artistName) async {
    final step = descriptor.similar;
    if (step == null) return const [];
    final first = await _prepare(step.url, artistName);
    if (first == null) return const [];
    final searchRoot = await _fetch(first.uri, first.headers);
    final idValue = _id(extractJsonPath(searchRoot, step.idPath));
    if (idValue.isEmpty) return const [];
    // 搜索首个候选常是重名占位条目，最多尝试三个候选。
    final candidates = <String>{
      idValue,
      ..._siblingIds(searchRoot, step.idPath),
    };
    var failed = false;
    for (final id in candidates.take(3)) {
      try {
        final second = await _prepare(step.fetchUrl, artistName, idValue: id);
        if (second == null) continue;
        final value = extractJsonPath(
          await _fetch(second.uri, second.headers),
          step.path,
        );
        if (value == null) continue;
        if (value is! List) throw const MetadataFetchException();
        final names = value.map(_text).where((name) => name.isNotEmpty);
        if (names.isNotEmpty) return names.take(step.limit).toList();
      } catch (_) {
        failed = true;
      }
    }
    if (failed) throw const MetadataFetchException();
    return const [];
  }

  /// 用 idPath 的通配形式（数字段 → *）提取搜索结果里的全部候选 id
  List<String> _siblingIds(Object? searchRoot, String idPath) {
    final wildcard = idPath
        .split('|')
        .map(
          (alt) => alt
              .trim()
              .split('.')
              .map((seg) => int.tryParse(seg) == null ? seg : '*')
              .join('.'),
        )
        .join('|');
    if (wildcard == idPath) return const [];
    final value = extractJsonPath(searchRoot, wildcard);
    if (value is! List) return const [];
    return value.map(_id).where((id) => id.isNotEmpty).toList();
  }

  @override
  Future<String?> fetchArtistBio(String artistName) async {
    final step = descriptor.bio;
    if (step == null) return null;
    final prepared = await _prepare(step.url, artistName);
    if (prepared == null) return null;
    var root = await _fetch(prepared.uri, prepared.headers);
    if (step.idPath != null && step.fetchUrl != null) {
      final idValue = _id(extractJsonPath(root, step.idPath!));
      if (idValue.isEmpty) return null;
      final second = await _prepare(
        step.fetchUrl!,
        artistName,
        idValue: idValue,
      );
      if (second == null) return null;
      root = await _fetch(second.uri, second.headers);
    }
    final value = extractJsonPath(root, step.path);
    var text = _stripHtml(_text(value)).trim();
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
      url = url.replaceAll('{id}', Uri.encodeComponent(idValue));
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
