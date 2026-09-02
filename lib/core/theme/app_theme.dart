import 'package:flutter/material.dart';

/// 全局主题：深色 Material 3（对标 1.x 深色 UI，主色 #2196F3）
abstract final class AppTheme {
  static const _seed = Color(0xFF2196F3);
  static const _background = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: _surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _background,
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        indicatorColor: _seed.withValues(alpha: 0.25),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? _seed : Colors.white70,
          ),
        ),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _seed,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
