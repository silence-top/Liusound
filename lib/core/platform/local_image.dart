/// 本地文件图片门面：给「按路径渲染本机文件」的 UI 用，
/// web 端返回 null（调用方回退占位图/网络图）。
library;

export 'local_image_web.dart' if (dart.library.io) 'local_image_io.dart';
