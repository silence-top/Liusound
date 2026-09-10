import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'app_platform.dart';

bool? _lastDisplayPowerSave;

/// 应用当前刷新率档位（幂等：档位未变化时不重复设置）
void applyDisplayPowerSave(bool powerSave) {
  if (!AppPlatform.isAndroid || _lastDisplayPowerSave == powerSave) return;
  _lastDisplayPowerSave = powerSave;
  (powerSave
          ? FlutterDisplayMode.setLowRefreshRate()
          : FlutterDisplayMode.setHighRefreshRate())
      .catchError((_) {});
}
