import 'dart:async';
import 'dart:io';

/// 应用错误模型（P1-AppError）：Adapter 层抛类型化错误，Provider 透传为
/// AsyncError，UI 只读 message / 按类型分支，禁止用 Exception.toString() 判断
sealed class AppError implements Exception {
  const AppError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 网络/连接类错误（超时、DNS、断网）
final class NetworkError extends AppError {
  const NetworkError([super.message = '网络连接失败']);
}

/// 认证/会话类错误（密码错误、SID 失效、未登录）
final class AuthError extends AppError {
  const AuthError([super.message = '认证失败，请重新登录']);
}

/// 服务器不支持该能力（AdapterCapabilities 之外的运行时不支持）
final class UnsupportedFeatureError extends AppError {
  const UnsupportedFeatureError([super.message = '当前服务器不支持此功能']);
}

/// 资源不存在（404、条目被删除）
final class NotFoundError extends AppError {
  const NotFoundError([super.message = '内容不存在']);
}

/// 权限不足
final class PermissionError extends AppError {
  const PermissionError([super.message = '没有执行此操作的权限']);
}

/// 本地存储类错误（磁盘、数据库）
final class StorageError extends AppError {
  const StorageError([super.message = '本地存储失败']);
}

/// 播放链路错误（流解析失败、编解码不支持）
final class PlaybackError extends AppError {
  const PlaybackError([super.message = '播放失败']);
}

/// 服务器返回异常响应（非 2xx、响应体缺失）
final class ServerError extends AppError {
  const ServerError([super.message = '服务器请求失败']);
}

/// UI 错误展示统一出口：AppError 直接读 message；其余异常按类型映射
/// 安全文案，不把原始异常串（可能含 URL/堆栈细节）暴露给用户
String appUserMessage(Object error) {
  if (error is AppError) return error.message;
  if (error is SocketException || error is TimeoutException) {
    return const NetworkError().message;
  }
  return '操作失败，请稍后重试';
}
