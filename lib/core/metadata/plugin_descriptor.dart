import 'dart:convert';

/// 元数据插件 JSON 描述（v1，纯声明式，不含可执行代码）。
///
/// 一个描述声明若干「能力节」（avatar / similar / bio），每节是
/// HTTP 端点 + 响应提取路径；由执行器按节发起请求并提取结果。
/// 官方模板与用户导入的第三方描述走同一条执行管道。
///
/// schema 约束：
/// - `id`：`[a-z0-9_-]{1,64}`，插件唯一标识（启用状态/key/缓存的存储键）
/// - 所有 `url` 强制 https：导入的描述会在用户网络环境发请求，禁止明文
/// - `path`：点分提取路径，`|` 分隔备选路径（取首个非 null），数字段=数组
///   下标，`*`=数组通配展开（如 `data.0.picture_xl`、`data.*.name`）
/// - 占位符：`{artist}`=歌手名（URL 编码后替换），`{id}`=两步流第一步提取值
/// - `auth`：可选，声明 API key 的注入方式（query 参数 / 请求头）；
///   key 本体不写入描述，由用户在设置页填写、存安全存储
class PluginDescriptor {
  const PluginDescriptor({
    required this.id,
    required this.name,
    required this.version,
    this.auth,
    this.avatar,
    this.similar,
    this.bio,
    this.headers = const {},
  });

  final String id;
  final String name;
  final int version;
  final AuthSpec? auth;

  /// 头像能力节（一步流）：返回图片 URL
  final FetchStep? avatar;

  /// 相似歌手能力节（两步流）：先查歌手拿到 id，再取相似歌手名列表；
  /// 名字到本地曲库的映射由 App 侧编排器完成，描述不涉及播放
  final SimilarStep? similar;

  /// 简介能力节（一步或两步流）：返回文本，执行器统一做 HTML 清洗与截断；
  /// 两步流（idPath + fetchUrl）先查歌手拿 id 再取详情端点
  final BioStep? bio;

  /// 附加到该插件全部请求的请求头
  final Map<String, String> headers;

  bool get hasAnySection => avatar != null || similar != null || bio != null;

  static final _idPattern = RegExp(r'^[a-z0-9_-]{1,64}$');

  /// 解析并校验描述文本；不合法抛 [FormatException]（文案面向用户）
  static PluginDescriptor parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('插件描述不是合法 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('插件描述顶层必须是 JSON 对象');
    }
    final id = _str(decoded, 'id');
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('id 只允许小写字母/数字/下划线/短横线（1~64 位）');
    }
    final name = _str(decoded, 'name');
    if (name.isEmpty || name.length > 32) {
      throw const FormatException('name 必须是 1~32 位非空文本');
    }
    final headers = <String, String>{};
    final rawHeaders = decoded['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k is String && v is String) headers[k] = v;
      });
    }
    final descriptor = PluginDescriptor(
      id: id,
      name: name,
      version: (decoded['version'] as num?)?.toInt() ?? 1,
      auth: _parseAuth(decoded['auth']),
      avatar: _parseFetchStep(decoded['avatar']),
      similar: _parseSimilarStep(decoded['similar']),
      bio: _parseBioStep(decoded['bio']),
      headers: headers,
    );
    if (!descriptor.hasAnySection) {
      throw const FormatException('描述至少要包含 avatar / similar / bio 之一');
    }
    return descriptor;
  }

  static AuthSpec? _parseAuth(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final type = _str(raw, 'type');
    if (type != 'query' && type != 'header') {
      throw const FormatException('auth.type 只允许 query 或 header');
    }
    final param = _str(raw, 'param');
    if (param.isEmpty) throw const FormatException('auth.param 不能为空');
    return AuthSpec(
      type: type,
      param: param,
      label: _str(raw, 'label').isEmpty ? 'API Key' : _str(raw, 'label'),
      hint: _str(raw, 'hint'),
      required: raw['required'] == true,
    );
  }

  static FetchStep? _parseFetchStep(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('能力节必须是对象');
    }
    return FetchStep(url: _requireUrl(raw), path: _requirePath(raw));
  }

  static SimilarStep? _parseSimilarStep(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('能力节必须是对象');
    }
    final step = SimilarStep(
      url: _requireUrl(raw),
      idPath: _requirePath(raw, key: 'idPath'),
      fetchUrl: _requireUrl(raw, key: 'fetchUrl'),
      path: _requirePath(raw),
      limit: (raw['limit'] as num?)?.toInt() ?? 8,
    );
    if (!step.url.contains('{artist}') || !step.fetchUrl.contains('{id}')) {
      throw const FormatException('similar.url 须含 {artist}，fetchUrl 须含 {id}');
    }
    return step;
  }

  static BioStep? _parseBioStep(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('能力节必须是对象');
    }
    final idPath = _str(raw, 'idPath');
    final fetchUrl = _str(raw, 'fetchUrl');
    if (idPath.isEmpty != fetchUrl.isEmpty) {
      throw const FormatException('bio 两步流须同时提供 idPath 与 fetchUrl');
    }
    if (fetchUrl.isNotEmpty && !fetchUrl.contains('{id}')) {
      throw const FormatException('bio.fetchUrl 须含 {id}');
    }
    return BioStep(
      url: _requireUrl(raw),
      path: _requirePath(raw),
      maxLength: (raw['maxLength'] as num?)?.toInt() ?? 2000,
      idPath: idPath.isEmpty ? null : idPath,
      fetchUrl: fetchUrl.isEmpty ? null : fetchUrl,
    );
  }

  static String _requireUrl(Map<String, dynamic> raw, {String key = 'url'}) {
    final url = _str(raw, key);
    if (url.isEmpty) throw FormatException('$key 不能为空');
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw FormatException('$key 必须是合法的 https 地址');
    }
    return url;
  }

  static String _requirePath(Map<String, dynamic> raw, {String key = 'path'}) {
    final path = _str(raw, key);
    if (path.isEmpty) throw FormatException('$key 不能为空');
    return path;
  }

  static String _str(Map<String, dynamic> raw, String key) =>
      raw[key]?.toString() ?? '';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    if (auth != null)
      'auth': {
        'type': auth!.type,
        'param': auth!.param,
        'label': auth!.label,
        if (auth!.hint.isNotEmpty) 'hint': auth!.hint,
        if (auth!.required) 'required': true,
      },
    if (avatar != null) 'avatar': {'url': avatar!.url, 'path': avatar!.path},
    if (similar != null)
      'similar': {
        'url': similar!.url,
        'idPath': similar!.idPath,
        'fetchUrl': similar!.fetchUrl,
        'path': similar!.path,
        'limit': similar!.limit,
      },
    if (bio != null)
      'bio': {
        'url': bio!.url,
        if (bio!.idPath != null) 'idPath': bio!.idPath,
        if (bio!.fetchUrl != null) 'fetchUrl': bio!.fetchUrl,
        'path': bio!.path,
        'maxLength': bio!.maxLength,
      },
    if (headers.isNotEmpty) 'headers': headers,
  };
}

/// API key 注入声明；key 为空且 [required] 时执行器短路不发请求
class AuthSpec {
  const AuthSpec({
    required this.type,
    required this.param,
    required this.label,
    required this.hint,
    required this.required,
  });

  /// `query`（拼到 URL）或 `header`（附加请求头）
  final String type;
  final String param;
  final String label;
  final String hint;
  final bool required;
}

class FetchStep {
  const FetchStep({required this.url, required this.path});

  final String url;
  final String path;
}

class SimilarStep {
  const SimilarStep({
    required this.url,
    required this.idPath,
    required this.fetchUrl,
    required this.path,
    required this.limit,
  });

  final String url;
  final String idPath;
  final String fetchUrl;
  final String path;
  final int limit;
}

class BioStep extends FetchStep {
  const BioStep({
    required super.url,
    required super.path,
    required this.maxLength,
    this.idPath,
    this.fetchUrl,
  });

  final int maxLength;

  /// 两步流：先请求 [url] 按 [idPath] 提取 id，再请求含 {id} 的 [fetchUrl]；
  /// 为 null 时一步直达
  final String? idPath;
  final String? fetchUrl;
}

/// 按点分路径从已解码 JSON 中提取值。
/// `|` 分隔备选路径（从左到右取第一个非 null 者，本地化字段兜底如
/// `artists.0.strBiographyCN|artists.0.strBiographyEN`）；
/// 数字段=数组下标（越界返回 null），`*`=对当前 List 每个元素提取剩余
/// 路径后收集为 List（跳过 null）；任何类型不匹配返回 null。
Object? extractJsonPath(Object? root, String path) {
  if (root == null || path.isEmpty) return null;
  for (final alternative in path.split('|')) {
    final value = _extract(root, alternative.trim());
    if (value != null) return value;
  }
  return null;
}

Object? _extract(Object? root, String path) {
  if (root == null || path.isEmpty) return null;
  final segments = path.split('.');
  Object? current = root;
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    if (seg == '*') {
      if (current is! List) return null;
      final rest = segments.sublist(i + 1);
      if (rest.isEmpty) return current;
      final out = <Object?>[];
      for (final item in current) {
        final value = _walk(item, rest, 0);
        if (value != null) out.add(value);
      }
      return out;
    }
    current = _step(current, seg);
    if (current == null) return null;
  }
  return current;
}

Object? _walk(Object? node, List<String> segments, int index) {
  if (index >= segments.length) return node;
  if (node == null) return null;
  final next = _step(node, segments[index]);
  return _walk(next, segments, index + 1);
}

Object? _step(Object? node, String seg) {
  if (node is List) {
    final idx = int.tryParse(seg);
    if (idx == null || idx < 0 || idx >= node.length) return null;
    return node[idx];
  }
  if (node is Map) return node[seg];
  return null;
}
