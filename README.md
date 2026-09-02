# 流声 Liu Sound

基于 [Navidrome](https://www.navidrome.org/) 自建音乐服务器的跨平台音乐客户端，一套代码同时运行在 **Android / iOS / Web** 三端。使用 Flutter 构建，支持流媒体播放、逐行歌词同步、后台播放与系统通知栏媒体控制、播放队列管理与多数据维度浏览。

> 版本历史：v1.0（React Native / Expo 实现）已归档至 git tag `v1.0`；当前 v2.0 为 Flutter 全量重构版本。

## 功能特性

- **多服务器登录**：输入 Navidrome 服务器地址 + 账号密码登录；会话持久化，冷启动自动恢复（凭证加密存储）
- **首页多维浏览**：最新专辑 / 最近播放 / 最常播放 / 随机专辑 / 每日推荐（随机 50 首），下拉刷新
- **播放内核**：`just_audio` 事件驱动（positionStream 替代轮询）；`audio_service` 后台播放、系统通知栏媒体控制、耳机线控
- **全屏播放器**：相似歌曲推荐 / 播放队列 / 歌词同步三 Tab
- **逐行歌词同步**：解析 Navidrome JSON 歌词（第一音轨、毫秒转秒、滤空行、排序），二分查找定位当前行，自动跟随滚动；支持 ±0.05s 偏移微调并逐歌持久化、一键复制歌词
- **播放队列**：添加 / 移除 / 清空、点击跳播；三种播放模式（顺序 / 随机 / 单曲循环）；队列与播放进度持久化（冷启动恢复，不自动播放，登出清除）
- **全局搜索**：300ms 防抖搜索 `/search`，歌曲 / 专辑 / 歌手分区展示，点击歌曲即播
- **设置页**：服务器信息、歌词偏移缓存清理、图片缓存清理、退出登录（二次确认）
- **三端一致 UI**：Material 3 深色主题，底部导航 IndexedStack 保活

## 技术栈

| 分类 | 选型 | 说明 |
| --- | --- | --- |
| 框架 | Flutter 3.47 stable / Dart 3.13 | Impeller 渲染（Android/iOS 默认） |
| 状态 | flutter_riverpod 2.6 | 细粒度 provider 拆分播放状态 |
| 播放 | just_audio + audio_service | 事件驱动播放内核；后台播放与媒体通知 |
| 网络 | dio 5 | 拦截器附加 JWT 双认证头，凭证内存化 |
| 存储 | flutter_secure_storage / shared_preferences | 敏感三要素加密存储；会话/播放状态/歌词偏移 |
| 图片 | cached_network_image | 磁盘 LRU + `memCacheWidth` 限制解码 |

## 架构与性能设计

```
lib/
├── main.dart                 # 入口：imageCache 上限、AudioService.init、认证分流
├── core/
│   ├── api/navidrome_client.dart    # REST 客户端（登录/专辑/歌曲/相似歌曲/搜索）
│   ├── lyrics/lyrics.dart           # 歌词解析 + 二分查找（纯函数）
│   ├── models/models.dart           # Song/Album/Artist/SearchResult（容错解析）
│   ├── storage/auth_store.dart      # 会话持久化（安全存储 + prefs）
│   ├── subsonic/subsonic.dart       # Subsonic 直链（封面/流）与认证参数
│   └── theme/app_theme.dart         # Material 3 深色主题
├── features/
│   ├── auth/                 # 服务器选择 / 登录 / 会话恢复
│   ├── home/                 # 首页五分区（keepAlive FutureProvider）
│   ├── player/               # 播放控制器 / 音频handler / Mini/全屏播放器
│   ├── search/               # 搜索页
│   └── settings/             # 设置页
└── shell/app_shell.dart      # IndexedStack 保活 + MiniPlayer 常驻
```

性能红线（对标 1.x Context 高频广播导致整页重建的问题）：

- 播放状态按 `currentSong / queue / isPlaying / position / duration` 拆分为独立 provider，切歌与高频进度互不干扰
- **播放期间首页/搜索页零重建**：高频流仅在最小叶子组件内订阅（进度条、播放按钮）
- 播放进度走 `just_audio` 事件流（内部节流），无定时器轮询
- 封面：服务端裁剪 300px + 客户端 `memCacheWidth: 300` 限制解码尺寸 + 全局 imageCache 64MB 上限
- 页面保活：底部导航 IndexedStack，切换零重挂载、滚动位置保留
- 播放状态持久化 500ms 防抖，队列仅落盘前 100 首且剔除内嵌歌词大字段

## 快速开始

### 环境要求

- Flutter SDK 3.47+（含 Dart 3.13）
- Android：Android Studio / SDK（已含 `android/` 原生工程）
- iOS：Xcode（macOS）
- 一台可访问的 Navidrome 服务器

### 安装与运行

```bash
# 拉取依赖
flutter pub get

# 开发运行
flutter run                 # 选择目标设备
flutter run -d chrome       # Web 端

# 静态检查
flutter analyze
```

### 构建发布

```bash
flutter build web                        # Web（构建产物 build/web）
flutter build apk --release              # Android APK
flutter build appbundle --release        # Android AAB
flutter build ipa                        # iOS（需 macOS + 签名配置）
```

> Android 首次构建前需接受许可：`flutter doctor --android-licenses`

## 服务端要求

- Navidrome（建议 0.50+，含 `/api/song` 歌词字段与 Subsonic 兼容接口）
- 登录接口 `POST /auth/login` 返回 `token / subsonicToken / subsonicSalt`
- 封面与播放走 Subsonic `getCoverArt` / `stream`（`c=NavidromeUI&v=1.8.0&f=json`）
