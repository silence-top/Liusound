# 流声 Liu Sound

多后端自建音乐服务客户端：一套代码适配 **Navidrome / Subsonic / Jellyfin / Emby / Plex / 群晖 Audio Station / 飞牛 fnOS 音乐** 七种后端，构建在 **Android / iOS / macOS / Windows / Linux / Web** 六个平台（鸿蒙为第七目标：守卫层与 ArkTS 通道已就位，原生工程未生成）。Flutter 实现，8 套可换肤的液态玻璃 UI，覆盖流媒体播放、逐行歌词、后台下载离线、本地曲库回放、Android 桌面小部件与系统媒体控制。

> **文档分工**：本 README 只讲「有什么、怎么跑」。逐字段行为、25 条架构不变量与反模式、平台能力矩阵见 [FEATURES.md](FEATURES.md)（文档版本 v2.4.0，2026-09-17 对 `lib/` 全量重核）；逐次变更见 [CHANGELOG.md](CHANGELOG.md)。
>
> **版本历史**：v1.0（React Native / Expo）已归档至 tag `v1.0`；v2.0 Flutter 全量重构；v2.1 多后端适配 + 液态玻璃 UI（tag `v2.1.0`，`pubspec.yaml` 版本号至今仍为 `2.1.0+1`，其后按日期批次演进）；2026-09-10 全平台适配 v3 Phase 0–6；2026-09-11 仓库清理 + 质量闸门与 git 历史重写。

## 功能特性

**播放**

- `just_audio` + `audio_service` 事件驱动内核：后台播放、通知栏与锁屏媒体控制、AVRCP 线控、耳机按键播放/切歌
- Crossfade 交叉淡化、断点续播（逐歌回写播放位置）、播放错误统一归一与提示
- 在线音质分档：无损 / 320 / 256 / 192 / 128 kbps + MP3 / OPUS 转码格式，Wi-Fi 与蜂窝各一档；转码能力按服务器**运行时真实探测**（见「已知边界」）
- 音效：Android 原生音效链 Equalizer + BassBoost + Virtualizer（Dart 侧按设备回传的频点与增益上下限动态渲染，波段数由机型决定、常见 5 段；预设曲线按 31–16000 Hz 十个标准频点插值映射）。设备缺失的模块自动缺席；Web 无系统音效 API，入口整体隐藏

**歌词**

- 逐行 LRC 同步 + 双语行、滚动跟随；±0.05s 偏移微调逐歌持久化且**按服务器隔离**
- Android 悬浮歌词（`SYSTEM_ALERT_WINDOW` 小窗），其余平台入口隐藏
- 播放页材质与皮肤解耦：弹层底色取封面取色毛玻璃，切换皮肤不改变播放页观感

**曲库与发现**

- 首页五分区：最新专辑 / 每日推荐 / 最近播放 / 最常播放 / 随机专辑；先回放本地快照再后台刷新（冷启动不转圈）
- 资料库：固定入口歌曲 / 我喜欢的 / 本地音乐 / 专辑 / 听歌统计，按后端能力显隐专辑艺术家 / 歌手 / 流派 / 电台（`fetchArtists` 等返回 null 即隐藏，加载中先隐藏避免闪烁）；下方歌单区可在「我的歌单 / 全部歌单」间切换。歌曲列表全字段排序（含中文拼音序）并全局记忆，歌手列表带字母索引侧栏
- 私人 FM：首页横幅进入，按 `SongSort.random` 抽批（七后端通用）、排除近 7 天听过的歌，队列复用全局播放队列
- 听歌统计：概览四项 + 最常听歌曲 + 最爱歌手，数据源为本地播放历史且与当前服务器绑定
- 全局搜索：防抖，歌曲 / 专辑 / 歌手分区，结果与提交都记入搜索历史，空态展示历史

**离线与本地**

- 边听边存 LRU 缓存 + 手动下载：**入列即返回**，后台队列串行执行，下载列表可看进度 / 重试失败项 / 清理
- 下载优先落公共音乐目录（MediaStore / 各平台用户目录），失败原子回退应用私有目录并登记索引
- 本地音乐：目录扫描（file_picker 选目录）+ `audio_metadata_reader` 读标签，与在线曲目统一播放

**多后端与会话**

- 七后端统一 `ServerAdapter` 接口 + `AdapterCapabilities` 能力矩阵，功能入口按能力自适应显隐
- 多台服务器并存、一键切换（切换自动退回首屏），会话持久化，token 失效静默重登，凭证存 `flutter_secure_storage`
- 服务器可新增 / 编辑 / 删除；Scrobble 上报失败落库重试（最多 5 次，1/2/4/8/16 分钟指数退避，超限丢弃）

**外观与个性化**

- 8 套皮肤：莫奈取色（默认）/ 液态玻璃 / 深空科幻 / 极简纯色 / 落日熔金 / 林间苔原 / 终端磷光 / 封面取色，以色温、圆角系数与材质相互区分
- Android Material You 动态取色（仅在未手动选色时生效）
- 玻璃效果三档（关闭 / 标准 / 增强，只管模糊强度）+ 全局「面板透明度」滑杆（0.2–1.0，拖动实时预览、松手落盘，对所有皮肤生效）
- 自定义背景图（最高优先级，压过所有皮肤氛围）；卡片展示开关（裸排 / 卡片双形态，默认裸排）
- 省电模式：退模糊、循环氛围动画停止、动效时长压缩至 40%、Android 切低刷新率

## 后端能力矩阵

浏览 / 搜索 / 收藏 / 歌单读写 / 下载 / 随机抽歌 **七后端全部实现**；下表是真正驱动「能力自适应」的差异项（逐项对应 `capabilities` 字段或 null 哨兵）。

| 后端 | 歌词 | 评分 | 相似歌曲 | 歌手简介 | 转码分档 | Scrobble | 版本快照 | 歌手·流派入口 |
|------|------|------|----------|----------|----------|----------|----------|----------------|
| Navidrome | ✅ | ✅ | ✅ | ✅ | ✅（探测） | ✅ | ✅ | ✅ |
| Subsonic | ✅ | ✅ | ✅ | ✅ | ✅（探测） | ✅ | ✅ | ✅ |
| Jellyfin | ✅ | — | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| Emby | ✅ | — | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| Plex | — | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| Audio Station | — | ✅ | — | — | — | — | — | — |
| 飞牛 fnOS | ✅（LRC） | — | — | — | — | — | — | ✅ |

> - Jellyfin 与 Emby 共享 `MediaBrowserAdapter` 基类，能力一致。
> - Plex 与 Audio Station 的 `fetchLyrics` 恒返回 null，歌词 Tab 自动隐藏。
> - Audio Station 的 `fetchArtists` / `fetchGenres` 返回 null → 资料库只留专辑与歌单；同时无 Scrobble / 无曲库变更标记。
> - 「版本快照」= 服务端提供曲库变更标记，未变时直接读本地快照、变化才全量重拉；缺失该能力的后端按时间/手动刷新。
> - 飞牛 fnOS 音乐为私有 API（`/music/api/v1/*`），Cookie-only token + SHA256 口令摘要；地址填 `host:port` 即可，路径 `/music` 自动补全。

## 技术栈

| 分类 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47（CI 锁 3.47.2）/ Dart ^3.13.2 |
| 状态 | flutter_riverpod ^2.6（Notifier / NotifierProvider；`build()` 期禁同步写 state） |
| 播放 | just_audio ^0.10.6 + audio_service ^0.18.19 + audio_session；Windows 用 `just_audio_windows`，Windows/Linux 用 `just_audio_media_kit`（Linux 另带 `media_kit_libs_linux`） |
| 网络 | dio ^5.11（认证头拦截器 + token 静默重登 `reauth_interceptor`）+ connectivity_plus（Wi-Fi/蜂窝分档） |
| 存储 | sqflite（曲库快照 / 播放历史 / 下载索引 / Scrobble 队列）；Web 走 `sqflite_common_ffi_web` 的 WASM worker；shared_preferences（偏好）+ flutter_secure_storage（凭证） |
| 取色与图片 | palette_generator（封面主色）+ cached_network_image / flutter_cache_manager（磁盘 LRU + `memCacheWidth` 解码限幅） |
| 系统能力 | home_widget（Android 小部件）、flutter_displaymode（刷新率档位）、permission_handler、dynamic_color（Material You）、image_picker（自定义背景）、audio_metadata_reader（本地标签）、share_plus、lpinyin（中文拼音排序） |
| 加密 | crypto（Subsonic salt+md5 token / Emby md5 口令 / fnOS sha256 口令） |
| 平台门面 | `AppPlatform` 等条件导出层统一 io / web / 鸿蒙差异，业务侧禁止直接 `import 'dart:io'` |

## 架构

```
lib/
├── main.dart                  # 入口：AudioService.init、认证分流、AppTheme 组装（动态取色 + 面板透明度系数）
├── core/
│   ├── api/                   # ServerAdapter 统一接口 + AdapterCapabilities + ServerType 工厂
│   │   └── adapters/          # 七后端适配器（Subsonic 协议基类、MediaBrowser 共享基类）+ reauth_interceptor
│   ├── audio/                 # EQ / 低音 / 空间虚拟化 + audio_session（按平台条件导出）
│   ├── cache/ download/       # 边听边存 LRU / 后台下载队列 + 落盘与索引
│   ├── history/ library/      # 播放历史（按服隔离）/ 排序比较器（拼音）
│   ├── local/ lyrics/         # 本地曲库扫描（分平台默认目录）/ LRC 解析
│   ├── floating/ scrobble/    # Android 悬浮歌词 / 离线 Scrobble 重试队列
│   ├── models/ network/       # 领域模型 / dio 封装
│   ├── platform/ settings/    # 平台门面 / 全局偏好 provider（省电、档位、透明度、卡片开关…）
│   ├── storage/ theme/        # SQLite 工厂（io / web）/ SkinTokens + AppTheme + MotionTokens
│   └── errors/ subsonic/ widget/  # AppError 归一 / Subsonic 协议原语 / 轻量 widget
├── features/
│   ├── auth/                  # 登录 + 服务器管理（新增 / 编辑）
│   ├── home/                  # 首页五分区、资料库入口、二级列表（AmbientScaffold 固定顶栏无缝氛围）
│   ├── player/                # 全屏播放器（黑胶/歌词/队列）、audio_handler（媒体会话）、MiniPlayer、下载队列弹层
│   ├── fm/ stats/             # 私人 FM / 听歌统计
│   └── search/ settings/      # 搜索（含历史）/ 设置主页与二级页
├── shared/
│   ├── cover_art.dart         # 统一封面加载（服务端裁剪 + 解码限幅 + 本地回退）
│   └── widgets/               # glass.dart 玻璃库、glass_quality、motion、toast、marquee_text、async_states、album_card
└── shell/app_shell.dart       # PageView + _KeepAlive 保活三页；MiniPlayer 悬浮叠加（Stack，非 bottomNavigationBar）
```

## 性能与体验红线

- **零重建**：播放状态用 `select` 细粒度订阅，切歌/进度推进不触发宿主页面重建；进度走 `positionStream` 事件流，无轮询
- **玻璃预算**：`BackdropFilter` 只用于非滚动与悬浮表面，列表滚动项一律 blur=0，禁止逐行挂模糊
- **图片预算**：封面走服务端裁剪尺寸 + 客户端 `memCacheWidth = 显示尺寸 × DPR`，不做全尺寸解码
- **零等待**：数据页先回放 SQLite 快照再后台刷新，不转圈不清空；耗时操作（下载等）入列即返回
- **省电门**：所有循环氛围动画挂 `powerSaveProvider`；省电模式退模糊、动效时长压缩至 40%
- **命名按感知范围**：面向用户的设置项以用户看到的东西命名（「面板透明度」而非内部 `glassTint`）

## 快速开始

```bash
flutter pub get
flutter run                # 选择目标设备
flutter run -d chrome      # Web
```

本地校验（与 CI 闸门同序）：

```bash
dart format lib test
dart format --output=none --set-exit-if-changed lib   # 必须 exit 0
flutter analyze --fatal-infos
flutter test                                         # 测试仅本地保留，仓库不含 test/
```

Web 端 SQLite worker 已随仓库提交；升级 `sqflite_common_ffi_web` 后需重新生成：

```bash
dart run sqflite_common_ffi_web:setup
```

构建发布：

```bash
flutter build apk --release              # Android APK
flutter build appbundle --release        # Android AAB
flutter build web                        # Web（build/web）
flutter build windows / macos / linux    # 桌面端
flutter build ipa                        # iOS（需 macOS + 签名配置）
```

> 鸿蒙需 `flutter_ohos` 工具链，当前不可构建；仓库已备好平台守卫与 ArkTS 通道占位。

## 服务端要求

| 后端 | 最低版本 | 备注 |
|------|----------|------|
| Navidrome | 0.50+ | 含歌词字段与 Subsonic 兼容接口；转码需服务端装有 ffmpeg |
| Subsonic | 任意 | Madsonic / Airsonic 等兼容实现均可 |
| Jellyfin | 10.8+ | `/Users/AuthenticateByName` 登录 |
| Emby | 4.7+ | MD5 密码哈希登录 |
| Plex | 任意 | `plex.tv` 账号认证 + 音乐分区发现 |
| Audio Station | DSM 7+ | `SYNO.AudioStation.*` API |
| 飞牛 fnOS | fnOS 音乐应用 | 私有 API，见上；歌词为 LRC 格式 |

## 平台说明

| 平台 | 状态 | 平台专属差异 |
|------|------|--------------|
| Android | ✅ 完整支持（真机 Redmi 2203121C 实测） | 桌面小部件、悬浮歌词、Material You 动态取色、刷新率档位、MediaStore 落盘 |
| Web | ✅ 支持（真浏览器冒烟通过） | 无音效 API（EQ/低音/空间隐藏）、无后台小窗、SQLite 走 WASM worker、下载走浏览器 |
| iOS | ✅ 已支持 | 后台音频走 `UIBackgroundModes: audio`；真机验证需 macOS + Xcode |
| macOS | ✅ 已支持 | 沙盒 entitlement 已声明（音乐资源库 / 下载 / 文件选择） |
| Windows | ✅ 已支持 | `just_audio_windows` / media_kit 内核 + ffi SQLite；构建需 VS 桌面开发负载 |
| Linux | ✅ 已支持 | `just_audio_media_kit` + `media_kit_libs_linux` |
| 鸿蒙 | ⚠️ 实验性，不可构建 | 守卫层与 ArkTS 通道就位，等待 `flutter_ohos` 生态与原生工程 |

> 上表中除 Android / Web 外的平台均未在作者机器上完成本机验证，构建与运行结果以你的环境为准。

## 已知边界

- **车机 / Android Auto**：`audio_handler` 已实现 `getChildren` / `playMediaItem` / `playFromMediaId`（能浏览），但 `AndroidManifest.xml` 缺 `automotive_app_desc` 元数据声明，Auto 界面不会收录本应用（未接入，非「已就绪」）。
- **转码分档依赖服务端**：Subsonic 系（含 Navidrome）对转码做运行时探测，结果按 `服务器 + 账号` 持久化，避免每次冷启动重探；探测本身失败会放行，播放侧另有回退兜底，最坏情况是转码档实际播原文件。
- **歌词覆盖不全**：Plex 与 Audio Station 无歌词接口，其余五后端可用。
- **电台仅展示**：电台入口与列表已就位，但播放需要独立流媒体管线，当前未实现。
- **无遥测**：依赖表中不含任何埋点/统计 SDK；服务器地址与凭证只存设备本地。
