/// 歌曲离线下载门面。落盘与索引实现在 `download_service_io.dart`
/// （Android/iOS/桌面/鸿蒙）；web 端 Phase 2 接浏览器下载，
/// 当前为占位 stub（`download_service_web.dart`）。
library;

export 'download_service_web.dart'
    if (dart.library.io) 'download_service_io.dart';
