import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/server_adapter.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_controller.dart';

/// 统一封面组件：
/// - localCover 非空时优先展示本地内嵌封面文件（本地扫描歌曲）
/// - ServerAdapter coverImage（服务端 300px 裁剪）
/// - memCacheWidth 按显示尺寸 × DPR 动态限制解码尺寸（上限 300），
///   避免小图（列表 44px）也解码到 300px 的内存浪费（性能红线）
/// - 磁盘 LRU 缓存 + 默认占位图
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

    final coverFile = localCover == null ? null : File(localCover!);
    if (coverFile != null && coverFile.existsSync()) {
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

    final ImageSource? coverSrc = adapter?.coverImage(albumId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: coverSrc?.url ?? '',
        httpHeaders: coverSrc?.headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(80, 300),
        fadeInDuration: const Duration(milliseconds: 150),
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

    final ImageSource? coverSrc = adapter.coverImage(entityId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: coverSrc?.url ?? '',
        httpHeaders: coverSrc?.headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(80, 300),
        fadeInDuration: const Duration(milliseconds: 150),
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
      memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(80, 300),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}
