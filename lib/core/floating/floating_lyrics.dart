import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics/lyrics.dart';
import '../theme/settings_prefs.dart';
import '../../features/player/player_controller.dart';

/// Android 悬浮歌词：平台通道控制 SYSTEM_ALERT_WINDOW 小窗显示当前歌词行。
/// 小窗可拖动、带关闭按钮，行为全部在原生侧；iOS 无对应能力，设置入口隐藏。
abstract final class FloatingLyrics {
  static const _channel = MethodChannel(
    'com.silencetop.liusound/floating_lyrics',
  );

  static bool get supported => Platform.isAndroid;

  static Future<bool> hasPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统「显示在其他应用上层」设置页，返回后调用方需复查 [hasPermission]
  static Future<void> requestPermission() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } catch (_) {}
  }

  static Future<void> update(String text) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('update', text);
    } catch (_) {}
  }

  static Future<void> hide() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }
}

/// 当前歌曲歌词数据（仅切歌时重新解析，供悬浮窗逐行取词）
final floatingLyricsDataProvider = Provider<LyricsData?>((ref) {
  final song = ref.watch(currentSongProvider);
  if (song == null) return null;
  return parseLyricsData(song.lyrics);
});

/// 悬浮歌词当前行：开关关闭/无歌曲/无歌词返回 null（监听方据此隐藏小窗）
final floatingLyricsLineProvider = Provider<String?>((ref) {
  if (!ref.watch(floatingLyricsProvider)) return null;
  final data = ref.watch(floatingLyricsDataProvider);
  if (data == null || data.lines.isEmpty) return null;
  final pos = ref.watch(positionProvider).valueOrNull;
  if (pos == null) return null;
  final idx = findLyricIndex(data.lines, pos.inMicroseconds / 1e6);
  return idx < 0 ? null : data.lines[idx].text;
});
