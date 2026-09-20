/// 元数据插件契约：外部歌手头像 / 相似歌手 / 歌手简介的统一取数接口。
///
/// 实现方有两类：
/// - [DescriptorPlugin]：执行声明式 JSON 描述（官方模板与用户导入共用）
/// - 后续可能的内置 Dart 插件
///
/// 全部方法允许失败：失败时返回 null / 空列表，由编排器降级到下一个来源，
/// 不抛异常打断调用方。
abstract interface class MetadataPlugin {
  String get id;
  String get displayName;

  /// 歌手头像图片 URL；无结果返回 null
  Future<String?> fetchArtistAvatar(String artistName);

  /// 相似歌手名列表（App 侧负责映射回本地曲库）；无结果返回空列表
  Future<List<String>> fetchSimilarArtistNames(String artistName);

  /// 歌手简介纯文本（已去 HTML、已截断）；无结果返回 null
  Future<String?> fetchArtistBio(String artistName);
}
