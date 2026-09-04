import 'package:flutter/material.dart';

import 'app_skin.dart';
import 'skin_tokens.dart';

/// 间距标尺（对齐 2.1 设计系统：8pt 基 + 4 半步）
/// features 层 EdgeInsets 一律引用此处，禁止手写标尺外数值
abstract final class AppSpacing {
  static const double xs = 4; // 文本行内微间隙
  static const double s = 8; // 行内默认间隙
  static const double m = 12; // 紧凑留白 / 列表行距
  static const double l = 16; // 页边距 / 卡片内边距
  static const double xl = 24; // 分区间距
  static const double xxl = 32; // 大区块间距
  static const double xxxl = 48; // 异步态留白
  static const double huge = 64; // 滚动尾部安全区
}

/// 圆角档位（对齐 2.1 设计系统）；GlassTokens 三个旧圆角已对齐此表
abstract final class AppRadius {
  static const double s = 8; // 徽标 / 内嵌块 / 拖动代理
  static const double m = 12; // 输入框 / 封面
  static const double l = 16; // 卡片（= GlassTokens.radiusCard）
  static const double xl = 24; // 底部弹层（= GlassTokens.radiusSheet）
  static const double xxl = 32; // 全屏播放器大容器
  static const double pill = 999; // 胶囊全圆（= GlassTokens.radiusPill）
}

/// const 上下文可用的字阶样式（不能引 Theme 的共享件用这里；
/// Widget 内优先用 Theme.of(context).textTheme 对应槽位）
abstract final class AppText {
  static const h1 = TextStyle(
    color: Colors.white,
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );
  static const h2 = TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );
  static const h3 = TextStyle(
    color: Colors.white,
    fontSize: 19,
    fontWeight: FontWeight.w500,
  );
  static const body = TextStyle(color: Colors.white, fontSize: 16);
  static const aux = TextStyle(color: Colors.white, fontSize: 14);
  static const caption = TextStyle(color: Color(0xFFBBBBBB), fontSize: 12);
}

/// 全局主题（对齐 1.x 配色）：
/// 皮肤相关色（背景/面/文本灰阶）随 AppSkin 走 SkinTokens，经 context 读取；
/// 点缀/装饰色与皮肤无关，保持 const。所有页面禁止再手写这些色值。
abstract final class AppTheme {
  static const primary = Color(0xFF2196F3); // 主蓝（按钮/激活态默认值）
  static const bar = Color(0xFF222B3A); // 详情页全播栏
  static const searchbar = Color(0xFF13304a); // 首页装饰搜索栏 / Tab 激活背景
  static const miniPlayer = Color(0xFF8B8A5F); // 迷你播放条胶囊（军绿，对齐设计图）
  static const queuePanel = Color(0xFF23272E); // 播放队列弹窗 / 底部操作面板
  static const queueActive = Color(0xFF1EB4FF); // 队列当前播放项（蓝，对齐设计图）

  // ---- 皮肤相关色（context 访问器） ----
  static Color backgroundOf(BuildContext c) => SkinTokens.of(c).background;
  static Color shellOf(BuildContext c) => SkinTokens.of(c).shell;
  static Color detailBgOf(BuildContext c) => SkinTokens.of(c).detailBg;
  static Color surfaceOf(BuildContext c) => SkinTokens.of(c).surface;
  static Color textDimOf(BuildContext c) => SkinTokens.of(c).textDim;
  static Color textFaintOf(BuildContext c) => SkinTokens.of(c).textFaint;

  // 点缀色
  static const indexGreen = Color(0xFF3EC06C); // 歌曲序号绿
  static const accentSoft = Color(0xFF9EC1F0); // 操作网格柔和蓝
  static const heartRed = Color(0xFFE57373); // 收藏 / 危险操作
  static const actionBlue = Color(0xFFB2D7F7); // 详情页操作图标
  static const formatBorder = Color(0xFF7ECFFF); // 无损格式标签
  static const formatBg = Color(0x593C5078); // rgba(60,80,120,0.35)
  static const formatText = Color(0xFFE0F6FF);

  static ThemeData get dark => build(AppSkin.liquidGlass, primary);

  /// 按皮肤 + 主题色构建深色 ThemeData（§8.1 / P1 主题系统化）：
  /// ColorScheme.fromSeed 会做 tone-mapping，这里用 copyWith(primary:) 强制
  /// 主色等于用户选的色值，保证按钮/激活态颜色与预设完全一致。
  static ThemeData build(AppSkin skin, Color accentColor) {
    final t = SkinTokens.forSkin(skin);
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
      surface: t.surface,
    ).copyWith(primary: accentColor);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      extensions: [t],
      // 统一文本基线（对齐 2.1 字阶：H1 28 / H2 22 / H3 19 / 正文 16 / 辅助 14 / 说明 12）：
      // 未显式指定样式的 Text 自动获得深色背景下的可读样式
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
        bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
        bodySmall: TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
        labelLarge: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: TextStyle(color: Colors.white38, fontSize: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: t.divider),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
