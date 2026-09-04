import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自定义背景图状态（§8.1）：路径 + 不透明度 + 模糊度，全部持久化。
/// path 为 null 表示未设置，此时 AmbientBackground 只渲染默认光斑。
class BackgroundConfig {
  const BackgroundConfig({this.path, this.opacity = 0.35, this.blur = 8.0});
  final String? path;
  final double opacity;
  final double blur;

  BackgroundConfig copyWith({String? path, double? opacity, double? blur}) =>
      BackgroundConfig(
        path: path ?? this.path,
        opacity: opacity ?? this.opacity,
        blur: blur ?? this.blur,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundConfig &&
          path == other.path &&
          opacity == other.opacity &&
          blur == other.blur;

  @override
  int get hashCode => Object.hash(path, opacity, blur);
}

class BackgroundController extends Notifier<BackgroundConfig> {
  static const _pathKey = 'bg_image_path';
  static const _opacityKey = 'bg_opacity';
  static const _blurKey = 'bg_blur';

  @override
  BackgroundConfig build() {
    SharedPreferences.getInstance().then((prefs) async {
      final p = prefs.getString(_pathKey);
      final o = prefs.getDouble(_opacityKey) ?? 0.35;
      final b = prefs.getDouble(_blurKey) ?? 8.0;
      // 文件被删了就当没设过
      if (p != null && !File(p).existsSync()) {
        await prefs.remove(_pathKey);
        return;
      }
      final cfg = BackgroundConfig(path: p, opacity: o, blur: b);
      if (cfg != state) state = cfg;
    });
    return const BackgroundConfig();
  }

  Future<void> setImage(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}${Platform.pathSeparator}custom_bg.png';
    await File(sourcePath).copy(dest);
    await _save(path: dest);
  }

  Future<void> clearImage() async {
    final cfg = state;
    if (cfg.path != null) {
      try {
        await File(cfg.path!).delete();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pathKey);
    state = BackgroundConfig(opacity: cfg.opacity, blur: cfg.blur);
  }

  Future<void> setOpacity(double v) async => _save(opacity: v);
  Future<void> setBlur(double v) async => _save(blur: v);

  Future<void> _save({String? path, double? opacity, double? blur}) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null) await prefs.setString(_pathKey, path);
    if (opacity != null) await prefs.setDouble(_opacityKey, opacity);
    if (blur != null) await prefs.setDouble(_blurKey, blur);
    state = state.copyWith(path: path, opacity: opacity, blur: blur);
  }
}

final backgroundProvider =
    NotifierProvider<BackgroundController, BackgroundConfig>(
      BackgroundController.new,
    );
