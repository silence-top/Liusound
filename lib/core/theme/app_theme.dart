import 'package:flutter/material.dart';

/// 全局主题（对齐 1.x 配色）：
/// 页面背景 #001B2E、框架/播放器 #0a1428、卡片 #1a2c3a、主色 #2196F3。
abstract final class AppTheme {
  static const primary = Color(0xFF2196F3); // 主蓝（按钮/激活态）
  static const background = Color(0xFF001B2E); // 页面背景（首页/搜索/登录）
  static const shell = Color(0xFF0A1428); // 主框架与全屏播放器背景
  static const surface = Color(0xFF1A2C3A); // 卡片 / 输入框
  static const searchbar = Color(0xFF13304a); // 首页装饰搜索栏 / Tab 激活背景
  static const miniPlayer = Color(0xFF8B8A5F); // 迷你播放条胶囊（军绿，对齐设计图）
  static const queuePanel = Color(0xFF23272E); // 播放队列弹窗
  static const queueActive = Color(0xFF1EB4FF); // 队列当前播放项（蓝，对齐设计图）

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
