import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/adapter_provider.dart';
import '../core/api/server_adapter.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/motion_tokens.dart';

/// 统一封面组件：
/// - localCover 非空时优先展示本地内嵌封面文件（本地扫描歌曲）
/// - ServerAdapter coverImage（服务端裁剪，源尺寸按显示尺寸×DPR 分档 300/600/900/1200）
/// - memCacheWidth 按显示尺寸 × DPR 动态限制解码尺寸，
///   避免小图（列表 44px）也解码到大尺寸的内存浪费（性能红线）
/// - 磁盘 LRU 缓存 + 默认占位图
/// 封面源尺寸分档：显示尺寸 × DPR 量化到最近的档位，
/// 控制 CachedNetworkImage 的 URL 变体数（同图跨页复用缓存）。
/// 大封面（全屏播放器 ~300-400 逻辑 px）在 3x 屏需要 >900px 源，
/// 恒取 300px 源会明显偏糊。
int _coverSourceSize(BuildContext context, double displaySize) {
  final px = (displaySize * MediaQuery.devicePixelRatioOf(context)).round();
  const tiers = [300, 600, 900, 1200];
  for (final t in tiers) {
    if (px <= t) return t;
  }
  return tiers.last;
}

class CoverArt extends ConsumerWidget {
  const CoverArt({
    super.key,
    required this.albumId,
    this.size = 120,
    this.radius = AppRadius.m,
    this.localCover,
  });

  final String albumId;
  final double size;
  final double radius;

  /// 本地歌曲内嵌封面文件路径（已由本地扫描抽取）
  final String? localCover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(serverAdapterProvider);
    final placeholder = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/app/default-album.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    // 文件缺失（被外部清理等极端情况）由 errorBuilder 兜底回退占位图；
    // 不在 build 中做 existsSync 同步磁盘 stat（性能红线：本地库列表滚动
    // 时每个 item build 都会触发，同步 I/O 阻塞 UI 线程）
    final coverFile = localCover == null ? null : File(localCover!);
    if (coverFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          coverFile,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }

    if (albumId.isEmpty) return placeholder;

    final ImageSource? coverSrc = adapter?.coverImage(
      albumId,
      size: _coverSourceSize(context, size),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: coverSrc?.url ?? '',
        httpHeaders: coverSrc?.headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        fadeInDuration: MotionTokens.durationFast,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

/// 无图实体的封面回退：实体（歌手等）本身取不到图时，
/// 用其第一首歌的专辑封面。仅由 [EntityCover] 的加载失败分支触发，
/// 有图的实体不会产生额外请求。
final entityFallbackCoverProvider = FutureProvider.family<ImageSource?, String>(
  (ref, entityId) async {
    final adapter = ref.watch(serverAdapterProvider);
    if (adapter == null) return null;
    final songs = await adapter.fetchArtistSongs(entityId, limit: 1);
    final albumId = songs.isEmpty ? '' : songs.first.albumId;
    if (albumId.isEmpty) return null;
    return adapter.coverImage(albumId);
  },
);

/// 实体封面组件（歌手/专辑艺术家等）：优先展示实体自身图片，
/// 加载失败（服务端没配图返回 404）时回退第一首歌的专辑封面。
class EntityCover extends ConsumerWidget {
  const EntityCover({
    super.key,
    required this.entityId,
    this.size = 120,
    this.radius = AppRadius.m,
  });

  final String entityId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(serverAdapterProvider);
    final placeholder = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/app/default-album.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    if (entityId.isEmpty || adapter == null) return placeholder;

    final ImageSource? coverSrc = adapter.coverImage(
      entityId,
      size: _coverSourceSize(context, size),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: coverSrc?.url ?? '',
        httpHeaders: coverSrc?.headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        fadeInDuration: MotionTokens.durationFast,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => _EntityFallbackCover(
          entityId: entityId,
          size: size,
          radius: radius,
        ),
      ),
    );
  }
}

class _EntityFallbackCover extends ConsumerWidget {
  const _EntityFallbackCover({
    required this.entityId,
    required this.size,
    required this.radius,
  });

  final String entityId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/app/default-album.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
    final src = ref.watch(entityFallbackCoverProvider(entityId)).valueOrNull;
    if (src == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: src.url,
      httpHeaders: src.headers.isNotEmpty ? src.headers : null,
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}
