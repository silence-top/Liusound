import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/local_fs.dart';
import '../settings/prefs.dart';

/// 自定义背景图状态（§8.1）：路径 + 不透明度 + 模糊度，全部持久化。
/// path 为 null 表示未设置，此时 AmbientBackground 渲染各皮肤专属舞台。
/// 设了图则图片即背景（最高优先级，全皮肤生效）。
class BackgroundConfig {
  const BackgroundConfig({this.path, this.opacity = 0.85, this.blur = 8.0});
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
  // 一次性迁移标记：图片背景从「低透明度点缀」升级为「优先背景」
  static const _opacityMigratedKey = 'bg_opacity_migrated_v2';

  @override
  BackgroundConfig build() {
    final prefs = ref.watch(sharedPrefsProvider);
    var opacity = prefs.getDouble(_opacityKey) ?? 0.85;
    // 旧默认 0.35 在图片升级为优先背景后太淡（几乎看不见），一次性提到 0.85；
    // 用户此前显式调高过（≥0.6）的保持原值
    if (prefs.getBool(_opacityMigratedKey) != true) {
      unawaited(prefs.setBool(_opacityMigratedKey, true));
      if (prefs.getString(_pathKey) != null && opacity < 0.6) {
        opacity = 0.85;
        unawaited(prefs.setDouble(_opacityKey, opacity));
      }
    }
    final cfg = BackgroundConfig(
      path: prefs.getString(_pathKey),
      opacity: opacity,
      blur: prefs.getDouble(_blurKey) ?? 8.0,
    );
    // 背景图文件可能已被系统/用户删除：异步校验（不阻塞 build），
    // 校验失败时仅在用户未写入新背景的前提下清理
    final path = cfg.path;
    if (path != null) _validateFile(path);
    return cfg;
  }

  /// 文件被删了就当没设过。同步先确认文件确实缺失，
  /// 之后若 state.path 已变化（用户刚设置了新背景）则放弃清理，
  /// 避免异步校验覆盖用户新值
  Future<void> _validateFile(String path) async {
    if (localFs.fileExists(path)) return;
    final prefs = await SharedPreferences.getInstance();
    if (state.path != path) return;
    await prefs.remove(_pathKey);
    if (state.path == path) {
      state = BackgroundConfig(opacity: state.opacity, blur: state.blur);
    }
  }

  Future<void> setImage(String sourcePath) async {
    final dest = await localFs.copyToAppDocuments('custom_bg.png', sourcePath);
    if (dest == null) return;
    await _save(path: dest);
  }

  Future<void> clearImage() async {
    final cfg = state;
    if (cfg.path != null) {
      await localFs.deleteFile(cfg.path!);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pathKey);
    state = BackgroundConfig(opacity: cfg.opacity, blur: cfg.blur);
  }

  /// 滑块拖动中只更新内存态（每次回调都落盘太密），松手时 [commitSliders] 持久化
  void updateOpacity(double v) => state = state.copyWith(opacity: v);
  void updateBlur(double v) => state = state.copyWith(blur: v);

  Future<void> commitSliders() async {
    final s = state;
    await _save(opacity: s.opacity, blur: s.blur);
  }

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
