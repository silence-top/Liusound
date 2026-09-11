# 流声 Liu Sound

多后端自建音乐服务客户端，支持 **Navidrome / Subsonic / Jellyfin / Emby / Plex / 群晖 Audio Station / 飞牛 fnOS 音乐** 七种后端，一套代码运行在 **Android / iOS / Web / Windows / macOS / Linux**。使用 Flutter 构建，液态玻璃 UI（8 套可换肤），支持流媒体播放、逐行歌词同步、下载离线、本地音乐回放、桌面小部件与系统媒体控制。

> 版本历史：v1.0（React Native / Expo 实现）已归档至 git tag `v1.0`；v2.0 为 Flutter 全量重构；v2.1 新增多后端适配与液态玻璃 UI。架构细节见 [FEATURES.md](FEATURES.md)，逐次变更见 [CHANGELOG.md](CHANGELOG.md)。

## 功能特性

- **多后端 + 多服务器**：七种音乐服务器统一适配，多台服务器并存管理、一键切换（切换自动退回首屏），会话持久化、token 失效静默重登，凭证加密存储
- **能力自适应**：按后端能力矩阵自动显隐功能入口（评分 / 相似歌曲 / 歌词 / 转码等）
- **首页多维浏览**：最新专辑 / 最近播放 / 最常播放 / 随机专辑 / 每日推荐；资料库四入口（专辑 / 歌手 / 流派 / 歌单）+ 拼音索引；歌曲列表多维排序（含中文拼音序）
- **播放内核**：`just_audio` 事件驱动；`audio_service` 后台播放、通知栏媒体控制、AVRCP 线控；Crossfade / Gapless / 断点续播
- **全屏播放器**：封面取色材质、黑胶 / 歌词 / 队列三 Tab；逐行歌词同步 + LRC 双语 + 悬浮歌词；±0.05s 偏移微调逐歌持久化（按服务器隔离）
- **音效**：10 段 / 31 段 EQ、空间音频近似（按平台能力门控）
- **下载离线**：边听边存缓存、手动下载落盘（系统音乐目录 / MediaStore）
- **本地音乐**：扫描设备本地曲库（文件 picker 选目录），ID3 读取，与在线曲库统一播放
- **桌面小部件**：Android 小部件（封面 + 控制按钮）；Scrobble 上报；Android Auto 资源就绪
- **个性化**：8 套皮肤（色温 / 圆角 / 材质差异化）、自定义背景图（最高优先级）、卡片展示开关（裸排 / 卡片双形态）、玻璃效果三档
- **全局搜索**：防抖搜索，歌曲 / 专辑 / 歌手分区展示，点击即播

## 后端支持矩阵

| 后端 | 浏览 | 搜索 | 收藏 | 评分 | 相似歌曲 | 歌词 | 下载 |
|------|------|------|------|------|----------|------|------|
| Navidrome | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Subsonic | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jellyfin | ✅ | ✅ | ✅ | — | — | ✅ | ✅ |
| Emby | ✅ | ✅ | ✅ | — | — | ✅ | ✅ |
| Plex | ✅ | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| Audio Station | ✅ | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| 飞牛 fnOS | ✅ | ✅ | ✅ | — | — | ✅（LRC） | ✅ |

> 飞牛 fnOS 音乐为私有 API（`/music/api/v1/*`），Cookie-only token + SHA256 密码；地址填 `host:port` 即可，路径 `/music` 自动补全。

## 技术栈

| 分类 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47 stable / Dart 3.13 |
| 状态 | flutter_riverpod 2.6 |
| 播放 | just_audio（+ windows / media_kit 桌面端）+ audio_service |
| 网络 | dio 5（拦截器认证头 + token 静默重登） |
| 存储 | sqflite（曲库快照 / 播放状态）+ flutter_secure_storage（凭证）+ shared_preferences |
| 加密 | crypto 3（Subsonic / Emby / fnOS 认证哈希） |
| 图片 | cached_network_image（磁盘 LRU + 解码尺寸限制） |

## 架构

```
lib/
├── main.dart                  # 入口：AudioService.init、认证分流
├── core/
│   ├── api/
│   │   ├── server_adapter.dart    # ServerAdapter 统一接口 + 能力矩阵
│   │   ├── server_type.dart       # ServerType 枚举 + 工厂
│   │   └── adapters/              # 七后端适配器（MediaBrowser 共享基类、Subsonic 协议基类）
│   ├── audio/ cache/ download/    # 音效 / 边听边存 / 下载落盘
│   ├── library/ lyrics/           # 排序比较器（拼音）/ 歌词解析
│   ├── local/ platform/           # 本地曲库 / 平台门面层
│   ├── models/ network/ scrobble/ settings/ storage/ theme/
├── features/
│   ├── auth/ home/ player/ search/ settings/
├── shared/
│   ├── cover_art.dart         # 统一封面加载
│   └── widgets/glass.dart     # 液态玻璃组件库（皮肤感知）
└── shell/app_shell.dart       # IndexedStack 保活 + MiniPlayer 常驻
```

性能要点：播放状态细粒度 provider 拆分（播放期间首页零重建）、进度走事件流无轮询、封面服务端裁剪 + 客户端解码限制、同一可见路由最多 2 个 BackdropFilter、低端设备自动降级。

## 快速开始

```bash
flutter pub get
flutter run                 # 选择目标设备
flutter run -d chrome       # Web
flutter analyze             # 静态检查（CI 闸门：format + analyze + gitleaks）
```

构建发布：

```bash
flutter build apk --release              # Android APK
flutter build appbundle --release        # Android AAB
flutter build web                        # Web（build/web）
flutter build windows / macos / linux    # 桌面端
flutter build ipa                        # iOS（需 macOS + 签名配置）
```

> 仓库不含 `test/`（仅本地保留）；`web/sqlite3.wasm`、`web/sqflite_sw.js` 为 `sqflite_common_ffi_web` 的生成物，依赖升级后执行 `dart run sqflite_common_ffi_web:setup` 重新生成。

## 服务端要求

| 后端 | 最低版本 | 备注 |
|------|----------|------|
| Navidrome | 0.50+ | 含歌词字段与 Subsonic 兼容接口 |
| Subsonic | 任意 | Madsonic / Airsonic 等兼容实现均可 |
| Jellyfin | 10.8+ | `/Users/AuthenticateByName` 登录 |
| Emby | 4.7+ | MD5 密码哈希登录 |
| Plex | 任意 | `plex.tv` 账号认证 + 音乐分区发现 |
| Audio Station | DSM 7+ | `SYNO.AudioStation.*` API |
| 飞牛 fnOS | fnOS 音乐应用 | 私有 API，见上；歌词为 LRC 格式 |

## 平台说明

| 平台 | 状态 |
|------|------|
| Android / Web | ✅ 完整支持（真机 / 真浏览器验证） |
| Windows / macOS / Linux | ✅ 已支持（部分环境受限：Windows 需 VS 桌面开发负载，iOS / macOS 需 Apple 机器） |
| iOS | ✅ 已支持（真机验证需 macOS + Xcode） |
| 鸿蒙 | ⚠️ 实验性，不可构建（守卫层已就位，原生工程未生成） |
