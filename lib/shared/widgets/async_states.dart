import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

/// 异步列表三态统一渲染（loading / error 可重试 / 空态 / 数据）。
///
/// 语义：`data == null` 时才显示 loading/error（刷新时保留旧数据）；
/// data 非空直接交给 onData 渲染，data 为空列表显示 emptyText。
/// 所有列表页共用同一套视觉，避免每个页面手写三态块。

const _kStatePadding = EdgeInsets.all(AppSpacing.xxxl);
// 弱化态辅助文本（辅助字阶 14，仅降透明度）
const _kStateStyle = TextStyle(color: Colors.white38, fontSize: 14);

Widget _loading() => const Padding(
      padding: _kStatePadding,
      child: Center(child: CircularProgressIndicator()),
    );

Widget _error(VoidCallback onRetry) => Padding(
      padding: _kStatePadding,
      child: Center(
        child: TextButton(
          onPressed: onRetry,
          child: const Text('加载失败，点击重试', style: _kStateStyle),
        ),
      ),
    );

Widget _empty(String text) => Padding(
      padding: _kStatePadding,
      child: Center(child: Text(text, style: _kStateStyle)),
    );

/// Sliver 版：直接展开塞进 CustomScrollView 的 slivers。
///
/// ```dart
/// ...sliverAsyncGuard(
///   async: songsAsync,
///   emptyText: '专辑暂无歌曲',
///   onRetry: () => ref.invalidate(albumSongsProvider(id)),
///   onData: (songs) => [SliverList(...), const SliverToBoxAdapter(...)],
/// )
/// ```
List<Widget> sliverAsyncGuard<T>({
  required AsyncValue<List<T>> async,
  required List<Widget> Function(List<T> data) onData,
  required String emptyText,
  required VoidCallback onRetry,
}) {
  final data = async.value;
  if (data == null) {
    if (async.isLoading) return [SliverToBoxAdapter(child: _loading())];
    if (async.hasError) return [SliverToBoxAdapter(child: _error(onRetry))];
  }
  if (data == null || data.isEmpty) {
    return [SliverToBoxAdapter(child: _empty(emptyText))];
  }
  return onData(data);
}

/// Box 版：用于 Scaffold body（普通 ListView/GridView 页面）。
Widget asyncStateBox<T>({
  required AsyncValue<List<T>> async,
  required Widget Function(List<T> data) onData,
  required String emptyText,
  required VoidCallback onRetry,
}) {
  final data = async.value;
  if (data == null) {
    if (async.isLoading) return _loading();
    if (async.hasError) return _error(onRetry);
  }
  if (data == null || data.isEmpty) return _empty(emptyText);
  return onData(data);
}

/// 过滤框搜不到结果时的紧凑空态（区别于整页空态的 48 padding）。
Widget noMatchBox() => Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(child: Text('没有匹配的歌曲', style: _kStateStyle)),
    );
