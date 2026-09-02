import 'package:flutter/material.dart';

/// 全局主题（对齐 1.x 配色）：
/// 页面背景 #001B2E、框架/播放器 #0a1428、卡片 #1a2c3a、主色 #2196F3。
/// 所有页面禁止再手写这些色值，一律引用此处常量，保证全局一致。
abstract final class AppTheme {
  static const primary = Color(0xFF2196F3); // 主蓝（按钮/激活态）
  static const background = Color(0xFF001B2E); // 页面背景（首页/搜索/登录）
  static const shell = Color(0xFF0A1428); // 主框架与全屏播放器背景
  static const detailBg = Color(0xFF0A1A2A); // 详情/列表二级页背景
  static const bar = Color(0xFF222B3A); // 详情页全播栏
  static const surface = Color(0xFF1A2C3A); // 卡片 / 输入框
  static const searchbar = Color(0xFF13304a); // 首页装饰搜索栏 / Tab 激活背景
  static const miniPlayer = Color(0xFF8B8A5F); // 迷你播放条胶囊（军绿，对齐设计图）
  static const queuePanel = Color(0xFF23272E); // 播放队列弹窗 / 底部操作面板
  static const queueActive = Color(0xFF1EB4FF); // 队列当前播放项（蓝，对齐设计图）

  // 文本灰阶（标题走 textTheme 白色，此处只收弱化层级）
  static const textDim = Color(0xFF888888); // 次要文本 / 弱图标
  static const textFaint = Color(0xFF444444); // 装饰图标 / 占位

  // 点缀色
  static const indexGreen = Color(0xFF3EC06C); // 歌曲序号绿
  static const accentSoft = Color(0xFF9EC1F0); // 操作网格柔和蓝
  static const heartRed = Color(0xFFE57373); // 收藏 / 危险操作
  static const actionBlue = Color(0xFFB2D7F7); // 详情页操作图标
  static const formatBorder = Color(0xFF7ECFFF); // 无损格式标签
  static const formatBg = Color(0x593C5078); // rgba(60,80,120,0.35)
  static const formatText = Color(0xFFE0F6FF);

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
      // 统一文本基线：未显式指定样式的 Text 自动获得深色背景下的可读样式
      textTheme: const TextTheme(
        headlineSmall:
            TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        titleLarge:
            TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        titleMedium:
            TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 15),
        bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
        bodySmall: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
        labelLarge:
            TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: Colors.white38, fontSize: 12),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
      ),
      dividerTheme: const DividerThemeData(color: Color(0x14FFFFFF)), // 统一 8% 白分隔线
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
