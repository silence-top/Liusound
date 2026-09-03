import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放页唱片形态（§4.2）：
/// vinyl 经典黑胶（含唱针动画）｜cd 唱片｜square 方形玻璃卡片｜fullBlur 全屏模糊大图。
enum CoverStyle { vinyl, cd, square, fullBlur }

extension CoverStyleLabel on CoverStyle {
  String get label => switch (this) {
    CoverStyle.vinyl => '经典黑胶',
    CoverStyle.cd => 'CD 唱片',
    CoverStyle.square => '方形玻璃卡片',
    CoverStyle.fullBlur => '全屏模糊大图',
  };

  IconData get icon => switch (this) {
    CoverStyle.vinyl => Icons.album_outlined,
    CoverStyle.cd => Icons.disc_full_outlined,
    CoverStyle.square => Icons.crop_square_outlined,
    CoverStyle.fullBlur => Icons.blur_on_outlined,
  };

  /// 是否随播放旋转（方形卡片与全屏大图是静态展示）
  bool get spins => this == CoverStyle.vinyl || this == CoverStyle.cd;
}

class CoverStyleController extends Notifier<CoverStyle> {
  static const _key = 'cover_style';

  @override
  CoverStyle build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (saved == null) return;
      final style = CoverStyle.values.where((e) => e.name == saved).firstOrNull;
      if (style != null && style != state) state = style;
    });
    return CoverStyle.vinyl;
  }

  Future<void> setStyle(CoverStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

final coverStyleProvider = NotifierProvider<CoverStyleController, CoverStyle>(
  CoverStyleController.new,
);
