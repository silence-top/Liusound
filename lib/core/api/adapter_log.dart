import 'package:flutter/foundation.dart';

/// 适配器静默降级路径（catch 后返回 null/false）的调试日志：
/// release 编译零开销，调试时可看到被吞掉的异常，便于排查「接口怎么没数据」
void adapterSwallowLog(String adapter, Object error, StackTrace stackTrace) {
  if (kDebugMode) {
    debugPrint('[$adapter] 静默降级: $error');
  }
}
