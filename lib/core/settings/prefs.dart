import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好读取的唯一入口：main() 在 runApp 前完成加载并 override 注入。
/// 业务控制器在 build() 中同步读取，消除「异步回填覆盖用户刚改的新值」竞态。
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw StateError(
    'sharedPrefsProvider 未注入：必须在 main() 中以 sharedPrefsProvider '
    'override 已加载的 SharedPreferences 后再 runApp',
  );
});
