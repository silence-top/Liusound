# 流声 Liu Sound 功能梳理文档（完整版）

## 项目概览

**项目名称**: 流声 Liu Sound  
**Document Version**: 2.4.0（本文件自身版本，见文末版本历史）  
**Product Version**: 2.1.x（以 `pubspec.yaml` 的 `version` 为唯一事实来源）  
**Dependency Source of Truth**: `pubspec.yaml`（本文不再复制维护依赖版本号）  
**技术栈**: Flutter 3.47.2（CI 锁定版本）+ Dart sdk ^3.13.2 + Riverpod + Just Audio + Audio Service  
**目标平台**: Android（MIUI 测试设备 2203121C）/ iOS / macOS / Windows / Linux / Web / 鸿蒙（`ohos`，依赖 flutter_ohos 生态）  
**多后端支持**: Navidrome / Subsonic / Jellyfin / Emby / Plex / Audio Station / 飞牛 fnOS（7 种）  
**架构风格**: Adapter 接口 + Capabilities 驱动 UI + Token 化主题系统（8 皮肤 SkinTokens ThemeExtension）  
**验证闸门**: `dart format lib test` → `dart format --output=none --set-exit-if-changed lib`（CI 格式闸门，必须退出 0）→ `flutter analyze --fatal-infos` → `flutter test`  

---

## 一、架构分层

### 1.1 目录结构

```
lib/
├── main.dart                  # 组合根：启动序列 + MusicApp（主题/取色/省电/悬浮歌词/换服退栈）+ _Splash
│                              #   路由与 MaterialApp 配置同在此文件（无独立 app.dart）
├── core/                      # 核心层（跨模块共享，禁止依赖 features/）
│   ├── api/                   # ServerAdapter 接口 + 7 个 adapter 实现
│   │   ├── server_adapter.dart    # 抽象基类 + 请求/响应模型 + AdapterCapabilities
│   │   ├── server_type.dart       # ServerType enum（7 变体）+ ServerConfig
│   │   ├── adapter_provider.dart  # serverAdapterProvider / transcodeSupportProvider / activeServerIdProvider（P1-B 自 features/auth 下沉）
│   │   ├── adapter_log.dart       # adapterSwallowLog：吞错但留痕
│   │   ├── navidrome_client.dart  # Navidrome 原生 API 客户端
│   │   └── adapters/              # 7 个 backend 适配器
│   │       ├── subsonic_protocol.dart   # Subsonic 协议共享基类（直链/资料库扩展/版本与转码探测）
│   │       ├── subsonic_adapter.dart / navidrome_adapter.dart（共用上述基类）
│   │       ├── mediabrowser_adapter.dart  # MediaBrowser 基类（Jellyfin/Emby 共用）
│   │       ├── emby_adapter.dart / jellyfin_adapter.dart / plex_adapter.dart
│   │       ├── audio_station_adapter.dart / fnos_adapter.dart（飞牛）
│   │       └── reauth_interceptor.dart    # 401 静默重登公共拦截器（MediaBrowser + Plex 共用）
│   ├── audio/                 # 音频会话与音效链（EQ/低音/空间；_io/_web 条件导入）
│   ├── cache/                 # 音频缓存 LRU（LockCachingAudioSource；_io/_web 分实现）
│   ├── download/              # 离线下载（原子写入）+ 后台下载队列 + 自动下载
│   ├── errors/                # AppError sealed 错误模型 + appUserMessage 文案映射
│   ├── floating/              # Android 悬浮歌词（原生小窗）
│   ├── history/               # play_history 播放历史（RefReader typedef 宿主）
│   ├── library/               # 曲库版本快照同步 + 歌曲列表排序偏好（song_sorting）
│   ├── local/                 # 本地音乐扫描（Isolate + SQLite）+ 各平台扫描目录
│   ├── lyrics/                # LRC 歌词解析（Navidrome JSON + 经典 LRC + 双语对齐）
│   ├── metadata/              # 元数据插件（§十六）：声明式 JSON 描述 + 执行器 + 编排器
│   ├── models/                # 数据模型 + 公共 Json 工具（P1-D）
│   ├── network/               # Dio 工厂 + 网络设置（代理/证书/hosts）
│   ├── platform/              # 平台能力门面：app_platform / display_mode / isolate_runner /
│   │                          #   local_fs / local_image / media_store（各 _io/_web/<平台> 实现）
│   ├── scrobble/              # Scrobble 上报（离线队列 + 补发）
│   ├── settings/              # prefs.dart（sharedPrefsProvider）+ streaming_prefs.dart（音质/转码/网络）
│   ├── storage/               # app_db（SQLite）+ auth_store + server_repository + db_factory(_io/_web)
│   ├── subsonic/              # Subsonic 协议常量/参数拼装
│   ├── theme/                 # 主题系统
│   │   ├── accent.dart            # AppAccent 强调色（6 预设）+ accentExplicitProvider
│   │   ├── app_skin.dart          # AppSkin 8 皮肤枚举 + SkinController
│   │   ├── skin_tokens.dart       # SkinTokens ThemeExtension（20 字段 × 8 皮肤 + albumTint 动态工厂）
│   │   ├── glass_theme.dart       # GlassTokens / AppSpacing / AppRadius / AppText
│   │   ├── background.dart        # 自定义背景图路径与不透明度
│   │   ├── motion_tokens.dart     # MotionTokens 动效令牌（见 §15.4）
│   │   └── settings_prefs.dart    # UI 偏好（迷你条/玻璃档位/省电/卡片形态/耳机动作等）
│   └── widget/                # home_widget_sync：Android 4x2 桌面播放小部件推送
├── features/                  # 功能模块（页面 + 控制器）
│   ├── auth/                  # 服务器选择 / 登录 / 服务器管理 + 编辑服务器页
│   ├── fm/                    # 私人 FM（fm_providers + fm_screen）
│   ├── home/                  # 首页 / 资料库 / 二级入口列表 / 专辑·歌手·歌单详情 / 歌曲信息 / 服务器详情
│   ├── player/                # 播放器 + 队列 + 操作弹窗 + 下载队列面板 + 状态 provider
│   │   ├── player_controller.dart     # 全部 provider 状态源 + playerActionsProvider 门面
│   │   ├── player_actions.dart        # PlayerActionsBase（part 宿主：事件绑定/初始化/切歌/shuffle/队列）
│   │   └── player_source_resolver / player_crossfade / player_breakpoint /
│   │       player_persistence / player_restore / player_error_handler   # 均为 `part of player_actions.dart`
│   ├── search/                # 搜索页（含搜索历史）
│   ├── settings/              # 设置主页（part 拆分）+ 8 个二级页
│   │   ├── settings_screen.dart + settings_sheets_{storage,appearance,audio,player}.dart
│   │   └── settings_sub_{appearance,effects,network,playback,player_style,storage,system,plugins}.dart
│   └── stats/                 # 听歌统计（summary / topSongs / topArtists）
├── shared/                    # 共享 UI 组件（不反向依赖 features 的具体页面）
│   ├── widgets/               # glass / glass_quality / motion / toast / async_states /
│   │                          #   album_card / cover 派生组件 / marquee_text / list_end_mark /
│   │                          #   quality_badge / search_entry
│   ├── cover_art.dart         # CoverArt（网络封面 + 本地封面回退 + 淡入）
│   └── cover_cache.dart       # CoverCacheManager（封面专用磁盘缓存：4000 项/365 天 + 并发限 8）
└── shell/                     # 主框架
    └── app_shell.dart         # AppShell：顶部图标导航 + PageView 保活三页 + MiniPlayer 悬浮叠加
                               #   （壳层 Stack 叠加，不用 bottomNavigationBar——推入的详情页才走该槽位；
                               #    避让 = MediaQuery.padding.bottom
                               #    += kMiniBarOverlaySpace(80.0，定义于 features/player/mini_player.dart:20)；
                               #    hasMiniBar 用 currentSongProvider.select，只在开始/停止播放时重建，切歌不触发）
```


### 1.2 关键架构契约

| 契约 | 说明 |
|------|------|
| **ServerAdapter 接口** | 所有后端必须实现的方法集；返回 `null` = 不支持，UI 据此隐藏入口 |
| **Capabilities 驱动 UI** | 每个能力字段控制一个或多个 UI 区域显示/隐藏 |
| **AppStage/AppSurface/AppSheet** | 主题组件分层契约：舞台→表面→弹层，禁止跨层消费 |
| **SkinTokens ThemeExtension** | 8 皮肤通过 20 个语义 token 实现；业务页面只使用 token，禁硬编码颜色（§4.14） |
| **AmbientScaffold** | 二级列表页统一骨架：`ColoredBox(shell) > AmbientBackground > 透明 GlassAppBar > Scaffold`，顶栏与页面背景无缝同色，滚动不叠字（§6.5） |
| **AppToaster** | 顶部 Toast 唯一出口：MaterialApp.builder 挂 `AppToaster`，`AppToaster.showToast(msg)` 静态调用免 BuildContext；禁止新增 SnackBar（§6.4） |
| **播放页材质隔离** | 全屏播放页表面**不与皮肤关联**（硬规则）：弹层与面板统一 `AlbumFrostedPanel` 封面取色毛玻璃，不用 GlassSurface；唯一例外是封面黑胶框 `_SquareCover`（视觉冻结于 611b9fa，§6.6/§6.8） |
| **装饰循环挂省电门** | 一切无限循环动效（光斑漂移/星闪/呼吸光环/旋转）必须在 `powerSaveProvider` 打开时停止；见 §4.14.9 与 §6.5 |
| **零等待** | 耗时操作一律后台化；数据页先同步回放快照缓存、再静默后台刷新，不转圈不清空（§4.13 首页 SWR） |
| **sharedPrefsProvider** | 唯一偏好读写入口；main() 加载后 override 注入，业务控制器 build() 同步读取 |
| **RefReader typedef** | `T Function<T>(ProviderListenable<T>)` 统一 Ref/WidgetRef 的 read tear-off（宿主：`core/history/play_history.dart`） |

---

## 二、多后端适配器

### 2.1 适配器列表

| 适配器 | 类名 | 基础协议 | 特殊能力 | 实际 Capabilities（ratings/similarSongs/artistBio/transcoding/scrobbling/versionedSnapshot，download 恒 true） |
|--------|------|----------|----------|-------------------|
| Navidrome | NavidromeAdapter | Subsonic API + 原生 `/api` | owner 字段、转码探测覆写、歌单播放走 mediaFileId | true / true / true / true / true / true |
| Subsonic | SubsonicAdapter | Subsonic API | 标准兼容 + 扩展映射（replayGain、kHz 归一、transcoded 回退键） | true / true / true / true / true / true |
| Jellyfin | JellyfinAdapter | MediaBrowser API | `/Audio/{id}/lyrics`（10.9+） | false / false / true / true / true / true |
| Emby | EmbyAdapter | MediaBrowser API | 继承基类；歌词接口多数版本缺失 → 静默 null | false / false / true / true / true / true |
| Plex | PlexAdapter | Plex MediaBrowser 变体 | query token 鉴权、sampleRate 单位为 Hz | true / false / true / true / true / true |
| Audio Station | AudioStationAdapter | Synology WebAPI | 无 scrobble、无曲库变更标记 | true / false / false / false / false / false |
| 飞牛 fnOS | FnOsAdapter | 飞牛音乐私有 API | 固定 `/music` 子路径（host:port 自动补全） | false / false / false / false / false / false |

**继承关系**：Navidrome/Subsonic `extends SubsonicProtocolAdapter`；Jellyfin/Emby `extends MediaBrowserAdapter`；Plex / Audio Station / fnOS 直接 `implements ServerAdapter`。全部适配器 `with SecretsUpdatable`（401 静默重登后把新令牌回写到 ServerRepository）。

**共享实现层**：
- `SubsonicProtocolAdapter`（P1-A）：Subsonic 与 Navidrome 的媒体直链（stream/download/封面）、资料库六扩展、版本号与转码探测（含 TranscodeProbeCache 持久化）全部上提，子类只提供 `dio/auth/api/parseSong` 四钩子。
- `MediaBrowserAdapter`：Jellyfin 与 Emby 共用；`authenticateByName(client:, md5Password:)` 统一 `/Users/AuthenticateByName` 登录与静默重登。
- `ReauthInterceptor`（P1-C）：MediaBrowser 系（header 重写）与 Plex（query token 重写）共用同一 QueuedInterceptor 实现。
- 异常统一抛 `AppError` 子类；吞错路径必须走 `adapterSwallowLog` 留痕。

### 2.2 ServerType 枚举

```dart
enum ServerType { navidrome, subsonic, jellyfin, emby, audioStation, plex, fnos }
```

每个变体包含：
- `displayName`: 显示名称（Navidrome/Subsonic/Jellyfin/Emby/Audio Station/Plex/飞牛音乐）
- `urlHint`: 输入提示（如 `192.168.1.10:4533`；fnOS 为 `192.168.1.10:5666`）
- `pathHint`: 子路径提示（fnOS → `/music`，其余 → `选填`）
- `tagline`: 描述文案（开源音乐流媒体/经典音乐服务器协议/免费媒体系统等）
- `fallbackIcon`: IconData（fnOS 为 Icons.music_note）
- `hasLogoAsset`: true，图标资源在 `assets/app/$name.png`
- `implemented`: 该后端是否已落地
- `createAdapter(config, secrets, [networkSettings])`: 工厂方法创建适配器（NetworkSettings 显式注入，§15.5）
- 各类型另有 `static Future<AdapterSession> signIn(AuthRequest)` 登录工厂

### 2.3 AdapterCapabilities 能力声明

```dart
class AdapterCapabilities {
  final bool ratings;            // 评分支持（0-5星）
  final bool similarSongs;       // 相似歌曲推荐（播放页「相似歌曲」读取）
  final bool download;           // 服务端下载支持（默认 true）
  final bool artistBio;          // 歌手简介（部分后端无此接口）
  final bool transcoding;        // 服务端转码（音质分档的前提）
  final bool scrobbling;         // Scrobble 上报（Audio Station 无接口）
  final bool versionedSnapshot;  // 曲库变更标记（版本快照同步前提；非 delta 增量）
}
```

> P1-C 起 `likedSongs` / `lyrics` 两字段已删除（全库零读取，且 Plex 曾声明 `lyrics:true` 而 `fetchLyrics` 恒 null，属自相矛盾）。`incrementalSync` 已正名 `versionedSnapshot`。

### 2.4 ServerAdapter 核心 API

```dart
abstract class ServerAdapter {
  ServerType get type;
  AdapterCapabilities get capabilities;

  // 资料库读取
  Future<List<Album>> fetchAlbums(AlbumQuery query);
  Future<List<Song>> fetchSongs(SongQuery query);
  Future<List<Song>> fetchAlbumSongs(String albumId);
  Future<List<Album>> fetchArtistAlbums(String artistId);
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30});
  Future<List<Playlist>> fetchPlaylists();
  Future<List<Song>> fetchPlaylistSongs(String playlistId);
  Future<List<Song>> fetchLikedSongs({int limit = 100});
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20});
  Future<String?> fetchArtistBio(String artistId);       // null = 不支持/无简介

  // 搜索
  Future<SearchResult> search(String query);
  Future<int> fetchSongCount();

  // 交互操作
  Future<bool> setStar(String id, bool starred);
  Future<bool> setRating(String id, int rating);
  Future<bool> addToPlaylist(String playlistId, String songId);

  // 上报
  Future<bool> scrobble(String songId);                  // false = 不支持
  Future<bool> nowPlaying(String songId);                 // false = 不支持

  // 增量同步
  Future<String?> libraryVersion();                       // null = 不提供

  // 歌词文本（null = 不支持/无歌词；Navidrome JSON 或经典 LRC 原文）
  Future<String?> fetchLyrics(String songId);

  // 扩展资料库（null = 不支持）
  Future<List<Artist>?> fetchArtists();
  Future<List<Artist>?> fetchAlbumArtists();
  Future<List<Genre>?> fetchGenres();
  Future<List<RadioStation>?> fetchRadioStations();
  Future<List<Song>?> fetchGenreSongs(String genre, {int limit = 100});

  // 歌单维护
  Future<bool> createPlaylist(String name);
  Future<bool> removeFromPlaylist(String playlistId, String songId);  // 默认实现返回 false

  // 播放源解析
  Future<PlaybackSource> resolveStream(Song song, {QualityHint? quality});
  Future<PlaybackSource> resolveDownload(Song song);

  // 转码探测（默认信任 static capabilities）
  Future<bool> supportsTranscode();                       // 播放侧另有回退兜底

  // 封面
  ImageSource? coverImage(String albumId, {int size = 300});
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64});

  // 生命周期
  Future<bool> validateSession();
  void dispose();
}
```

### 2.5 AlbumQuery / SongQuery 查询参数

**AlbumQuery**: sort(name/recentlyAdded/recentlyPlayed/mostPlayed/random/year), start=0, limit=20, seed?, artistId?, descending=true

**SongQuery**: sort?(title/random/rating/recentlyAdded/recentlyPlayed/mostPlayed/track), start=0, limit=50, seed?, artistId?, albumId?, starredOnly=false

**SongSort 枚举**: title, random, rating, recentlyAdded, recentlyPlayed, mostPlayed, track

**AlbumSort 枚举**: recentlyAdded, recentlyPlayed, mostPlayed, random, name, year

### 2.6 AuthRequest / AdapterSession / PlaybackSource / ImageSource

```dart
class AuthRequest {
  final String serverUrl;    // 含协议完整 URL
  final String username;
  final String password;
  final String deviceId;     // 默认 ''
  final Map<String, String> extra;  // 默认 {}
}

class AdapterSession {
  final Map<String, String> secrets;     // 认证令牌/盐/密钥
  final Map<String, String> meta;        // 元数据（用户名等）
  final String? displayName;
}

class PlaybackSource {
  final String url;
  final Map<String, String> headers;     // HTTP 头（鉴权等），默认 {}
}

class ImageSource {
  final String url;
  final Map<String, String> headers;
}
```

---

## 三、数据模型（models.dart 详细版）

### 3.1 Json 辅助工具类（P1-D 单源）

私有 `_Json` 已提升为公共 `Json`（models.dart），五个适配器的本地 JSON 静态方法（`_s/_i/_iOrNull/_n/_firstStr/_firstNum/_doubleOrNull` 等副本）改为委托调用，调用点短名不变。

提供安全解析：`str(j, key, fallback)`, `strOf(j, [keys], fallback)`（依次取第一个非空字段）, `intOf/doubleOf/boolOf`（带类型回退）, `strOrNull/doubleOrNull/intOrNull`（可缺省版，全缺返回 null）, **`intOfOrNull`**（单键、仅接受 `num`，用 `is num` 判定——字符串值返回 null 而非抛 TypeError）, **`firstStr`**（候选键逐个 trim 取首个非空）。

### 3.2 Song 歌曲模型

```dart
class Song {
  const Song({
    required this.id,
    required this.title,          // 缺省 '未知歌曲'
    required this.artist,         // 缺省 '未知歌手'
    required this.album,          // 可为空
    required this.albumId,
    required this.artistId,
    required this.duration,       // double，单位秒
    required this.playCount,      // int
    required this.starred,        // bool
    required this.size,           // int，字节数
    required this.rating,         // int 0-5
    this.lyrics,                  // String?，Navidrome JSON 格式
    this.suffix,                  // String?，容器后缀 flac/mp3/m4a
    this.codec,                   // String?，解码器 FLAC/AAC
    this.bitRate,                 // int? kbps
    this.sampleRate,              // int? Hz（已由 _sampleRateHz 归一：<=1000 视为 kHz * 1000）
    this.bitDepth,                // int? 位深 16/24
    this.albumArtist,             // String? 专辑艺术家
    this.year,                    // int? 年代
    this.discNumber,              // int? 碟号
    this.trackNumber,             // int? 音轨号
    this.path,                    // String? 服务端文件路径
    this.lastPlayed,              // String? ISO8601 原文
    this.created,                 // String? ISO8601 入库时间
    this.replayGain,              // ReplayGain? 回放增益
    this.localCoverPath,          // String? 本地内嵌封面路径
  });

  factory Song.fromJson(Map<String, dynamic> j)  // 容错解析，字段回退链
  Song copyWith({bool? starred, int? rating})     // 收藏乐观更新用
  Map<String, dynamic> toJson()                   // 序列化（剔除 lyrics 以减小体积）
  static List<Song> listFromJson(dynamic json)
}
```

**关键字段回退链**:
- `albumArtist`: `['albumArtist', 'albumArtistName']`
- `sampleRate`: `_sampleRateHz()` — <=1000 视为 kHz
- `suffix`: `['suffix', 'transcodedSuffix', 'contentType']`
- `bitRate`: `['bitRate', 'bitrate']`
- `path`: `['path', 'filePath']`
- `lastPlayed`: `['played', 'lastPlayed', 'lastPlayedAt']`
- `created`: `['created', 'createdAt', 'created_at', 'dateCreated']`
- `trackNumber`: `['trackNumber', 'track']`

### 3.3 Album 专辑模型

```dart
class Album {
  final String id;
  final String name;            // 缺省 '未知专辑'
  final String artist;          // 回退 ['artist', 'albumArtist']
  final String artistId;        // 回退 ['artistId', 'albumArtistId']
  final int songCount;
  final double duration;
  final int playCount;
  final bool starred;
  final int rating;
  final int? year;              // 优先 maxYear，fallback year
}
```

### 3.4 Artist 歌手模型

```dart
class Artist {
  final String id;
  final String name;            // 缺省 '未知歌手'
  final int albumCount;
  final int songCount;
}
```

### 3.5 Genre 流派模型

```dart
class Genre {
  final String value;
  final int songCount;
  final int albumCount;
}
```

### 3.6 RadioStation 网络电台模型

```dart
class RadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String? homePageUrl;
}
```

### 3.7 Playlist 歌单模型

```dart
class Playlist {
  final String id;
  final String name;            // 缺省 '未命名歌单'
  final int songCount;
  final String? coverArt;       // 封面 ID（getCoverArt 用）
  final String? owner;          // 所有者用户名（区分「我的/全部歌单」）

  factory Playlist.fromJson(j) => Playlist(
    owner: (j['owner'] ?? j['ownerName'])?.toString(),  // ownerName 兜底
  );
}
```

### 3.8 ReplayGain 回放增益模型

```dart
class ReplayGain {
  final double? albumGain;    // 专辑增益 dB
  final double? albumPeak;    // 专辑峰值
  final double? trackGain;    // 音轨增益 dB
  final double? trackPeak;    // 音轨峰值
}
```

### 3.9 SearchResult 搜索结果

```dart
class SearchResult {
  final List<Song> songs;
  final List<Album> albums;
  final List<Artist> artists;
  bool get isEmpty => 三者皆空
}
```

---

## 四、状态管理与 Riverpod Provider（完整版）

### 4.1 认证与服务器

#### 4.1.1 AuthState 数据模型

```dart
class AuthState {
  final List<ServerConfig> servers;
  final String? activeServerId;
  final Map<String, String> activeSecrets;
  final bool initialized;
  bool get isAuthenticated => activeServerId != null;
  ServerConfig? get activeConfig => 从 servers 中查找 activeServerId
}
```

#### 4.1.2 AuthController 控制器

| 方法 | 功能 |
|------|------|
| `build()` | 调用 `_restore()` 初始化时恢复所有服务器和当前激活服务器 |
| `_restore()` | 迁移 legacy session → 加载 servers + activeId + secrets → 设置 state |
| `login(type, url, username, password)` | 调用 type.signIn → 生成 UUID id → 保存 config/secrets/activeId → 更新 state |
| `switchServer(id)` | 验证 config 存在 → 加载 secrets → 保存 activeId → 更新 state |
| `validateServer(id)` | 创建临时 adapter → 调用 validateSession → 释放 |
| `removeServer(id)` | 删除 config/secrets/activeId（如果是当前则清除 active） |
| `logout()` | 清空当前会话的所有服务器数据 |
| `storedPassword(id)` | 读出某台服务器已存的登录密码（供编辑页回填，:131） |
| `editServer({...})` | 编辑服务器（:143）：URL/账密/名称/子路径变更后**完整重登校验**，通过才落盘；若激活服被改则就地重建 adapter。仅改备注名走离线快路径，不发网络请求 |
| `updateStoredSecrets(id, fresh)` | 401 静默重登后由 adapter 回写新令牌（`SecretsUpdatable` 回调） |

> P1-B 起 `serverAdapterProvider` / `transcodeSupportProvider` / `activeServerIdProvider` 已下沉到 `core/api/adapter_provider.dart`，core 通过 `activeServerSessionProvider`（组合根注入）取会话，方向恢复 features→core 单向；`auth_controller.dart` re-export 旧位置，导入路径不变。

#### 4.1.3 normalizeServerUrl

- 去空白
- 无前缀自动补 `http://`
- 去除尾部 `/`

#### 4.1.4 serverAdapterProvider

```dart
final serverAdapterProvider = Provider<ServerAdapter?>((ref) {
  final auth = ref.watch(authControllerProvider);
  // 网络设置显式注入 adapter（P1-NetworkRuntime：无全局可变状态）；
  // 网络设置变更时重建 adapter，让超时/代理/证书/hosts 重新生效
  final net = ref.watch(networkSettingsProvider);
  final config = auth.activeConfig;
  if (config == null) return null;
  final adapter = config.type.createAdapter(config, auth.activeSecrets, net);
  ref.onDispose(adapter.dispose);
  return adapter;
});
```

#### 4.1.5 transcodeSupportProvider

```dart
final transcodeSupportProvider = FutureProvider<bool>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return false;
  return adapter.supportsTranscode();
});
```
后台静默探测，真结果缓存在 adapter 会话内；探测完成前 value 为 null，UI 先按支持显示、播放侧另有回退兜底。

### 4.2 播放内核（player_controller.dart）

#### 4.2.1 播放状态 Provider 矩阵

| Provider | 类型 | 用途 | 数据来源 |
|----------|------|------|----------|
| `audioPlayerProvider` | Provider<AudioPlayer> | 全局唯一 AudioPlayer（App 生命周期持有） | AudioPlayer.new → onDispose dispose |
| `currentSongProvider` | StateProvider<Song?> | 当前歌曲（仅切歌时变化） | PlayerActions.play() |
| `queueProvider` | NotifierProvider<List<Song>> | 播放队列 | QueueNotifier |
| `shuffleOrderProvider` | StateProvider<ShuffleOrderState> | 全队列随机遍历序 + 游标（§15.2） | PlayerActions 维护，随 player_state 持久化 |
| `nextSongProvider` | Provider<Song?> | 下一首预判 | 依赖 queue + currentSong + playMode + shuffleOrder |
| `playModeProvider` | StateProvider<PlayMode> | 播放模式 | order/shuffle/repeatOne |
| `playbackSpeedProvider` | StateProvider<double> | 播放速度 0.5-3.0 | 随播放状态持久化 |
| `replayGainModeProvider` | StateProvider<ReplayGainMode> | 响度归一：off / track / album | 默认 off（不持久化） |
| `loopPlaybackProvider` | StateProvider<bool> | 循环播放（队列播完回首） | 默认 true |
| `autoPlayProvider` | StateProvider<bool> | 启动后自动播放 | 默认 false |
| `fmActiveProvider` | StateProvider<bool> | 私人 FM 漫游中（§4.21） | FM start/stop 与整表播放置位/清除 |
| `playerReadyProvider` | StateProvider<bool> | 冷启动恢复 READY 信号；Scrobble 等位置监听方必须忽略 READY 前的 position 事件 | player_restore |
| `currentQualityProvider` | StateProvider<StreamQuality?> | 本次播放实际生效音质档（音质徽标展示） | play() 解析源时写入 |
| `crossfadeSecondsProvider` | NotifierProvider<int> | 交叉淡化 0-10 秒 | 持久化 key='crossfade_seconds' |
| `autoOpenPlayerProvider` | NotifierProvider<bool> | 点击歌曲自动打开全屏播放页 | 默认 true，持久化 |
| `sleepTimerProvider` | NotifierProvider<Duration?> | 定时停止，null=未启用 | 不持久化 |
| `bilingualLyricsProvider` | NotifierProvider<bool> | 双语歌词开关（MiniBar 副标题与全屏歌词共用，切换即时刷新） | 持久化 key='lyrics_bilingual_enabled'，默认 true |
| `resumeNoticeProvider` | StateProvider<String?> | 续播提示/错误消息，由常驻 UI 层经 AppToaster 消费 | |

#### 4.2.2 流式状态 Provider（StreamProvider）

| Provider | 类型 | 用途 | 节流策略 |
|----------|------|------|----------|
| `isPlayingProvider` | StreamProvider<bool> | 播放/暂停 | processingState.playing.map().distinct() |
| `positionProvider` | StreamProvider<Duration> | 播放进度 | just_audio positionStream (~200ms 节流) |
| `durationProvider` | StreamProvider<Duration?> | 曲目时长 | durationStream |
| `bufferedPositionProvider` | StreamProvider<Duration> | 缓冲位置 | bufferedPositionStream |
| `isBufferingProvider` | StreamProvider<bool> | 缓冲中状态 | processingState==buffering/loading |

#### 4.2.3 QueueNotifier 方法

```dart
class QueueNotifier extends Notifier<List<Song>> {
  void add(List<Song> songs)                    // 追加到队尾
  void replaceAll(List<Song> songs)             // 替换整个队列
  void clear()                                  // 清空
  void remove(String songId)                    // 按 id 移除
  void replaceSong(String songId, Song song)    // 原地更新某首歌（收藏乐观更新）
  void reorder(int oldIndex, int newIndex)      // 拖动排序（newIndex 已修正移除位）
  void insertAfterCurrent(List<Song> songs)     // 下一首播放：插到当前之后（去重）
}
```

#### 4.2.4 nextSongProvider 判断逻辑

```dart
// 依赖: queueProvider + currentSongProvider + playModeProvider + shuffleOrderProvider
// P1-ShuffleOrder：shuffle 走整队列随机遍历序（ShuffleOrderState.order + 游标 pos），
// 预判 = order[pos+1]，与 playNext 实际取歌严格一致；一轮播完由 playNext 重新洗牌
nextSong = switch (playMode) {
  PlayMode.repeatOne => null,                              // 单曲循环不预测下一首
  PlayMode.shuffle => pos+1 在遍历序内 ? order[pos+1] 对应歌 : null,
  PlayMode.order => index < length-1 ? queue[index+1] : loop ? queue.first : null,
};
```

#### 4.2.5 PlayerActions 类详解

**文件组织（P1 渐进式拆分）**: `player_controller.dart` 保留全部 Provider 状态源与
`playerActionsProvider` 构造入口；类体在 `player_actions.dart`，职责块按 part 拆出
`player_source_resolver / player_crossfade / player_breakpoint / player_persistence /
player_restore / player_error_handler`（共享私有状态放 `PlayerActionsBase` 基类）。

**构造与初始化**:
1. listen `playModeProvider` → 同步 setLoopMode + 持久化
2. listen `playbackSpeedProvider` → 同步 setSpeed
3. listen `currentSongProvider` + `queueProvider` → 维护 Shuffle 遍历序 + debounce 持久化
4. _initialize(): RESTORING（_restore 恢复队列/当前歌/进度）→ _bindPlayerEvents
   （completed 自动切歌 + positionStream 驱动交叉淡化）→ READY（playerReadyProvider）
   → READY 后才允许恢复后自动播放（P0-PLAYER-01 严格顺序）

**核心方法**:

```dart
Future<void> play(Song song)  // 播放指定歌曲
  - 代数守卫 (_playGeneration++) → 连点作废旧请求
  - 时序铁律：resolveStream 返回后、_setStreamSource 写音源**之前**必须再验一次代数；
    catch 入口旧代数直接静默 return（不再发起无损回退，避免与新请求竞争音源）；
    _playLocal 写音源前同样补验 —— 否则旧请求晚完成会把旧歌音源覆写到播放器上打断新歌加载
  - 本地文件优先 → _playLocal() (id 含 'local:' 前缀或已下载)
  - 音质档位 → resolveCurrentQuality(settings) → 蜂窝门禁检查
  - 转码探测 → supportsTranscode() → 不支持直接走无损
  - 边听边存 → LockCachingAudioSource vs 直连
  - 转码失败回退无损 → 无损也失败才报网络错误
  - 长音频断点 → _saveLongTrackBreakpoint() + _resumeLongTrack()

Future<void> toggle()  // 播放/暂停
  - playing → pause
  - idle + 有恢复进度 → play(song) → seek(resumeMs)
  - 其他 → play()

Future<void> playNext()  // 下一首
  - repeatOne → _restartCurrent() (seekTo(0) + play)
  - shuffle → 沿遍历序游标前进；一轮完整遍历后重新洗牌开启新一轮
    （新轮次避免与当前曲重复起头）
  - order → queue[index+1] 或 loop ? queue.first : seek(0)+pause

Future<void> playPrevious()  // 上一首
  - repeatOne → restart
  - shuffle → 沿遍历序游标回退（本轮开头无历史则不动）
  - order → queue[index-1]

Future<void> seek(Duration position)  // 跳转进度
  - 长音频 (>10min) 持久化断点
```

**交叉淡入淡出 (Crossfade)**:
- 参数范围: 0-10 秒，默认 0（关闭），持久化
- 触发条件: `duration - pos > seconds && duration > seconds*2 && playing && 有真实下一首`
  （下一首预判复用 nextSongProvider，保证淡入的歌就是触底文案预告的歌）
- 实现方式: 音量自动化近似（just_audio 无原生 crossfade），100ms 固定步进，
  步数 = seconds*1000/100 由时长派生（P1-Crossfade 语义统一，无固定步数业务语义）
- 防重入: `_fading` 标志

**长音频断点续播**:
- 阈值: Duration > 10 分钟
- 持久化: `SharedPreferences` key=`breakpoint_<songId>`，毫秒精度
- 恢复: 播放开始时检测 saved > 60000ms → seek(saved) → 弹出提示
- 时机: 切歌前 save + seek() 后 save

**播放状态持久化**:
- key: `'player_state'`
- 内容: queue(first 100) + currentSong + playMode + speed + loopPlayback + currentTime
- 恢复: _restore() → 重建 state → 如果有 currentTime → seekTo(position)

**歌词偏移持久化**:
- prefix: `'lyricOffset_'`
- key 拼接 song.id

**双语歌词开关**:
- key: `'lyrics_bilingual_enabled'`
- 全局，默认开启

#### 4.2.6 封面取色与皮肤连续性（album_tint.dart）

动态取色三件套，保证切歌全程颜色不断档：

| Provider | 形态 | 职责 |
|----------|------|------|
| `albumDominantColorProvider` | `FutureProvider.autoDispose.family<Color?, String>`（key=albumId） | 原生端 `CachedNetworkImageProvider` 共用 `CoverCacheManager` 的 300 档缓存与在途下载，Web 用 `NetworkImage`；`ResizeImage` 将实际解码限制在 64×64 内，`PaletteGenerator` 最多 16 色，按 vibrant → muted → dominant 返回；成功结果 `keepAlive` 3 分钟，切服随 adapter 失效；异常返回 null，不阻塞播放器 |
| `lastAlbumDominantProvider` | `StateProvider<Color?>` | 进程级记忆「最近一次成功取到的主色」 |
| `currentAlbumDominantProvider` | `Provider.autoDispose<Color?>` | 生效主色 = 本次取色结果 ?? 上一首成功取色 |

三条硬性约束：

1. **鉴权 header 必须透传**：原生 `CachedNetworkImageProvider` 与 Web `NetworkImage` 均传
   `headers: cover.headers`。带 header 鉴权的后端（fnOS / MediaBrowser 系）不透传会 401；
   原生有效磁盘缓存命中时直接读取本地文件。
2. **不在 build 期写 state**（Riverpod 红线）：`currentAlbumDominantProvider` 用
   `currentSongProvider.select((s) => s?.albumId)` 只在专辑变化时重建，取色结果到达后经
   `ref.listen` 写入 `lastAlbumDominantProvider`——同步写 state 会让取色永远停在 loading。
3. **切歌不闪回默认色**（用户钦定）：新封面取色未到位期间，播放页 / 弹层 / 迷你条 / 皮肤
   沿用上一首颜色；从未取到过才回退莫奈主色。

取色材质梯度（全部由 dominant 单色派生，无独立硬编码色）：

| 函数/组件 | 公式 | 用途 |
|-----------|------|------|
| `albumAdaptiveTint(d)` | `lerp(d, black, 0.42)` α0.55 | 播放页自适应面板：底部控制栏 / 歌词浮层 / 队列 / 操作弹窗共用，与页面背景渐变顶端同公式 |
| `albumSolidTint(d)` | `lerp(d, black, 0.55)` 实色 | 播放页弹层不透明底色（去玻璃），保证白字可读 |
| `albumFrostedTint(d)` | `lerp(d, black, 0.55)` α0.90 | `glassBottomSheet` 近实色取色 tint（定时停止 / 播放速度） |
| `AlbumFrostedPanel` | `BackdropFilter(blur 28)` + `withGlassTintOpacity(base α0.90)` | 毛玻璃面板；`opaque: true` 时去掉模糊层走全实色，供歌曲上下文弹层（更多 / 添加到歌单）使用 |

`dominant == null` 时上述函数一律返回 null，由调用方回退主题表面色。

### 4.3 SleepTimerNotifier

```dart
class SleepTimerNotifier extends Notifier<Duration?> {
  void start(Duration duration)  // Timer.periodic(1s)，剩余倒计时 setState
  void cancel()  // 停止 timer + 重置 state=null
}
// state=Duration? → 显示剩余 HH:MM:SS；null=未启用
```

### 4.4 CrossfadeSecondsNotifier

```dart
class CrossfadeSecondsNotifier extends Notifier<int> {
  @override int build() => prefs.getInt('crossfade_seconds') ?? 0;
  void set(int seconds) { state = seconds.clamp(0, 10); persist; }
}
```

### 4.5 AutoOpenPlayerNotifier

```dart
class AutoOpenPlayerNotifier extends Notifier<bool> {
  @override bool build() => prefs.getBool('auto_open_player') ?? true;
  void set(bool v) { state = v; persist; }
}
```

### 4.6 在线音质与网络设置（streaming_prefs.dart）

#### 4.6.1 StreamQuality 音质档位

```dart
enum StreamQuality {
  lossless('无损', 0),     // 0 = 不转码，播原文件
  k320('320 kbps', 320),
  k256('256 kbps', 256),
  k192('192 kbps', 192),
  k128('128 kbps', 128),
}
```

#### 4.6.2 TranscodeFormat 转码格式

```dart
enum TranscodeFormat { mp3('MP3'), opus('OPUS'); }
```

#### 4.6.3 QualityHint

```dart
class QualityHint {
  final StreamQuality quality;
  final TranscodeFormat format;
  bool get transcode => quality != StreamQuality.lossless;
}
```

#### 4.6.4 TranscodeProbeCache 转码探测持久化

```dart
abstract final class TranscodeProbeCache {
  static String _key(serverUrl, username) {
    digest = SHA-256('$serverUrl|$username').substring(0, 16)
    → 'transcode_probe_<16-char-hash>'
  }
  static Future<bool?> get(...)  // 读取缓存
  static Future<void> set(..., bool supported)  // 写入缓存
}
```
缓存意义: 探测要发 2 个网络请求，不缓存则每次冷启动首播前都白等一轮。换服务器/账号后 key 不同自动重探。

#### 4.6.5 StreamingSettings

```dart
class StreamingSettings {
  final StreamQuality wifiQuality;        // 默认 lossless
  final StreamQuality cellularQuality;    // 默认 k320
  final TranscodeFormat transcodeFormat;  // 默认 mp3
  final bool cellularAllowed;             // 默认 true
}
```

prefs keys: `'quality_wifi'`, `'quality_cellular'`, `'transcode_format'`, `'cellular_allowed'`

#### 4.6.6 resolveCurrentQuality

```dart
Future<StreamQuality?> resolveCurrentQuality(StreamingSettings s) async {
  // 1. Connectivity().checkConnectivity()
  // 2. cellular = results.contains(mobile)
  // 3. cellular && !cellularAllowed → return null（播放器据此拒播）
  // 4. cellular ? s.cellularQuality : s.wifiQuality
}
```

#### 4.6.7 NetworkSettings

```dart
class NetworkSettings {
  final int timeoutSeconds;       // 默认 10
  final String proxy;             // 空=跟随系统，格式 '127.0.0.1:7890'
  final bool verifyCertificates;  // 默认 true，自签名内网可关闭
  final String hostOverrides;     // 格式 '域名=IP;域名=IP'
  Map<String, String> get hostMap  // ';' 分隔解析为 map
}
```

prefs keys: `'net_timeout'`, `'net_proxy'`, `'net_verify_certs'`, `'net_host_overrides'`

### 4.7 缓存系统（cache_manager.dart）

#### 4.7.1 CacheLimit 限额档位

```dart
enum CacheLimit {
  g2('2 GB', 2 * 1024 * 1024 * 1024),
  g5('5 GB', 5 * 1024 * 1024 * 1024),
  g10('10 GB', 10 * 1024 * 1024 * 1024),
  unlimited('无限制', null),  // null.bytes = 不过限
}
```

#### 4.7.2 CacheSettings

```dart
class CacheSettings {
  final bool cacheWhileListen;     // 默认 true，走 LockCachingAudioSource
  final bool autoDownload;         // 默认 false，后台预取「我喜欢」
  final CacheLimit limit;          // 默认 g2
}
```

prefs keys: `'cache_while_listen'`, `'cache_auto_download'`, `'cache_limit'`

#### 4.7.3 AudioCache 工具类

```dart
abstract final class AudioCache {
  static Future<Directory> dir()          // getTemporaryDirectory()/just_audio_cache
  static Future<int> sizeBytes()          // 遍历目录累加文件大小，不存在返回 0
  static Future<void> clear()             // delete(recursive) + 重建
  static Future<void> enforceLimit(CacheLimit limit)  // LRU 清理：按 lastModified 从旧到新删
}
```

LRU 清理算法:
1. 遍历缓存目录所有 File
2. total += file.lengthSync()
3. total > maxBytes → files.sort(lastModifiedSync ascending) → 逐个 delete 直到 total <= maxBytes
4. 单个文件删除失败不影响整体

#### 4.7.4 audioCacheSizeProvider

```dart
final audioCacheSizeProvider = FutureProvider<int>((_) => AudioCache.sizeBytes());
```
清理后调用方 invalidate 刷新。

### 4.8 下载系统（download_service.dart + auto_download.dart）

#### 4.8.1 downloadSongFile

```dart
Future<String> downloadSongFile({
  required PlaybackSource source,
  required Song song,
  String serverId = '',
  NetworkSettings networkSettings = const NetworkSettings(),
  void Function(int received, int total)? onProgress,
})
```
- 文件名: `<safeName(artist - title)>--<fingerprint>.<ext>`
  - `ext` 取 `song.suffix`（flac/m4a 等真实容器），为空回退 `mp3`
  - `fingerprint = sha256('$serverId|$songId')[0:16]` — **含 serverId**：fnOS/Plex
    这类数字 id 服务器，不同服务器的同名 id 不得共用一个文件
- `.tmp` 临时文件下载 → 校验存在且非空 → 原子提交，最终路径永不出现半截文件
- 落盘位置：优先**公共音乐目录**（Android 10+ 经 MediaStore 写 `/sdcard/Music/流声/`，
  Windows 写「用户音乐库\流声\」）；iOS / Android 9- / 公共目录失败回退私有
  `Documents/Music`。Android 的 MediaStore 是 copy，成功后删掉私有残缺副本避免一首歌存两份
- `NetworkRuntime.configureDio(dio, networkSettings)`：代理/自签证书/hosts 映射对下载同样生效
- 成功后登记 `download_index`（含 `payload` = Song JSON 快照，供本地音乐合并展示）；
  索引写失败不影响文件本身
- connectTimeout=10s，receiveTimeout=5min

#### 4.8.2 findDownloadedSong

```dart
Future<String?> findDownloadedSong(Song song, String serverId)  // 未下载返回 null
```
反查顺序：`download_index` 索引（O(1)）→ 目录指纹扫描兜底并回填。三条一致性策略：

- 先查本服务器新指纹，未命中再查**旧版指纹**（`sha256(songId)[0:16]`，升级前的历史下载），
  命中且归属可确认（`server_id` 为空或等于本服务器）时就地把旧记录迁移到新指纹，不重下
- 索引命中但文件已丢失 → 懒修复（删失效记录）
- 目录兜底跳过 `.tmp`，绝不把半截文件当有效下载
- `cleanupOrphanTmpFiles()` 启动时清理 mtime 超过 1 小时的 `.tmp` 残留

#### 4.8.3 AutoDownload 自动下载

```dart
class AutoDownload {
  static bool _running = false;  // 防止并发
  static Future<void> run(RefReader read) async {
    // 1. adapter != null
    // 2. resolveCurrentQuality(settings) → null=蜂窝禁传，跳过
    // 3. _running guard
    // 4. adapter.fetchLikedSongs(limit: 50)
    // 5. for each song: if !cacheSettings.autoDownload → stop; if already downloaded → skip
    // 6. adapter.resolveDownload(song) → downloadSongFile(source, song)
    // 7. AudioCache.enforceLimit(limit)
  }
}
```

#### 4.8.4 maybeAutoDownload

```dart
void maybeAutoDownload(RefReader read) {
  if (!read(cacheSettingsProvider).autoDownload) return;
  unawaited(AutoDownload.run(read));
}
```
供三处业务触发（P1-AutoDownload：播放器不负责自动下载）：
1. serverAdapterProvider 从 null → 非 null（冷启动已登录/新登录成功，main.dart MusicApp listen）
2. onConnectivityChanged 回到 Wi-Fi/以太网（main.dart 启动段）
3. 收藏成功回调（audio_handler / full_screen_player / action_sheets）

#### 4.8.5 后台下载队列（download_queue.dart）

歌曲操作弹窗的「下载」只负责入列 + 提示，任务在后台顺序落盘，
用户无需停在进度对话框上等待（零等待原则）。

```dart
enum DownloadTaskStatus { waiting, running, completed, failed }

class DownloadTask {
  final String id;        // 'serverId|songId'：跨 async 去重与定位键
  final Song song;
  final String serverId;
  final DownloadTaskStatus status;
  final int received, total;
  final String? error;
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
}

class DownloadQueueController extends Notifier<List<DownloadTask>> {
  int enqueue(List<Song> songs, String serverId)  // 返回实际新增数，同 id 去重
  void retry(String id)      // 仅 failed：重建为干净 waiting
  void remove(String id)     // running 拒绝移除（无法中途取消，等它自然结束）
  void clearFinished()       // 清 completed+failed，保留 waiting+running
}
final downloadQueueProvider = NotifierProvider<DownloadQueueController, List<DownloadTask>>(...)
```

队列不变量：

| 机制 | 说明 |
|------|------|
| 单飞 | `_pumping` 重入守卫；`enqueue`/`retry` 后 `unawaited(_pump())`，while 循环逐个取 waiting |
| 落盘索引合并 | `_completedSinceDrain` 标记，**排空时只 bump 一次** `downloadIndexVersionProvider`——逐首 bump 会让 `localSongsProvider` 在批量下载期间连续全量重读（与 AutoDownload 收尾同策略） |
| 排队期切服 | `_runTask` 起跑时校验 `activeServerIdProvider != task.serverId` → failed `'服务器已切换，任务取消'`（任务可能排队很久） |
| 已下载短路 | 起跑先 `findDownloadedSong`，命中直接标完成（重复点击不会重下） |
| 进度节流 | `_progress` 仅在 ≥2% 步进（或最终块）时重建列表——`onProgress` 每个数据块都回调 |
| 错误分类 | `DioException` → `'网络错误'`，其他 → `'下载失败'` |
| 收尾 | `finally` 清 `_pumping` 与 `_lastProgressAt` |

### 4.9 ScrobbleService

```dart
class ScrobbleService {
  // 构造时订阅:
  // 1. audioPlayerProvider.positionStream → _onPosition
  // 2. Connectivity().onConnectivityChanged → _flush
  // 3. unawaited(_flush()) → 启动补发
}
```

#### 4.9.1 _onPosition 触发条件

- 歌曲变化 → reset `_submitted = false`
- `_submitted` 已为 true → 跳过
- 时长 null 或零 → 跳过
- 触发: `pos >= dur * 0.5 || pos >= Duration(minutes: 2)`（先到先触发）

#### 4.9.2 _report 上报逻辑

- adapter null / serverId null / !scrobbling → 不上报也不入队
- adapter.scrobble(songId) 成功 → 返回
- 失败 → _enqueue 入 SQLite `scrobble_queue`

#### 4.9.3 _flush 补发逻辑

- 同 _report 前置检查
- SQL: `SELECT * FROM scrobble_queue WHERE server_id=? ORDER BY created_at ASC LIMIT 50`
- 逐条 scrobble → 成功 delete，失败停止本轮（队列原样保留避免重复上报丢失）

#### 4.9.4 scrobble_queue 表字段

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PRIMARY KEY AUTOINCREMENT | |
| server_id | TEXT NOT NULL | 归属服务器 |
| song_id | TEXT NOT NULL | 歌曲 ID |
| created_at | INTEGER NOT NULL | 毫秒时间戳 |

### 4.10 曲库版本快照同步（library_sync.dart）

> 命名说明：这是 **versionedSnapshot（版本快照）**，不是 delta 增量同步——服务端只给
> 轻量变更标记，标记一变即全量重拉。字段级快照规格与 kind 清单见 §7.1。

#### 4.10.1 LibrarySync.songs

```dart
static Future<List<Song>> songs(RefReader read) async {
  // kind: 'songs_all_v2'
  // query: SongQuery(sort=title, limit: 100000)
  // 调用点：librarySongsProvider（资料库「歌曲」入口）
  // 展示顺序由 UI 侧决定：按 created 倒序，无 created 的沉底再按标题排
}
```

#### 4.10.2 LibrarySync.albums

```dart
static Future<List<Album>> albums(RefReader read) async {
  // kind: 'albums_name_v2'
  // query: AlbumQuery(sort=name, limit: 10000)
  // 调用点：libraryAlbumsProvider（服务器详情页全量快照）；
  // 资料库专辑列表页不走这里，改用 LibraryAlbumsController 真 offset 分页
  //（fetchAlbums 原生支持 start/limit，每页 60 张）
}
```

#### 4.10.3 _load 同步算法

```dart
Future<List<T>> _load<T>({String kind, Future<List<T>> fetch, encode, decode}) async {
  // 1. !capabilities.versionedSnapshot（如 Audio Station）→ 直接 fetch()，如实降级每次全量
  // 2. 读 SQLite library_snapshot（server_key + kind）
  // 3. adapter.libraryVersion() → 5s timeout，失败/超时按 current=null 处理
  // 4. 有快照且（current == null ‖ current == cachedVersion）→ decode(cachedPayload)
  //    弱网/离线时版本标记不可用，已有快照就是最可靠的可用数据
  // 5. 标记变化 → fetch() fresh；快照落库单独 try/catch，
  //    写库失败只跳过补写，fresh 照常返回（不吞掉成功的拉取）
  // 6. 外层任一环节抛错 → 有 cachedPayload 则 decode 兜底
  // 7. 兜底也没有 → 重新抛出：fetch 已失败过一次，弱网下不再立即重试第二次全量，
  //    交给调用方错误态 + 下拉刷新/下次进入重试
}
```

### 4.11 本地音乐（local_library.dart）

#### 4.11.1 scanLocalLibrary 流程

1. `Isolate.run(() => _scanIsolate(dirPaths, coverDirPath))` — 纯 Dart IO 函数运行在隔离线程
2. 主 isolate 上处理: 歌词落库 + 封面落盘 + 内存构建 Song 列表
3. 返回 `List<(Song, (String, String, String)?)>` — lyricKey/title/content

#### 4.11.2 _scanIsolate 纯 Dart 函数

- 遍历 Music/Download 目录
- 过滤音频后缀 (flac/mp3/m4a/wav/aac/ogg/ape)
- audio_metadata_reader 读取 ID3 标签
- 内嵌 LRC 解析
- 内嵌封面抽取 → saves to covers directory

#### 4.11.3 localScanVersionProvider

```dart
final localScanVersionProvider = StateProvider<int>((ref) => 0);
```
bump-driven 刷新机制，配合 5 分钟限流。

#### 4.11.4 localSongsProvider

```dart
final localSongsProvider = FutureProvider.family<List<Song>, bool?>((ref, served) async {
  // 1. watch localScanVersionProvider
  // 2. read cache from SQLite (library_snapshot with server_key='local', kind='local_songs')
  // 3. 有缓存 → 立即返回缓存 + launch background rescan
  // 4. 无缓存 → 同步扫描
  // 5. 5 分钟限流：_rescanInBackground(ref, served)
});
```

#### 4.11.5 _sameSongs 比较

比较长度 + id + size + duration + title + artist → 任一不同视为文件变化需要重扫

#### 4.11.6 本地歌曲 ID 规范

- 前缀: `local:`
- 格式: `local:${file.path}`
- 与服务器歌曲天然不冲突

### 4.12 悬浮歌词（floating_lyrics.dart）

#### 4.12.1 FloatingLyrics 抽象类

```dart
abstract final class FloatingLyrics {
  static const _channel = MethodChannel('com.silencetop.liusound/floating_lyrics');
  static final _closed = StreamController<void>.broadcast();
  static final _permissionChanges = StreamController<bool>.broadcast();

  // 原生侧回调:
  // 'closed' → _closed.add(null)
  // 'permissionChanged: true/false' → _permissionChanges.add(...)

  static bool get supported => Platform.isAndroid;  // iOS 无对应能力

  static Future<bool> hasPermission()    // 查 SYSTEM_ALERT_WINDOW
  static Future<void> requestPermission() // 跳转系统设置页
  static Future<void> update(current, next)  // 推送双行歌词文本
  static Future<void> hide()                // 隐藏小窗
}
```

#### 4.12.2 floatingLyricsDataProvider

```dart
final floatingLyricsDataProvider = Provider<LyricsData?>((ref) {
  final song = ref.watch(currentSongProvider);
  if (song == null) return null;
  return parseLyricsData(song.lyrics);  // 仅切歌时重新解析
});
```

#### 4.12.3 floatingLyricsOverlayProvider

```dart
final floatingLyricsOverlayProvider = Provider<({String current, String next})?>((ref) {
  // !ref.watch(floatingLyricsProvider) → null（隐藏小窗）
  // data empty → null
  // pos null → null
  // findLyricIndex(data.lines, pos.microseconds/1e6) < 0 → null
  // else → (current: lines[idx].text, next: idx+1 < len ? lines[idx+1].text : '')
});
```

### 4.13 歌词系统（lyrics.dart）

#### 4.13.1 LyricLine / LyricsData

```dart
class LyricLine {
  final double time;   // 秒
  final String text;
}

class LyricsData {
  final List<LyricLine> lines;           // 主轨（原文）
  final List<LyricLine> translations;    // 译轨（无译轨时空列表）
}
```

#### 4.13.2 parseLyricsData（Navidrome JSON 格式）

```dart
LyricsData parseLyricsData(String? lyricsText) {
  // 1. parseLyricsTracks(lyricsText) → [(lang, [LyricLine])]
  // 2. tracks[0] → mainLang + mainLines
  // 3. 找 lang != mainLang 的第一轨 → translation
  // 4. return LyricsData(lines: mainLines, translations: translation ?? [])
}
```

JSON 格式解析:
- `jsonDecode(lyricsText)` → List<Map>
- 每轨: `track['line']` → List<Map<{start, value}>>
- `start` 单位毫秒 → 除以 1000 转为秒
- `value` → 歌词文本，空行跳过
- 每轨内部按时间排序

#### 4.13.3 parseLrcText（经典 LRC 文本）

```dart
List<LyricLine> parseLrcText(String lrc) {
  // RegExp: \[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]
  // 2 位 = 厘秒(/100), 3 位 = 毫秒(/1000)
  // 一行多时间戳 → 同一文本添加多个 LyricLine
  // [ti:]/[ar:]/[by:] 等元数据标签 → 忽略
}
```

#### 4.13.4 alignTranslations

双指针算法对齐译轨到主轨:
- `while (abs(trans[j].time - t) > abs(trans[j+1].time - t)) j++`
- `if (abs(trans[j].time - t) < 0.5) → result[i] = trans[j].text`

#### 4.13.5 mergeDuplicateTimestamps

合并 LRC 同时间轴双语行:
- 相邻时间相同 + 文本相同的重复行 → 跳过
- 相邻时间相同 + 文本不同 → 前行原文、后行译文
- 返回 `(主轨行列表, 逐行译文或null)`

#### 4.13.6 findLyricIndex（二分查找）

```dart
int findLyricIndex(List<LyricLine> list, double time) {
  // lo/hi 夹逼，mid = (lo+hi)>>1
  // list[mid].time <= time → ans=mid, lo=mid+1
  // list[mid].time > time → hi=mid-1
  // 首句之前返回 -1
}
```

### 4.14 主题系统（core/theme/）

#### 4.14.1 AppSkin 皮肤枚举

```dart
enum AppSkin {
  liquidGlass('液态玻璃', '镜面高光描边 · 内容透色'),
  deepSpace('深空科幻', '近黑蓝底 · 霓虹青发光点缀'),
  minimal('极简纯色', '暖炭纸纹实色卡片 · 强排版'),
  materialYou('莫奈取色', '动态取色跟随系统壁纸（Android 12+）'),
  sunset('落日熔金', '暖橙玫瑰底 · 低垂夕阳光球'),
  forest('林间苔原', '暖绿纸质 · 冠层微光颗粒'),
  terminal('终端磷光', '纯黑绿字 · CRT 扫描线直角'),
  albumTint('封面取色', '全局跟随当前播放封面取色 · 与播放页同源');

  final String label;
  final String desc;
}
```

8 套皮肤全部为深色系（白阶文字语义在所有皮肤下保持有效）。

SkinController:
- prefs key: `'app_skin'`
- 默认值与 `orElse`（存了未知值）: **`AppSkin.materialYou`（莫奈取色）**
- `set(AppSkin skin)`: state change + `prefs.setString(key, skin.name)`

#### 4.14.2 SurfaceLanguage 语言枚举

与 AppSkin 一一对应（8 值），作为 `SkinTokens.language` 供组件层分派**绘制实现**：
容器/弹层/舞台按 language 选各自视觉路径，主题不只是替换一组颜色。

#### 4.14.3 SkinTokens ThemeExtension

20 个语义 token（`ThemeData.extensions: [t]` 注入，读取入口 `SkinTokens.of(context)`）:

| Token | 类型 | 含义 |
|-------|------|------|
| background | Color | Scaffold/AppBar 页面背景 |
| shell | Color | 主框架背景（AmbientScaffold 打底色） |
| detailBg | Color | 详情/二级页背景。**当前零调用点**：背景统一后二级页改用 `AmbientScaffold` 无缝氛围（§6.5），`AppTheme.detailBgOf` 只剩定义没有消费者，别再往它身上加新逻辑 |
| surface | Color | 卡片/输入框 |
| divider | Color | 分隔线 |
| glassTint | Color | 玻璃面板 tint 底色 |
| tintLight | Color | 亮色薄雾 |
| borderTop | Color | 玻璃上缘受光 |
| borderBottom | Color | 玻璃下缘 |
| borderHairline | Color | 1px 均匀微亮描边 |
| shadowColor | Color | 投影 |
| textPrimary | Color | 主文本（每套皮肤各自的白阶主色） |
| textDim | Color | 次要文本 |
| textFaint | Color | 装饰图标/占位 |
| glow | Color | 发光点缀（透明=无发光） |
| blurScale | double | 模糊强度缩放 |
| blurEnabled | bool | 是否允许背景模糊 |
| highlightStrength | double | 镜面高光强度（0=改实色描边） |
| radiusScale | double | 圆角档位缩放（基准圆角 × scale，1.0=液态玻璃现状） |
| language | SurfaceLanguage | 当前皮肤语言 |

**静态皮肤对照表**（materialYou 列为 M3 动态色覆盖前的底板，运行时会被
`AppTheme.build` 用 `DynamicColorBuilder` 的 surface/surfaceContainerHigh/
surfaceContainerLowest/outline/outlineVariant/onSurfaceVariant 覆写）：

| Token | liquidGlass | deepSpace | minimal | materialYou | sunset | forest | terminal |
|-------|-------------|-----------|---------|-------------|--------|--------|----------|
| background | 0xFF001B2E | 0xFF05070E | 0xFF141210 | 0xFF14121B | 0xFF1A0E0B | 0xFF0E1410 | 0xFF000000 |
| shell | 0xFF0A1428 | 0xFF070A14 | 0xFF1A1714 | 0xFF1D1B22 | 0xFF241310 | 0xFF131A14 | 0xFF050805 |
| detailBg | 0xFF0A1A2A | 0xFF080D18 | 0xFF171412 | 0xFF1A181F | 0xFF1F110D | 0xFF101712 | 0xFF030503 |
| surface | 0xFF1A2C3A | 0xFF0D1322 | 0xFF221E1A | 0xFF282430 | 0xFF2E1A14 | 0xFF1C261D | 0xFF0A120A |
| glassTint | 0x4D13243C | 0x59101830 | 0xF0221E1A | 0x522A2536 | 0xF02E1A14 | 0xF01C261D | 0xF00A120A |
| textPrimary | 0xFFFFFFFF | 0xFFE8F4FF | 0xFFF7F3EC | 0xFFE6E1E5 | 0xFFFFF3EA | 0xFFF1F5EE | 0xFF5CFF8A |
| textDim | 0xFF888888 | 0xFF9FB4CC | 0xFFB3ABA2 | 0xFFCAC4D0 | 0xFFD8B49A | 0xFFAFC0AE | 0xFF7FE08A |
| textFaint | 0xFF444444 | 0xFF4A5A72 | 0xFF6E655C | 0xFF79747E | 0xFF8A6A55 | 0xFF6E7C6C | 0xFF3E8A4C |
| glow | 0x00000000 | 0x3800E5FF | 0x00000000 | 0x00000000 | 0x33FF7A45 | 0x00000000 | 0x4033FF66 |
| blurScale | 1.0 | 1.1 | 0 | 1.0 | 0 | 0 | 0 |
| blurEnabled | **true** | false | false | false | false | false | false |
| highlightStrength | 1.0 | 0 | 0.2 | 0 | 0.15 | 0.15 | 0 |
| radiusScale | 1.0 | 0.7 | 0.55 | 1.3 | 1.1 | 0.6 | 0.0 |

- **玻璃特性只属于液态玻璃**（钦定）：`blurEnabled` 仅 liquidGlass 为 true，其余皮肤
  面板实色、只保留 tint 色系；`radiusScale` 让圆角随皮肤性格变化（终端直角 0.0、
  莫奈大圆角 1.3），应用点如 `AppTheme.build` 输入框 `8 * t.radiusScale`。

**albumTint 为动态取色皮肤**，不设静态表：
- `SkinTokens.albumTint(dominant)`：`dominant.computeLuminance() > 0.5` 时先
  `lerp(dominant, black, 0.45)` 压暗保证白字对比；随后 `mixBlack(t)`/`mixWhite(t,alpha)`
  推导整套色板 —— background 0.42 / shell 0.55 / detailBg 0.60 / surface 0.50
  （与播放页渐变同源公式），glassTint = mixBlack(0.50) α0.30，textPrimary 纯白，
  `blurEnabled: false`、`radiusScale: 1.0`
- `albumTintFallback`：取色中/取色失败（本地歌曲、无封面）的中性深灰底板，
  避免整页等待或闪变
- 取色链路见 §4.2.6（`albumDominantColorProvider` / `lastAlbumDominantProvider` /
  `currentAlbumDominantProvider`）

**其余方法**:
- `forSkin(AppSkin skin, {Color? albumDominant})`: switch 映射表；albumTint 且
  dominant 非空 → 动态构建，否则回退 `albumTintFallback`
- `copyWith(...)`: 全字段可选覆盖（materialYou 动态色板覆写走此路径）
- `lerp(SkinTokens? other, double t)`: Color.lerp 插值 + blurScale/highlightStrength/
  radiusScale 线性插值 + blurEnabled/language 阈值切换（t<0.5 保留原值）
  → 切皮肤时整站颜色连续过渡，不闪变

#### 4.14.4 GlassTokens 尺寸常量

```dart
abstract final class GlassTokens {
  // 模糊强度
  static const blurHeavy = 28.0;
  static const blurMedium = 18.0;
  static const blurContainer = 12.0;  // 列表行禁用
  static const blurLight = 10.0;

  // 圆角
  static const radiusCard = 16.0;   // l
  static const radiusPill = 999.0;  // pill
  static const radiusSheet = 24.0;  // sheet/dialog

  // 颜色委托（随皮肤）
  static Color tint(c) → glassTint
  static Color tintLight(c) → tintLight
  static Color borderTop(c) → borderTop
  static Color borderBottom(c) → borderBottom
  static Color borderHairline(c) → borderHairline
  static Color shadow(c) → shadowColor
  static double blurScale(c) → blurScale
  static bool blurEnabled(c) → blurEnabled
  static double highlightStrength(c) → highlightStrength
  static Color glow(c) → glow
}
```

#### 4.14.5 AccentController 主题色

```dart
enum AppAccent {
  blue('流声蓝', Color(0xFF2196F3)),
  pink('樱花粉', Color(0xFFF06292)),
  purple('暮山紫', Color(0xFF9575CD)),
  green('薄荷绿', Color(0xFF26A69A)),
  orange('落日橙', Color(0xFFFF8A65)),
  night('极夜黑', Color(0xFF90A4AE));

  final String label;
  final Color color;
}
```

prefs key: `'app_accent'`，默认 blue。

- `accentExplicitProvider`: `NotifierProvider<bool>` — 用户是否显式选过主题色，true=手动选色优先于 Material You 动态取色

#### 4.14.6 BackgroundController 自定义背景

```dart
class BackgroundConfig {
  final String? path;       // null=未设置
  final double opacity;     // 默认 0.85，clamp(0,1)
  final double blur;        // 默认 8.0
}
```

| 方法 | 说明 |
|------|------|
| `setImage(sourcePath)` | 复制到 `custom_bg.png` → 持久化 path |
| `clearImage()` | 删除文件 → 清 path → state 保留 opacity/blur |
| `updateOpacity(double)` | 滑杆拖动中只改 state（不落盘） |
| `updateBlur(double)` | 同上，拖动中不写 prefs |
| `commitSliders()` | 松手时一次性持久化 opacity + blur |
| `_validateFile()` | **同步** `localFs.fileExists` 校验，缺失即清理；state.path 与待删 path 不一致时放弃（不覆盖用户刚设的新值） |

prefs keys: `'bg_image_path'`, `'bg_opacity'`, `'bg_blur'`

透明度历史迁移：早期默认 0.35 观感过暗，一次性升到 0.85——`bg_opacity_migrated_v2`
为迁移标记，仅当已存值 < 0.6（即从未手动调过）时改写为 0.85 并写标记，
用户手动调过的值永不被动。

#### 4.14.7 AmbientBackground 舞台渲染（glass.dart:746）

`AmbientScaffold`（glass.dart:706）= `ColoredBox(SkinTokens.shell)` →
`AmbientBackground` → `Theme`（appBar 透明 + elevation/scrolledUnderElevation 0）
→ `Scaffold(backgroundColor: transparent)`。整页背景只有一层，页面与其下内容同源。

| 优先级 | 渲染源 | 行为 |
|--------|--------|------|
| 1（最高） | 用户背景图 | `hasImage = bg.path != null` 时**所有皮肤**都跳过 `_AmbientStage`——图片是最高优先级背景源。`Opacity(bg.opacity)` + `ImageFiltered(blur)` + `BoxFit.cover` + `gaplessPlayback`；`localFileImage(path)` 在 web 返回 null 时自动回落到舞台 |
| 2 | `_AmbientStage`（glass.dart:801） | 按皮肤分派下列装饰舞台 |

各皮肤舞台：

| 皮肤 | 舞台实现 |
|------|----------|
| liquidGlass | **2 个** RadialGradient 光斑（340px α0.10 于 top:-140/left:-100，phase 0；300px α0.075 于 bottom:-80/left:20，phase 0.5），漂移取主色；玻璃特性只属于本皮肤，其他主题绝不复用此舞台 |
| materialYou | 1 个 360px 柔光球 α0.16（phase 0.3），跟随动态主色 |
| deepSpace | `_DeepSpaceStagePainter`：网格 + 星点闪烁 |
| minimal | `_GrainStagePainter`：纸纹颗粒（seeded Random 确定性） |
| sunset | `_SunsetStagePainter`：夕照晕染 + 地平线太阳 |
| forest | `_ForestStagePainter`：冠层微光 + 光斑 |
| terminal | `_CrtStagePainter`：CRT 扫描线 + 顶部辉光 |
| albumTint | `LinearGradient(tintLight → transparent)` 自上而下，复刻播放页上浅下深 |

装饰循环禁令：`_drift`（`MotionTokens.ambientLoop` 26s）与 `_twinkle`（`twinkle` 4s）
两个 `AnimationController` 由 `_syncLoops()` 统一控制——**`powerSaveProvider` 为 true 时
不 repeat**，并通过 `ref.listen(powerSaveProvider, (_,_) => _syncLoops())` 即时响应省电开关；
整个舞台包在 `RepaintBoundary` 内，避免每帧重绘波及页面内容。

#### 4.14.8 舞台 painter 参数（glass.dart）

| Painter | 参数 |
|---------|------|
| `_DeepSpaceStagePainter` | 网格 `strokeWidth=1`，`textFaint` α0.055，step=56px；6 颗星，`pulse = 0.55 + 0.45*sin((twinkle + i/len)*2π)`，r = 0.9 + 0.7*pulse，α = 0.45*pulse（亮度与半径同相，闪烁不突兀） |
| `_GrainStagePainter` | `Random(7)` 固定种子；α0.05，密度 `w*h/900*density`（上限 900 点），r=0.7；`density` 由皮肤传入（minimal 0.6） |
| `_SunsetStagePainter` | 上部 55% 高度晕染 α0.10；太阳圆心 (0.5w, 0.94h) 半径 0.72w，辉光 α0.55 → 0 |
| `_ForestStagePainter` | 上部 60% 冠层 α0.10；`Random(11)`，密度 `w*h/1100`（上限 700 点） |
| `_CrtStagePainter` | 3px 间隔扫描线 α0.05；顶部辉光圆心 (0.5w, -0.08h) 半径 0.9w α0.10 |
| `_DriftBox` | 利萨如轨迹 `Offset(16*sin(t*2π), 12*sin(t*4π))`——水平与垂直频率 1:2，轨迹闭合不越界 |

#### 4.14.9 面板透明度与玻璃档位（glass_quality.dart）

| 控制器 | prefs key | 取值 |
|--------|-----------|------|
| `GlassQualityController` | `'glass_quality'` | `GlassLevel { off, standard, enhanced }`（文案「关闭（最流畅）/ 标准 / 增强（更通透）」）；旧值 `high`→standard、`low`→off 一次性迁移 |
| `GlassTintOpacityController` | `'glass_tint_opacity'` | 0.2（`min`）~ 1.0，默认 1.0；`preview(v)` 拖动中只改内存，`commit()` 松手落盘 |

- `withGlassTintOpacity(ref, color)`：所有面板/弹层底色的唯一透明度入口，组件不得自带私有硬编码 alpha。
- 「面板透明度」命名沿用户钦定（按感知范围而非实现命名）：**档位只管模糊强度，透明度系数对全部 8 套皮肤生效**。
- `shouldUseBlur` / `glassBlurScale` 先读 `powerSaveProvider`：省电模式下强制不模糊、模糊缩放为 0；enhanced 档缩放 1.5×。

### 4.15 网络运行时配置（http_factory.dart）

P1-NetworkRuntime 已去除全局可变状态：`NetworkSettings` 由
serverAdapterProvider 经 `createAdapter(config, secrets, networkSettings)`
显式注入各 adapter 构造函数，Server A 的设置不影响 Server B。

```dart
abstract final class NetworkRuntime {
  // 无静态可变 settings；设置随 adapter 构造显式传入
  static void configureDio(Dio dio, NetworkSettings s) {
    // connectTimeout = s.timeoutSeconds
    // receiveTimeout = s.timeoutSeconds * 2
    // if IOHttpClientAdapter → adapter.createHttpClient = () => _createHttpClient(s)
  }

  static HttpClient _createHttpClient(NetworkSettings s) {
    // client.connectionTimeout = s.timeoutSeconds
    // proxy → client.findProxy = 'PROXY $proxy'
    // !verify → client.badCertificateCallback = (_,__,__) = true
    // hostMap → client.connectionFactory = _connectWithHosts
  }

  static Future<ConnectionTask<Socket>> _connectWithHosts(Uri uri, NetworkSettings s) {
    // mapped = hostMap[uri.host] ?? uri.host
    // HTTPS: SecureSocket.startConnect(target, port, onBadCertificate: ...)
    // HTTP: Socket.startConnect(target, port)
  }
}
```

### 4.16 ServerRepository 持久化

| 操作 | 存储位置 | 说明 |
|------|----------|------|
| loadServers/saveServers | SharedPreferences `'servers_json'` | JSON array of ServerConfig |
| loadActiveId/saveActiveId | SharedPreferences `'active_server_id'` | UUID string |
| loadSecrets/saveSecrets | FlutterSecureStorage `'server_secrets_<id>'` | JSON object of tokens |
| deleteServer | prefs + secure | 同时清理 config/secrets/activeId |
| migrateLegacySession | 全量 | 将 1.x AuthStore session 迁移到新的多服务器存储 |

### 4.17 AppDb 数据库操作

5 张表，`version: 6`，懒初始化单例（`AppDb.instance()`，web 端先 `configureDbFactory()`
切 WASM 工厂）：

| 表 | 用途 | 关键索引 |
|----|------|----------|
| scrobble_queue | Scrobble 离线队列 | `id` AUTOINCREMENT 主键 + `server_id` / `retry_count` / `next_retry_at` |
| library_snapshot | 曲库增量同步快照 | PRIMARY KEY(server_key, kind) |
| download_index | 离线下载索引 | UNIQUE `idx_download_fingerprint(fingerprint)` |
| lyrics_local | 本地导入/扫描歌词 | PRIMARY KEY(lookup_key) |
| play_history | 本地播放历史（统计 + FM 排除） | `idx_history_played(server_id, played_at)` |

**迁移约束（写在类注释里）**: 只允许 `ADD COLUMN` / `CREATE TABLE`；破坏性操作仅限可再生
缓存，且必须在迁移注释中说明影响。

| 版本 | 迁移内容 |
|------|----------|
| v2→v3 | `scrobble_queue` 加 `server_id`，并 `DELETE WHERE server_id=''`（无归属历史补发会串到新账号） |
| v3→v4 | 加 `played_at / retry_count / last_error / next_retry_at` 重试防护字段 + 建 `download_index`（旧 schema，无 payload） |
| v4→v5 | `download_index` 加 `payload`（Song 元数据快照，供本地音乐合并展示） |
| v5→v6 | 建 `play_history` |
| 兜底 | `onUpgrade` 末尾统一 `_createLyricsLocal()`（历史版本可能缺表） |

**lyrics_local lookup_key 三种语义（P0-09 分开，旧键作兜底）**:
```dart
lyricsSongKey(serverId, songId)  = 'lyrics:{serverId}:{songId}'   // 服务器歌曲
lyricsLocalKey(fingerprint)       = 'lyrics:local:{fingerprint}'  // 本地/下载文件
lyricsFallbackKey(title, artist)  = '${title.trim().toLowerCase()}|${artist...}'
```
`saveLyrics` 同时写主键与兜底键（文件 mtime 变化会让 fingerprint 变，兜底键仍可命中）；
`loadLyrics(lookupKeys)` 按优先级依次尝试。

### 4.18 共享 UI Provider

主体在 `core/theme/settings_prefs.dart`（其余按领域就近放置，见下表最后一列）：

| Provider | 类型 | 默认 | prefs key | 文件 |
|----------|------|------|-----------|------|
| `settingsIconsProvider` | `NotifierProvider<bool>` | true | `settings_icons_visible` | theme/settings_prefs.dart |
| `listEndTextProvider` | `NotifierProvider<String>` | `'- 到底啦 -'` | `list_end_text`（留空/等于默认时 remove） | theme/settings_prefs.dart |
| `powerSaveProvider` | `NotifierProvider<bool>` | false | `power_save` | theme/settings_prefs.dart |
| `floatingLyricsProvider` | `NotifierProvider<bool>` | false | `floating_lyrics`（仅 Android，开启前需悬浮窗权限） | theme/settings_prefs.dart |
| `cardDisplayProvider` | `NotifierProvider<bool>` | **false（裸排）** | `card_display` | theme/settings_prefs.dart |
| `headsetClicksProvider` | `NotifierProvider<HeadsetClicksState>` | 单击播放/暂停、双击下一首、三击上一首 | `headset_click_{single,double,triple}`（存枚举 index 字符串） | theme/settings_prefs.dart |
| `glassQualityProvider` | `NotifierProvider<GlassLevel>` | standard | `glass_quality` | shared/widgets/glass_quality.dart |
| `glassTintOpacityProvider` | `NotifierProvider<double>` | 1.0（min 0.2） | `glass_tint_opacity` | shared/widgets/glass_quality.dart |
| `coverStyleProvider` | `NotifierProvider<CoverStyle>` | — | 见文件 | features/player/cover_style.dart |
| `miniBarStyleProvider` | `NotifierProvider<MiniBarStyle>` | gradient（渐变） | 见文件 | features/player/mini_bar_style.dart |
| `miniBarOffsetProvider` | `NotifierProvider<double>` | 0 | 见文件 | features/player/mini_bar_style.dart |
| `bilingualLyricsProvider` | `NotifierProvider<bool>` | true | `lyrics_bilingual_enabled` | features/player/player_controller.dart |
| `audioEffectsProvider` | `NotifierProvider<AudioEffectsState>` | — | 见文件 | core/audio/audio_effects.dart |

`cardDisplayProvider` 是**去卡片化**方向的总开关：关闭（默认）时内容卡（设置分组 /
服务器卡 / 入口 / 歌单 / 搜索分组）全部裸排，封面与列表行直接落在页面上；
玻璃只保留给悬浮表面。

所有控制器都以 `ref.watch(sharedPrefsProvider)` **同步**读初值、`await getInstance()` 落盘
（`core/settings/prefs.dart` 是唯一读取入口，main() 在 runApp 前 override 注入）。

### 4.19 首页分区与 SWR 快照（home_providers.dart）

旧实现是纯内存 `FutureProvider`，冷启动必然整轮转圈等网络。现统一为 SWR 控制器
（零等待原则：先回放磁盘快照，再后台刷新）：

```dart
class SectionSpec<T> {
  final String cacheKey;                     // 实际 key = '$cacheKey.$serverId'（多服隔离）
  final Future<List<T>> Function(RefReader read, ServerAdapter adapter) fetch;
  final Map<String, dynamic> Function(T) encode;
  final T Function(Map<String, dynamic>) decode;
}

abstract class HomeSectionController<T> extends Notifier<AsyncValue<List<T>>> {
  SectionSpec<T> get spec;
}
typedef HomeSectionProvider<T> =
    NotifierProvider<HomeSectionController<T>, AsyncValue<List<T>>>;
```

`build()` 时序（四条硬性约束）：

1. `watch(activeServerIdProvider)` + `watch(serverAdapterProvider)` —— 切服或网络设置变更
   整体重建（对齐旧 FutureProvider 行为）
2. 同服重建优先保留内存；首次同步读 `sharedPrefsProvider.getString('$cacheKey.$serverId')`，
   有效快照（包括空数组）直接 `AsyncValue.data`，缺失／损坏才进 loading
3. 首取推迟到 microtask 调用 `refresh()`，并检查代际有效性，避免 build 期改 state
4. `_fetch` 失败且有旧数据时保留原态，仅无缓存才进 error；重建／切服／销毁后的旧请求
   成功和失败均丢弃；同内容不重复通知，写盘失败留待下次刷新补写

五个分区（均 `home.` 前缀）：`home.latestAlbums` / `home.recentlyPlayed` /
`home.mostPlayed` / `home.randomAlbums` / `home.dailySongs`。
随机类分区依赖 `randomSeedProvider`（`makeSeed()` = 微秒时间戳 + 随机整数），
下拉刷新时换 seed 触发重取。

其余取数 provider（同一文件）：`playlistsProvider`、`albumSongsProvider`、
`playlistSongsProvider`、`playlistCoverIdsProvider`、`songTotalProvider`、
`likedSongsProvider`、`librarySongsProvider`、`libraryAlbumsProvider`、
`libraryAlbumsPagedProvider`（分页态 `AlbumPagedState`）、`artistsProvider`、
`albumArtistsProvider`、`genresProvider`、`radioStationsProvider`、
`genreSongsProvider`、`artistAlbumsProvider`、`artistSongsProvider`
（分页态 `ArtistSongsState` + `ArtistSongsController`）。

### 4.20 播放历史与听歌统计（play_history.dart / stats_providers.dart）

`PlayHistory`（`abstract final class`，SQLite `play_history` 表）：

| 成员 | 说明 |
|------|------|
| `record({serverId, song, durationMs})` | 写入一行，**含歌名/歌手/专辑快照**（服务器删曲后统计仍可读） |
| `recentSongIds(serverId, {days=7})` | 近 N 天听过的歌曲 id，供私人 FM 排除 |
| `summary(serverId)` → `StatsSummary` | `totalPlays` / `totalDurationMs` / `uniqueSongs` / `plays7d` / `plays30d` |
| `topSongs(serverId, limit=20)` | `GROUP BY song_id`，`ORDER BY c DESC, MAX(played_at) DESC` |
| `topArtists(serverId, limit=10)` | 同口径按歌手聚合 |

`PlayHistoryService`（`playHistoryServiceProvider`）监听 `positionStream`，
每首歌每次播放只记一行：

- **门槛** `_threshold(dur)` = `dur >= 40s ? 20s : dur * 0.5`（短曲按比例，长曲固定 20s）
- `if (!_read(playerReadyProvider)) return;` —— 冷启动恢复（RESTORING）期间的 position
  事件不是真实播放，不能记成历史
- `song.id` 变化时重置 `_recorded`；dur 未知（null/≤0）时不判定
- 行数上限 `_maxRows = 20000`，每 100 次插入触发一次裁剪（保留最近 N 行）

统计页 provider 全部 `watch(activeServerIdProvider)`，切服自动重取：
`statsSummaryProvider` / `statsTopSongsProvider` / `statsTopArtistsProvider`
（serverId 为空直接返回 null/空列表，不查库）。

### 4.21 私人 FM（fm_providers.dart）

```dart
class FmController {
  Future<bool> start()          // 抽一批替换队列并立即播放
  Future<void> refillIfNeeded() // 当前曲之后剩余 ≤3 首时补一批到队尾
  Future<void> skipDislike()    // playNext + 把当前曲移出队列（不再回来）
}
final fmActiveProvider / fmLoadingProvider / fmRefillServiceProvider
```

- `_batchSize = 20`；`_draw()` 两轮随机抽：`fetchSongs(SongQuery(sort: random, limit: 50))`，
  第一轮**严格排除**近 7 天听过（`PlayHistory.recentSongIds`），第二轮放宽为只去重
  ——曲库很小时保证仍有歌可播；排除当前曲、已在队列、批内重复
- **队列身份签名** `_queueSignature()` = `'长度|首 id|尾 id|当前曲 id'`。`List` 是引用相等，
  跨 async 间隙比对必须用字符串形态；抽歌是网络请求，期间切服/换队列会使本次会话作废，
  旧批量若照常 `replaceQueue` 会把旧服务器的歌倒进新服务器队列 → 直接返回 false
- `start()` 先守卫 `fmLoadingProvider`（防重复点击），成功后 `replaceQueue(batch)` →
  **重新置 `fmActiveProvider = true`**（`replaceQueue` 按曲库整表播放语义会清除 FM 激活态）
  → `play(batch.first)`
- `refillIfNeeded()` 用 `_refilling` 布尔守卫防并发切歌时补两批；追加前二次校验
  `fmActive` / serverId / queueSignature

### 4.22 搜索历史与歌曲排序

**搜索历史**（`features/search/search_screen.dart`）：

```dart
class SearchHistoryController extends Notifier<List<String>>  // key 'search.history.v1'，上限 15
final searchHistoryProvider / searchQueryProvider / searchResultProvider
```

- `add(query)` 去重置顶、超 15 条截断；`remove(query)` 单条删除；`clear()` 清空
  （空列表时 `prefs.remove` 而非写 `'[]'`）
- 录入时机：结果点击与键盘提交（`_submit`）自动记入，不要求用户点搜索按钮
- 搜索页空态即历史列表；`searchResultProvider` 是 `autoDispose`，退出即释放

**歌曲排序**（`core/library/song_sorting.dart` + `SongSortController`）：

```dart
class SongSortPref { final SongSort field; final bool ascending; }
const kSortableSongFields = [recentlyAdded, title, artist, album, duration,
                             rating, mostPlayed, recentlyPlayed];  // random 不进菜单
List<Song> sortSongs(List<Song> songs, SongSortPref? pref)
final songSortPrefProvider = NotifierProvider<SongSortController, SongSortPref?>
```

- prefs key `'songList.sort.v1'`，值 `'${field.name}:${asc|desc}'`；`null` = 各列表保持
  原始顺序（歌单的服务端编排顺序等）；`set(null)` 直接 `remove` 该 key
- 读取走 `Future.microtask`（`Notifier.build()` 期同步改 state 会被 Riverpod 拒绝），
  且校验字段在 `kSortableSongFields` 内，未知值忽略
- **全量快照排序**：曲库/歌单/喜欢/流派/本地的取数都是完整列表，本地排序与服务端排序等价
- 中文按**拼音序**（与艺人索引同一策略）：`_pinyinKey` 用
  `PinyinHelper.getPinyin(t, separator: '')` —— separator 必须为空串，传空格会把英文
  逐字拆开（`"Always"` → `"a l w"`）导致键序失真
- 稳定性：非主键的次级键恒为标题拼音升序；主键文本在 O(n log n) 比较外**预计算成 Map**，
  不在比较器里算拼音

---

## 五、功能模块详解（完整版）

### 5.1 认证模块（features/auth/）

#### 5.1.1 LoginScreen（features/auth/login_screen.dart）

服务器类型**不在本页选择**：`LoginScreen({required ServerType serverType})` 由
`ServerSelectScreen` 的后端卡片或 `ServersScreen` 的类型弹层 push 进入。

- **页面骨架**：`Scaffold` → `AmbientBackground` → `SafeArea` → `Form` →
  `ListView(padding: horizontal 24)`
- **头部**：36×36 圆角 logo（`_TypeIcon`，r8）+ 「登录 {displayName}」22 bold +
  `{tagline}` 14 dim
- **分组「服务器」**（`_GroupLabel`：14 w600 dim + `letterSpacing 1`）→
  `GlassCard(padding: 16)`：
  - 地址框（`Expanded(flex: 5)`，`keyboardType: url`，hint `type.urlHint`，空值报
    「请输入服务器地址」）+ 独立端口框（`flex: 2`，`number`，hint「选填」，
    非空时校验 1–65535）——**地址与端口拆成两框**，无需用户自己处理冒号
  - 路径框（hint `type.pathHint`：fnOS 固定 `/music`，其余「选填」）
  - 「启用 HTTPS」14 dim + `Switch`（**默认 HTTP**，局域网直连无需开启）
- **分组「登录信息」**→ `GlassCard(padding: 16)`：用户名（`autofillHints: username`，
  空值报错）、密码（`obscureText` + `visibility_outlined` 明暗切换后缀，
  `onFieldSubmitted` 直接提交）、`FilledButton` 全宽（`vertical: 16` padding、
  圆角 12、19 bold）；提交中 `onPressed: null` 且文案换成 22×22
  `CircularProgressIndicator(strokeWidth: 2.4)`，按钮宽度不跳
- **地址归一化**（`_submit`，与 `EditServerScreen` 同款）：粘贴完整 URL 时自动识别
  `https://`/`http://` 前缀并**反向同步 HTTPS 开关**；域名框里带出的子路径转移到路径位
  （路径框已有值时以路径框为准）；端口仅在域名框未自带 `:` 时拼接；头尾斜杠全部剥掉。
  最终 URL 为 `scheme://host[:port][/path]`，`AuthController.login` 内再走一次
  `normalizeServerUrl`（auth_controller.dart:256）兜底
- **结果**：成功 `popUntil((r) => r.isFirst)` 回壳层；失败 toast
  「登录失败：{appUserMessage(error)}」（§15.3）

#### 5.1.2 ServerSelectScreen（features/auth/server_select_screen.dart）

冷启动首屏（未登录时的入口页），`Scaffold` → `AmbientBackground` → `SafeArea` →
`ListView(padding: 24,0,24,32)`：

- **品牌头**：80×80 `assets/app/logo.png` + 「选择你的音乐服务」22 bold +
  「支持 Navidrome / Subsonic / Jellyfin / Emby 等」14 dim
- **已保存的服务器**（仅 `auth.servers.isNotEmpty` 时出现）：`_SavedServerTile`
  （`GlassCard(h16 v10)`）= 24 logo + 名称 16 + `{url} · {username}` 12 faint；
  激活服显示「当前」徽标（primary .15 底、12 w600、r12）且 `onTap: null`，
  其余服整卡可点 → `switchServer(id)`，右侧 `chevron_right` 20
- 该区块右下角 `TextButton.icon`「管理服务器」（`settings` 16，14 dim）→
  push `ServersScreen`（§5.1.4）
- **添加新服务器**：`ServerType.values` 全量渲染 `_BackendTypeCard`（28 logo +
  displayName 16 + tagline 12 faint + `chevron_right` 22）。`implemented` 为 false 时
  整卡 `Opacity(.45)` + 「即将推出」徽标，点击只 toast「{name} 适配器开发中，敬请期待」——
  当前 7 个后端 `implemented` 恒为 true，置灰分支走不到（同 §5.1.4 遗留）
- 可点卡片 → `fadeRoute(LoginScreen(serverType: type))`

#### 5.1.3 ServerDetailScreen（features/home/server_detail_screen.dart）

资料库页顶部的服务器卡片点进来（`music_library_screen.dart:86`，`fadeRoute`）。
`AmbientScaffold` + `AppBar(title: 激活服 displayName ?? '服务器')`；
`activeConfig == null` 时只有一行居中 faint「未连接服务器」，否则
`ListView(padding: 16)` 四段：

- **_Header**：48 `AppRadius.m` 圆底（primary .15）+ `type.fallbackIcon` 28 +
  类型名 20 bold + URL 12 faint（均单行省略）+ `TextButton`「刷新」
  → `invalidate` 五个 provider（`songTotal` / `playlists` / `librarySongs` /
  `libraryAlbums` / `artists`）
- **_StatsCard**（`GlassContainer(h16 v4)`，行高 14 + `Divider(height: 1,
  SkinTokens.divider)`）：歌曲/专辑/歌手/歌单四行，值取 provider 的 `.length`；
  `null` 时歌曲显示 `0`、专辑与歌单显示 `…`（加载中），歌手显示 `—`
  （`artistsProvider` 的 null 同时涵盖「后端无艺人表」与「未取到」两种情况）
- **用户设置**：`_UserSettingsCard` —— 用户名（只读值）+ 管理服务器
  （`chevron_right` 20 → `ServersScreen`）
- **资料库管理**：`_ManageCard` —— 别名（只读值，改名走 §5.1.5）、连接线路
  （`valueCompact`）、重新同步资料库（invalidate 四个 provider + toast
  「已开始重新同步」）、删除资料库（`AppTheme.heartRed` 值色 + `glassDialog`
  二次确认 → `removeServer(id)`）
- 通用 `_row`：label 16（不可点时 `textPrimary`、可点时 `textDim`）+ `Spacer` +
  `Flexible` 值 15 单行省略 + 可选 trailing；整行 `InkWell(borderRadius:
  AppRadius.s)`。可选元素用 Dart 3 的 null-aware element 语法 `[?trailing]`

#### 5.1.4 ServersScreen（features/settings/servers_screen.dart）

服务器管理页，`Scaffold` + `ListView(padding: 12)`（**不是** AmbientScaffold，
也无 FAB）：

- **三个入口**：服务器选择页右上、`ServerDetailScreen` 的「服务器管理」、
  设置 → 系统 → 服务器管理（均 `fadeRoute`）
- **添加服务器**：首行 `GlassContainer(onTap:)`（32 圆角底 `primary .15` +
  `Icons.add` 20 + 「添加服务器」16 + `chevron_right` 20）→ `glassBottomSheet`
  列出 `ServerType.values`（`_ServerIcon` + displayName），选中 pop 后
  push `LoginScreen(serverType: type)`。`implemented`/`hasLogoAsset` 当前对
  7 个后端恒为 true，「即将推出」置灰分支实际走不到（遗留待清理）
- **空态**：`auth.servers.isEmpty` 时只有一行居中 16 号 faint「暂无已保存的服务器」
  （未走 `glassEmptyState`），无图标
- **_ServerCard**（`GlassCard(padding: 16)`）：32 logo（`assets/app/{type.name}.png`，
  r8）+ 名称 16 + URL 14 faint + `当前连接` 徽标（primary .15 底、12 w600、r12，
  仅激活服出现）；次行 `person_outline` 14 + username 12 faint
- **五个动作**：非激活服额外出现 `TextButton.icon` 切换（`swap_horiz` 16，
  `minimumSize: Size.zero` + `shrinkWrap`）；`more_vert` 20 菜单为
  切换到此服务器 / 编辑（`edit_outlined` → `EditServerScreen(config:)`，见 §5.1.5）/
  检测连接（`wifi_find`）/ 删除（`delete_outline` + `AppTheme.heartRed`）
- **检测连接**：`authController.validateServer(id)` → toast「连接正常」/
  「连接失败：会话无效」；抛错走 `appUserMessage(e)`（§15.3）。
  该检测**为目标服务器临时 createAdapter**，不复用当前激活服的 adapter
- **删除**：`glassDialog` 二次确认（提示会清除该服务器本地会话数据，确认键
  `heartRed`）→ `removeServer(id)`
- 数据源是 `ref.watch(authControllerProvider)`，增删切服后卡片自动重排

#### 5.1.5 EditServerScreen（features/auth/edit_server_screen.dart）

`Scaffold` + `AppBar('编辑服务器')` + `Form` + `ListView(padding: 12)`，
三段 `GlassCard(padding: 16)`，表单字段与登录页一致（地址/端口/路径/HTTPS/用户名/密码）
外加一个备注名：

- **预填**：备注名与用户名直接取 `ServerConfig`；`Uri.tryParse(config.serverUrl)`
  拿到 scheme+authority 时**反向拆解**出 HTTPS 开关、host、port、子路径（与登录页
  拼接逻辑互逆），解析失败则整串塞进地址框；密码由
  `authController.storedPassword(id)` **异步回填**（仅当输入框仍为空且 `mounted`），
  读取失败留空由用户重输
- **备注名可留空**：hint「留空保持「{displayName}」不变」——空值即不改名
- **保存**：`editServer(id:, serverUrl:, username:, password:, name:)`。控制层先做
  `normalizeServerUrl`，再比对「地址/用户名/密码」是否真变化：
  **有变化才用新凭证完整走一次 `signIn`**（成功后把新鲜 secrets 连明文密码一并落库），
  网络失败直接抛出 → UI toast「保存失败：{appUserMessage}」，**原配置一字不改**；
  只改备注名则跳过网络直接保存。提交中按钮 `onPressed: null` + 22×22 spinner
- **生效范围**：编辑当前激活服务器时 `state` 变更会重建 adapter，新地址/凭证即刻生效；
  非激活服只更新列表与（凭证变化时的）secrets，`activeSecrets` 保持不动
- 成功后 toast「已保存」并 pop


### 5.2 首页（features/home/home_screen.dart）

#### 5.2.1 页面结构

`HomeScreen` 是 `ConsumerWidget`，`Scaffold(backgroundColor: Colors.transparent)` 嵌在壳层
`AmbientBackground` 之内（自定义背景图/皮肤舞台透出），body 为 `RefreshIndicator` +
`CustomScrollView`（`AlwaysScrollableScrollPhysics`），sliver 顺序固定：

| 顺序 | 内容 | 实现 |
|------|------|------|
| 1 | 搜索入口条 | `SearchEntryBar(onTap: → fadeRoute(SearchScreen()))`（`shared/widgets/search_entry.dart`） |
| 2 | 私人 FM 入口 | `_FmEntry`：紧凑图标与标题，整行点击进 `FmScreen` |
| 3 | 最新专辑 | `_Section('最新专辑', _AlbumRow(latestAlbumsProvider))` |
| 4 | 每日推荐 | `_SongListSection(withDate: true)` |
| 5 | 最近／最常播放 | `_ListeningHistory` 标签切换，`_SongListSection(horizontalCovers: true)` 横向封面 |
| 6 | 随机专辑 | `_Section('随机专辑', _AlbumRow(randomAlbumsProvider))` |
| 7 | 收尾留白 | `SizedBox(height: AppSpacing.huge + MediaQuery.paddingOf(context).bottom)` |

- **无欢迎词**：1.x 的 `_Greeting` 已删除，搜索入口条与资料库页顶部平齐。
- `SearchEntryBar` 是装饰性入口（不承载输入），填充色经 `withGlassTintOpacity` +
  `imageBgAwareTint`，随「面板透明度」与自定义背景图联动；不负责导航，避免 shared 反依赖 features。

#### 5.2.2 分区壳与卡片

- `_Section(title, child, trailing?)`：分区标题 + 可选右侧动作位（「查看更多」）。
- `_AlbumRow(provider)` 与 `_SongCoverRow` 共用 `_HomeCoverCard`（封面 + 双行名称 + 歌手）；
  专辑点击进 `SongListScreen(rateTargetId: album.id, rating: album.rating)`，歌曲点击播放、长按操作。
  最近／最常各自用 `PageStorageKey(provider)` 保存横向滚动位置，列表按需构建。
- `_SongListSection(title, provider, withDate)`：`HomeSectionProvider<Song>` 三态
  （loading 180px 转圈 / error `errorRetryBox` + `ref.invalidate` / empty `glassEmptyState`），
  每日推荐有数据时最多展示 3 行 `_SongCardRow`，最近／最常展示 `_SongCoverRow`；trailing「查看更多」→
  `SongListScreen(songs: list, coverAlbumId: list.first.albumId, date: 每日推荐传今日)`。
- `_SongCardRow`：52 封面 + 标题/副标题；点击 `replaceQueue(queue)` +
  `play(song)`，`autoOpenPlayerProvider` 为真时 `openFullScreenPlayer`；长按
  `showSongActionSheet`（与详情页 `SongRow` 行为一致）。
- **去卡片化双形态**：卡片模式下 3 行包进 `GlassContainer`，默认裸排（`cardDisplayProvider`
  为 false）时直接 `Column` 排布。

#### 5.2.3 数据源与下拉刷新

分区数据源是 `SectionSpec` + `HomeSectionController` 的 SWR 快照（见 §4.19：进入即同步读盘
回放、不转圈，后台重取）。`_refresh(ref)` 先 `randomSeedProvider = makeSeed()`，再
并行等待五个分区 notifier 的 `refresh()`：`latestAlbumsProvider` / `recentlyPlayedSongsProvider` /
`mostPlayedSongsProvider` / `randomAlbumsProvider` / `dailySongsProvider`。同代在途请求复用，刷新保留
当前数据（含空快照），代际守卫丢弃旧请求成功／失败；内容未变时不通知、不重复写盘。

### 5.3 资料库（features/home/music_library_screen.dart）

#### 5.3.1 页面结构

`MusicLibraryScreen`（`ConsumerWidget`）：`Scaffold(backgroundColor: Colors.transparent)` +
`ListView(padding: top 4 / bottom 96 + 安全区)`，子项依次为
`SearchEntryBar` → `_ServerPanel(total: songTotalProvider 的 value ?? 0)` → `SizedBox(20)` →
`_PlaylistSection`。与首页共用同一只读搜索入口与底部留白口径。

#### 5.3.2 服务器面板（_ServerPanel，裸排）

- 折叠态是 `_ServerPanelState` 的本地 `bool _expanded = true`（**不是**全局 StateProvider）。
- 头部：`type.hasLogoAsset` → `Image.asset(type.iconAsset, 44×44, AppRadius.m 圆角)`，
  否则主色 18% 圆角底 + `type.fallbackIcon`；标题 `type?.displayName ?? '未连接服务器'`（20px bold）；
  副行 `Icons.alt_route` + `config?.name ?? '点击设置添加服务器'` + `Icons.music_note` + 歌曲总数。
  点击整行 → `ServerDetailScreen`（`config == null` 时 onTap 为 null）。
- `Divider(height: 1, color: SkinTokens.of(context).divider)`。
- 入口网格折叠：`ClipRect` + `AnimatedAlign(heightFactor: _expanded ? 1 : 0, 260ms,
  Curves.easeOutCubic)`，底部箭头随状态翻转。

#### 5.3.3 入口网格（_EntryGrid）

首行恒在，第二行为「按后端能力自动显隐」的扩展入口
（`xxxProvider.valueOrNull != null` 才渲染，后端不支持即入口消失）：

| 入口 | 打开方式 | 数据源 / 页面 |
|------|----------|----------------|
| 歌曲 | `_openSongs('歌曲', librarySongsProvider)` | `SongListScreen(songsProvider:)` |
| 我喜欢的 | `_openSongs('我喜欢的', likedSongsProvider)` | `SongListScreen(songsProvider:)` |
| 本地音乐 | `_openSongs('本地音乐', localSongsProvider, onRefresh: forceLocalRescan)` | `SongListScreen(songsProvider: + 下拉重扫)` |
| 专辑 | `_openAlbums()` | `AlbumListPage(title: '专辑', paged: libraryAlbumsPagedProvider)` |
| 听歌统计 | push `StatsScreen` | 见 §5.11 |
| 专辑艺术家 | `_openArtists('专辑艺术家', albumArtistsProvider, openAlbums: true)` | `ArtistListPage` → 该歌手专辑 |
| 歌手 | `_openArtists('歌手', artistsProvider)` | `ArtistListPage` → 歌手歌曲 |
| 流派 | push `GenrePage` | 见 §5.6 |
| 电台 | push `RadioPage` | 见 §5.6 |

- `_Entry`：主色图标(24) + 12px 标签；卡片模式用 `GlassCard`，默认裸排用 `InkWell` +
  `AppRadius.m` 圆角点击区（`Expanded` 等分一行）。

#### 5.3.4 歌单区（_PlaylistSection）

- `playlistsProvider`（SWR 快照，见 §4.19）；`playlistCoverIdsProvider` 取歌单前 4 首歌的
  albumId 拼成 2×2 网格封面。
- **我的 / 全部歌单** 切换（本地 `bool _all`）：
  - `hasOwnerInfo = all.any((p) => p.owner?.isNotEmpty == true)`；无 owner 信息或 `username == null`
    时 `mine = all`。
  - 否则按 `owner.toLowerCase() == username.toLowerCase()` 过滤；**过滤结果为空时回退到 all**
    （后端只返回显示名等场景，避免整个歌单区看似消失）。
  - `canToggle = all.isNotEmpty`（只要有歌单就允许切换，即使两份列表一致）。
- `more_horiz` 菜单：`create` → `glassDialog(新建歌单, _CreatePlaylistForm)`；`sync` →
  `ref.invalidate(playlistsProvider)`。重命名走 `_RenamePlaylistForm`。
- 歌单行 `_PlaylistRow`：拼贴封面 + 名称 + 歌曲数 + 播放/入队；点击 →
  `SongListScreen(playlistId: id)`（见 §5.7）。

#### 5.3.5 AlbumListPage（专辑列表页）

```dart
class AlbumListPage extends ConsumerStatefulWidget {
  const AlbumListPage({
    super.key,
    required this.title,
    this.provider,   // 一次性全量（艺人专辑），接受 ProviderBase<AsyncValue<List<Album>>>
    this.paged,      // 滚动加载分页（资料库专辑入口）
                     // AutoDisposeNotifierProvider<LibraryAlbumsController, AlbumPagedState>
  }) : assert(provider != null || paged != null,
              'AlbumListPage 需要 provider 或 paged 之一作为数据源');
}
```

- 布局：`AmbientScaffold(appBar: AppBar(title), bottomNavigationBar: MiniPlayer(), body: ...)`，
  固定顶栏 + 无缝背景（详见 §6.5）；`body` 为 `Column(ListSearchBar, 内容区)`。
- 内容状态：分页源 `AlbumPagedState`（`loading` 转圈 / `error` → `errorRetryBox(retry)` /
  空 → `glassEmptyState('暂无专辑')`）；有数据时外层 `ScrollBottomLoader(onBottom: loadMore)`，
  网格尾部挂 `LoadMoreRow(onLoadMore, loading, failed, noMore)`。
- 过滤：本地 `_search` 输入即时生效，`_filter` 按「专辑名 or 歌手」小写包含匹配，不重新请求。
- 4 列网格：`padding=12 / spacing=10 / mainAxisSpacing=14`，
  `cover = (屏宽 - 12*2 - 10*3) / 4`，`childAspectRatio: cover / (cover + 40)`（正方形封面 + 两行文字）。
- `AlbumCard`（`shared/widgets/album_card.dart`）：`PressableScale` 包裹 → `CoverArt(radius:10)`
  + 名称(14/w500) + 歌手(12/dim)；右上角 `SongCountBadge(count)`
  （`scheme.primary` 底 + `onPrimary` 文字，高 18、minWidth 18、圆角 9，`>99` 显示 `99+`）——
  **角标随皮肤取色，不硬编码红色**（早期 `0xFFFA2C19` 已废弃）。
- 点击进入专辑详情：`SongListScreen(rateTargetId: album.id, songsProvider:
  albumSongsProvider(album.id), title, subtitle: '${year} ${artist}', rating)`。

#### 5.3.6 ListSearchBar（二级列表页共用过滤栏）

- `music_library_screen.dart` 内的 `ListSearchBar(controller, onChanged, hint = '搜索专辑/歌手')`，
  专辑 / 歌手等二级页共用；作用是**过滤当前列表**，不是全局搜索。
- 高 40、圆角 20，填充 `withGlassTintOpacity(imageBgAwareTint(surfaceOf))`（随面板透明度与
  自定义背景图联动）；`TextField(expands: true, maxLines: null,
  textAlignVertical: center)` —— 用 expands 撑满固定高度才能真正垂直居中，
  `isCollapsed` 方案受 CJK 字体度量影响会整体偏高。

### 5.4 详情页（features/home/detail_screen.dart）

#### 5.4.1 SongListScreen 构造函数（四源合一：直给 / 分页 / 异步 / 歌单）

```dart
class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({
    super.key,
    required this.title,
    this.songs,                 // 直接给定（每日推荐「查看更多」）
    this.pagedSongsProvider,    // 分页加载（艺人歌曲，含「加载更多」）
    this.songsProvider,         // 一次性异步加载（资料库歌曲/我喜欢的/本地音乐/流派）
    this.playlistId,            // 异步加载（我的歌单 /api/playlist/{id}/tracks）
    this.coverAlbumId,          // 封面（回退到 first.albumId；艺人页传 artistId）
    this.date,                  // 头部副标题覆盖（每日推荐传今日）
    this.subtitle,              // 副标题覆盖（本地音乐为占用空间文本）
    this.rating = 0,
    this.rateTargetId,          // 非 null 且后端支持评分时显示五星评分（专辑）
    this.onRefresh,             // 非 null 才启用下拉刷新（本地音乐），见 §5.9
  }) : assert(
         songs != null ||
             pagedSongsProvider != null ||
             songsProvider != null ||
             playlistId != null,
         '必须提供 songs / pagedSongsProvider / songsProvider / playlistId 之一',
       );
}
```

- 数据源优先级（从高到低）：`pagedSongsProvider` > `songs` > `songsProvider` >
  `playlistId`；`assert` 把「四选一」提到编译期，避免误传空构造
- `songsProvider` 类型为 `ProviderBase<AsyncValue<List<Song>>>?`（而非
  `FutureProvider`），因此普通与 autoDispose、含已取参的 family 都能传入
- 分页源复用 `artistSongsProvider`（ArtistSongsController 累计 limit 策略），
  列表尾部挂 `LoadMoreRow`，空态/失败重试独立于 `sliverAsyncGuard`

#### 5.4.2 Build 数据获取与排序/过滤记忆化

```dart
final paged = widget.pagedSongsProvider == null
    ? null
    : ref.watch(widget.pagedSongsProvider!);
final async = paged != null
    ? null
    : widget.songs != null
        ? AsyncValue.data(widget.songs!)
        : widget.songsProvider != null
            ? ref.watch(widget.songsProvider!)
            : ref.watch(playlistSongsProvider(widget.playlistId!));

final all = paged?.songs ?? async?.value ?? const <Song>[];
final sorted = _sortedOf(all, ref.watch(songSortPrefProvider)); // 全表拼音排序
final songs = _filteredOf(sorted, _search);                     // 关键词过滤

final showFileSize = widget.songsProvider != null; // 资料库歌曲入口显示占用空间
final totalBytes = all.fold<int>(0, (sum, s) => sum + s.size);
final subtitle = widget.subtitle ?? (all.isEmpty
    ? ''
    : showFileSize && totalBytes > 0
        ? '共计占用 ${QualityBadge.fileSizeLabel(totalBytes)} 空间'
        : '共 ${all.length} 首歌曲');
final coverAlbumId = widget.coverAlbumId ?? (all.isEmpty ? null : all.first.albumId);
```

- 排序/过滤结果记忆化（`_sortedCache` / `_filteredCache`，以 `identical()`
  比对列表实例 + 偏好/关键词）：`build` 每帧都会走到，缓存命中即跳过；
  数千首时避免每次输入重复 O(n log n) 全表拼音排序
- `_toggleFilter()` 收起时一并清空关键词，避免「看不见但仍在过滤」
- 页面整体为 `AmbientScaffold(appBar: _detailAppBar(...),
  bottomNavigationBar: selectMode ? _BatchBar(...) : const MiniPlayer(),
  body: _bodyWithRefresh(CustomScrollView(slivers: [_Header, _ListTop,
  ..._listSlivers])))`；`onRefresh != null` 时才挂 `RefreshIndicator` 并把
  physics 提到 `AlwaysScrollableScrollPhysics`（见 §6.5）

#### 5.4.3 _Header 静态头部

- `Padding(16, 16, 16, 24)` + Row；封面 **90×90、圆角 12**（`ClipRRect`），
  取图走 `adapter.coverImage(coverAlbumId, size: 300)`（300 档与列表同 URL
  共享磁盘缓存）+ `CachedNetworkImage(cacheManager: CoverCacheManager(),
  memCacheWidth: 180, httpHeaders: 透传)`
- 加载失败 → `_CoverPlaceholder`：90×90 `SkinTokens.surface` 圆角 12 +
  `Icons.album` 36，不裂图不留白
- 标题 19 bold（maxLines 2）+ 副标题 14 dim；`StarRating` 仅在
  `rating != null && onRating != null` 时出现（专辑页）

#### 5.4.4 _ListTop 列表顶部（渐变面板 + 可收纳筛选）

- `panel = Colors.white.withValues(alpha: .08)`、`panelFaint = .03`、
  `panelBorder = withGlassTintOpacity(white .12)`；纵向 LinearGradient
  两端都过 `withGlassTintOpacity`（有背景图时随图调暗），
  `BorderRadius.vertical(top: GlassTokens.radiusCard)` + 0.5 顶描边
  → 与下方列表形成一张「卡片起始」的观感，而非独立卡片
- Column[_PlayAllBar, `AnimatedSize`(200ms, easeOutCubic, topCenter)]：
  展开时插入 Divider + `_FilterBar`，收起时高度归零，把 44dp 纵向空间
  还给歌曲列表
- `_PlayAllBar`：height 48；36×36 圆底（`primary.withValues(alpha:.18)`）
  + `Icons.play_circle_fill` 28 → 「全部播放」19 bold + 「（共N首）」14 dim
  （`FittedBox(scaleDown)` 防溢出），尾部三个 compact IconButton 22
  `AppTheme.actionBlue`：`shuffle` 随机播放 / `playlist_add` 加入队列 /
  `play_circle_outline` 顺序播放
- 三个动作：`_playAll` = replaceQueue + play(first)；`_playShuffle` =
  replaceQueue + `playModeProvider = PlayMode.shuffle` + 按
  `DateTime.now().millisecond % length` 选起点；`_enqueue` = addToQueue +
  toast「已将 N 首歌曲加入队列」
- `_FilterBar`：height **44**（不是独立圆角框，直接坐在渐变面板上），
  `Icons.search` 20 faint + `autofocus` TextField，hint「搜索歌曲/专辑/歌手」，
  三处 `InputBorder.none` + `filled: false` + `isDense: true`
- 过滤 `_filterSongs`：title/artist/album 小写 contains；入口在顶栏
  `Icons.search`，tooltip 随态切换「筛选歌曲 / 收起筛选」，展开时图标染 primary

#### 5.4.5 _songSlivers 与 _listSlivers 列表分区块

```dart
// 数据态裸排行（去卡片化：行内不再套 GlassCard）
if (songs.isEmpty) return [SliverToBoxAdapter(child: noMatchBox())]; // 筛选无匹配
return [
  SliverList.builder(
    itemCount: songs.length,
    itemBuilder: (context, index) => FadeSlideIn(
      index: index,                    // 级联入场，见 §6.8
      child: SongRow(
        song: songs[index],
        index: index,
        songs: songs,                  // 播放队列 = 当前筛选结果
        showFileSize: showFileSize,
        selected: selectMode ? selected.contains(song.id) : null,
        onToggleSelect: selectMode ? () => onToggle(song) : null,
        playlistId: playlistId,        // 非 null 时行菜单出现「从歌单移除」
      ),
    ),
  ),
  SliverToBoxAdapter(child: ListEndMark(songs: songs)), // 「到底啦」+ 总数
];
```

- `_listSlivers` 按数据源分两支：
  - **分页源**：非空 → 行 + `LoadMoreRow(loading/failed/noMore/onLoadMore)`
    + `SizedBox(height: 64)`；空 → loading 转圈（Padding 48）/ `errorRetryBox`
    （`controller.retry`）/ `glassEmptyState('暂无歌曲')`
  - **非分页源**：`sliverAsyncGuard<Song>`（错误重试 invalidate 数据源，
    空态文案 `playlistId != null ? '歌单暂无歌曲' : '${title}暂无歌曲'`）
- 分页源额外包一层 `ScrollBottomLoader(onBottom: controller.loadMore)`，
  `LoadMoreRow` 只做状态展示、不负责触发
- `_bodyWithRefresh`：`RefreshIndicator.onRefresh` 先 `await onRefresh()`
  再 `ref.invalidate(songsProvider)`

#### 5.4.6 SongRow 歌曲行（裸排，去卡片化）

```dart
InkWell(
  onTap: selecting ? onToggleSelect : () {
    onResultTap?.call();                    // 搜索页借它记历史，见 §5.8
    if (identical(songs, const [])) return; // 纯展示行不可播
    actions.replaceQueue(songs); actions.play(song);
    if (ref.read(autoOpenPlayerProvider)) openFullScreenPlayer(context);
  },
  onLongPress: () => showSongActionSheet(context, song, playlistId: playlistId),
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      SizedBox(width: 24, child: 序号(indexGreen 16 bold) | 勾选 Icon 22),
      SizedBox(width: 10),
      Expanded(child: Column([
        Text(song.title, 19 bold letterSpacing .5),        // 单行省略
        SizedBox(height: 6),
        Row([QualityBadge(trailingGap: 8, showFileSize),
             Expanded(Text('${artist} - ${album}', 12 dim))]),
      ])),
      if (!selecting) IconButton(Icons.more_vert 22),      // 选择态收起菜单
    ]),
  ),
)
```

- 勾选框占用与序号**同宽的 24dp 列**，进出选择态时行内容不横向跳动
- 行内无封面（区别于首页 `_SongCardRow` 的 56 封面）；音质徽标在标题下与
  歌手同行，`showFileSize` 为真时徽标显示 `flac 61 MB` 而非码率

#### 5.4.7 顶栏与批量选择

- `_detailAppBar`：`toolbarHeight: 56`，leading BackButton，标题
  `selectMode ? '已选 $selectedCount 首' : title`；右侧筛选、排序
  （`_showSortSheet`，见 §4.22）与选择入口；`canSelect = totalCount > 0`
  （空列表不给入口），选择态额外出现 `select_all` / `deselect` 与退出
- `_BatchSelect` mixin：`bool _selectMode` + `Set<String> _selected`，
  `selectionOf(songs)` 与**当前可见列表取交集**，保证「已选 N 首」与实际
  处理数永远一致（被筛掉的行不参与）；`toggleSelectAll` 再点一次取消全选
- 四个批量动作：`Icons.low_priority` 下一首播放（`playNextInQueue`）、
  `Icons.playlist_add` 添加到歌单、`Icons.favorite_border` 收藏（按选中
  多数态翻转，逐首 `setStar`）、`Icons.download_outlined` 下载
  （`canDownload` 才出现；入列后台队列即返回，见 §4.8.5）
- `_BatchBar`：`GlassSurface(radius: 0, blur: GlassTokens.blurMedium,
  gradientBorder: false, shadow: false)`，padding 上 8 / 下 安全区+8；
  图标 22 `AppTheme.actionBlue` + 12 文字标签，`count == 0` 时整体 disabled

#### 5.4.8 可选评分（专辑入口）

- `canRate = rateTargetId != null && capabilities.ratings`，为真时
  `_Header` 显示五星 `StarRating`（其余皮肤/后端不出现）
- `_rate`：乐观更新本地 `_rating` → `adapter.setRating`，失败回滚原值并
  `showToast('评分提交失败', error: true)`

### 5.5 艺人歌曲入口（原独立 ArtistDetailScreen 已删除）

- 所有艺人歌曲入口（歌曲信息页 / 操作弹窗 / 搜索艺人行 / 资料库歌手列表）
  统一 push SongListScreen(pagedSongsProvider: artistSongsProvider(artistId), coverAlbumId: artistId)
- 分页数据源 ArtistSongsController（home_providers.dart）：累计 limit 策略、
  按 id 去重合并、返回少于请求量或无新增判定 noMore

---

### 5.6 资料库入口页（features/home/library_entries_screen.dart）

三张二级页都由资料库入口网格 push（见 §5.3.3），统一 `AmbientScaffold`
固定顶栏 + 无缝背景（见 §6.5），且都处理「后端不支持该能力」的空态。

#### 5.6.1 ArtistListPage（歌手 / 专辑艺术家，A-Z 分组 + 索引条）

```dart
ArtistListPage({required String title, required FutureProvider<List<Artist>?> provider, bool openAlbums = false})
```

- provider 返回 **null 表示后端不支持**（入口通常已隐藏，这里兜底
  `glassEmptyState('当前服务器不支持该内容')`）；`loading` → 转圈，
  `hasError` → `errorRetryBox(onRetry: invalidate)`
- `openAlbums` 决定行点击去向：专辑艺术家 → `AlbumListPage(provider:
  artistAlbumsProvider(id))`；歌手 → `SongListScreen(pagedSongsProvider:
  artistSongsProvider(id), coverAlbumId: id)`
- **拼音分组**（`lpinyin`）：`_pinyinKey(name)` 取无音调小写拼音（转换失败
  回退原名），`_letterOf` 取首字母、非 A-Z 归 `#`；排序按拼音键、同键再按
  原名小写；分组后 `#` 恒定排最后 → 中文名归入 A-Z 而非 Unicode 码点
- 固定行高常量 `_kHeaderHeight = 32` / `_kRowHeight = 64`：**索引条跳转靠
  算式**定位（`offset = 12 + Σ(header + n×row)`，`animateTo` 250ms easeOut），
  改行高必须同步这两处
- 顶部复用 `ListSearchBar(hint: '搜索歌手')`，过滤匹配**原名或拼音键**
  （所以输 "jay" 可命中「周杰伦」）；无匹配 → `glassEmptyState('没有匹配的歌手')`
- `_ArtistRow`：44×44 `ClipOval(EntityCover radius: 22)` + 名称 15 +
  副行 `N 首歌曲`（为 0 时降级 `N 张专辑`，再为 0 不显示）
- `_LetterIndexBar`：右侧 `Positioned(right: 2, bottom: 96)`，`GestureDetector`
  的 `onTapUp` 用落点 dy / (高度/字母数) 反查索引；底乘「面板透明度」系数
  （`withGlassTintOpacity(black .15)`）、圆角 10、字母 10 bold

#### 5.6.2 GenrePage（流派彩色瓷砖）

- `AmbientScaffold(appBar: AppBar(title: '流派'))` + 3 列 `GridView`
  （padding 12，spacing 10，`childAspectRatio: 1.5`），行 = `FadeSlideIn(index:)`
- **色相由流派名固定映射**：`hue = (genre.value.hashCode % 360).abs()` →
  `HSLColor.fromAHSL(1, hue, 0.45, 0.42)`，填充再乘面板透明度
  （`withGlassTintOpacity(color.withValues(alpha: .85))`）→ 同一流派在任何
  皮肤/任何次进入下颜色一致
- 瓷砖左下白字：流派名 14 bold + `N 首`（白色 .75，11，songCount 为 0 不显示）
- 点击 → `SongListScreen(title: genre.value, songsProvider: genreSongsProvider(genre.value))`
- 文案分支：`genres == null` → 「当前服务器不支持流派」/ 有 error → 「加载失败，
  点击重试」；空列表 → 「暂无流派」（icon `Icons.piano_outlined`）
  — 注意这两句走 `glassEmptyState`，**只有文案没有 onRetry 动作**，
  与 `errorRetryBox` 不一致（遗留待议）

#### 5.6.3 RadioPage（电台，本期仅展示）

- 三态同 GenrePage（`Icons.radio_outlined`，「当前服务器不支持电台」/
  「暂无电台」）；有数据 → `ListTile`：44 圆底 primary .18 + `Icons.radio` 22、
  台名 15、副行 `homePageUrl`（12 faint，null 不显示）
- **电台播放需独立流媒体管线，本期只做展示**（行不可点、无播放入口）

---

### 5.7 歌单：无独立详情页（原 playlist_detail_screen 已删除）

- 歌单详情 = `SongListScreen(playlistId: id, title: playlist.name,
  coverAlbumId: playlist.coverArt)`，头部/全部播放/筛选/批量选择全部复用 §5.4
- 数据源 `playlistSongsProvider`（`FutureProvider.autoDispose.family`）→
  `adapter.fetchPlaylistSongs(id)`；未连接服务器返回空列表而非抛错
- 空态文案特判 `'歌单暂无歌曲'`（其余入口为 `'${title}暂无歌曲'`）
- `playlistId` 一路透传到 `SongRow` → `showSongActionSheet`，**只有在歌单内**
  的行菜单才出现「从歌单移除」（`removeFromPlaylist` 后
  `ref.invalidate(playlistSongsProvider(id))`）；`capabilities` 不支持时隐藏
- 歌单封面 = 资料库列表的 `_PlaylistCover`（非详情页）：watch
  `playlistCoverIdsProvider(id)`（前 4 首歌去重专辑 id，**会话级缓存**、
  watch 服务器 id 切服即失效，避免每次进资料库为取 4 个 id 拉全量曲目）
  - ≥2 张 → 52×52 圆角 8 的 2×2 拼贴，不足 4 张时按下标取模循环补位
  - 1 张 → 单图；0 张 → 回退 `playlist.coverArt` 的 `CoverArt`，
    再无 → `AppTheme.surface` 底 + `Icons.queue_music` 26
- 管理动作在资料库歌单行的 `more_vert` 菜单里，不在详情页：播放 / 加入队列 /
  重命名（`glassDialog` + `renamePlaylist`）/ 删除（二次确认，
  `FilledButton` 染 `AppTheme.heartRed`）；成功后 `invalidate(playlistsProvider)`
  并 toast，失败 toast「重命名失败」/「删除失败」

---

### 5.8 搜索结果页（features/search/search_screen.dart）

#### 5.8.1 入口与页面骨架

- 入口：首页与资料库顶部的 `SearchEntryBar`（装饰性入口条）
  `fadeRoute(const SearchScreen())`；**`SearchScreen` 不带 query 参数**，
  进入即空输入态显示历史
- 无 `SearchDelegate`（1.x 的「过滤框即搜」方案已废弃）；详情页的
  关键词过滤是页内 `ListSearchBar` / `_FilterBar`，不发网络（见 §5.3.6 / §5.4.4）
- `Scaffold(body: SafeArea(child: Column[GlassSurface 搜索胶囊,
  _SegmentTabs, Expanded(_Results)]))`；页面**不**用 `AmbientScaffold`
- 搜索胶囊：`GlassSurface(radius: GlassTokens.radiusPill, blur: 0,
  tint: GlassTokens.tint(context), gradientBorder: true, shadow: false,
  margin: EdgeInsets.all(16))`，内含 `Icons.search` 24 + TextField +
  `_ClearButton`。TextField 必须**三层边框显式 `InputBorder.none`**
  （`border`/`enabledBorder`/`focusedBorder`）+ `filled: false` —— 主题的
  `applyDefaults` 会在空位补回边框，在玻璃胶囊里再套一层框

#### 5.8.2 数据流与防抖

```dart
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final searchResultProvider = FutureProvider.autoDispose<SearchResult>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const SearchResult();
  final adapter = ref.watch(serverAdapterProvider);
  return adapter == null ? const SearchResult() : adapter.search(query);
});
```

- 300ms 防抖（`_onChanged` 取消旧 Timer）→ 写 `searchQueryProvider`；
  `_submit` 跳过防抖立即生效
- **query 不在整页 watch**：`_ClearButton` 与 `_Results` 各自订阅，防抖触发时
  不重建搜索框胶囊与分段 Tab
- `autoDispose`：离开搜索页即销毁，重进时输入框与结果一致
- `_Results` 用 `when(skipLoadingOnReload: true, ...)`：换关键词的请求期间
  **保留上次结果**，只在首次进入时显示 `CircularProgressIndicator`
  （无骨架屏）；error 直接把异常文本渲染成 faint 文字

#### 5.8.3 结果分区与纯前端 Tab

- `ServerAdapter.search` 是**单次聚合调用**返回 `SearchResult{artists,
  albums, songs}`，因此 `_SearchTab {all, songs, albums, artists}` 只做
  **前端过滤**——切 Tab 零网络、零闪烁
- 全部视图截断：艺人 `take(3)`、专辑 `take(5)`、歌曲全量；单类 Tab 放开截断
- 分区标题 `_SectionTitle` 19 bold（padding 16/16/16/8）为独立 sliver；
  **裸排模式（默认）下每组用 `SliverList.builder` 虚拟化**，一次只
  build/layout 可视行；卡片模式（`cardDisplayProvider`）保留 `GlassContainer`
  整体包裹。否则大结果集一次性塞进 `SliverToBoxAdapter` 会阻塞整段 layout
- `_ArtistRow`：`EntityCover(48, radius 24)` + 名称 16 + 「N 张专辑 · N 首」
  14 → `SongListScreen(pagedSongsProvider: artistSongsProvider(id),
  coverAlbumId: id)`
- `_AlbumRowCard`：`CoverArt(48, radius 6)` + 名称 16 + 歌手 14 →
  `SongListScreen(rateTargetId: album.id, songsProvider:
  albumSongsProvider(album.id), subtitle: '${year} ${artist}', rating:)`
- 歌曲行直接复用详情页 `SongRow`（含序号/音质徽标/行菜单），
  `FadeSlideIn(index:)` 入场
- 空态文案分层：整体无结果 `Icons.music_off` 48 + 「未找到与"$query"相关的内容」；
  当前 Tab 无结果按 `_emptyText` 表给「未找到相关内容 / 未找到相关歌曲 /
  未找到相关专辑 / 未找到相关歌手」；尾部 `SizedBox(height: 96)` 让位迷你条

#### 5.8.4 搜索历史（`SearchHistoryController`）

- `NotifierProvider<SearchHistoryController, List<String>>`，
  **应用级存活**（非 autoDispose）；SharedPreferences key
  `'search.history.v1'`，JSON 数组，**最多 15 条**，新词/重查**去重置顶**
- `build()` 内用 `Future.microtask` 读盘后再赋 state —— 不能 build 期同步
  改（Riverpod 红线，见 §13）；历史损坏视为无历史，不影响搜索
- 写入时机只认**两类真实意图**：键盘提交 `_submit`、点击结果条目
  （`SongRow.onResultTap` / 艺人行 / 专辑行的 `onRecord`）；
  **防抖中间词不入史**
- 持久化失败静默（内存历史已生效，下次成功写入再补），空列表时 `remove(key)`
- UI `_HistoryView`：query 为空时替代结果区。无历史 → `Icons.search` 48 +
  「搜索音乐、专辑、艺人」；有历史 → 标题行「搜索历史」19 bold +
  `Icons.delete_outline` 清空 + `Wrap(spacing 8, runSpacing 8)` 的 `_HistoryChip`
- `_HistoryChip`：高 36 胶囊、`GlassTokens.tint` 底、词 14；尾部 `Icons.close`
  16 单条删除，外层 `Padding(all: 6)` 把命中区撑到 32×32
- 点 chip = `_searchFromHistory`：回填输入框 + 立即搜索 + 置顶该条

---

### 5.9 本地音乐（core/local/local_library.dart + local_library_io.dart）

没有独立的本地音乐页（`features/local/` 不存在），整条链路是「资料库入口 +
复用 `SongListScreen` + 一套本地扫描与快照缓存」。

#### 5.9.1 入口与页面

- 资料库「本地音乐」瓷砖（music_library_screen.dart）→
  `_openSongs(context, '本地音乐', localSongsProvider, onRefresh: forceLocalRescan)`
  → `SongListScreen(songsProvider:, onRefresh:)`，即 §5.4 的异步数据源分支
  （头部 + 顶部操作条 + 批量选择，与其他资料库歌曲入口完全一致）
- `onRefresh != null` 才出现下拉刷新（§5.4.2）：`forceLocalRescan()` 绕过 5 分钟
  限流直扫文件系统并覆盖快照，调用方随后 invalidate `localSongsProvider` 重读
- 头部副标题走 `showFileSize` 分支（传了 `songsProvider` 即为真）：
  显示「共计占用 X 空间」而非「共 N 首歌曲」；行内 `QualityBadge(showFileSize: true)`
  显示 `flac 61 MB` 而非码率（§5.4.4 / §5.4.6）
- 首次进页面（无快照）才同步等 `scanLocalLibrary()`；有快照先秒开、后台限流重扫
  ——不在 app 启动或 build 期扫描，符合零等待原则

#### 5.9.2 localSongsProvider：扫描段 + 已下载段合并

`FutureProvider<List<Song>>`（非 autoDispose），watch 三个源：
`localScanVersionProvider`（重扫发现文件变化）、`downloadIndexVersionProvider`
（下载完成）、`activeServerIdProvider`（切服）。返回 `[...本地扫描, ...已下载]`。

- **已下载段** `loadDownloadedSongs(serverId)`：读 `download_index.payload`
  的 Song 元数据快照反序列化，**身份保持服务器 id**——点播经
  player_source_resolver 自动命中离线文件，收藏/评分/歌词继续命中服务器歌曲，
  与 `local:` 歌曲天然不重
  - 只取 `server_id = 当前` 或 `server_id = ''`（无归属的历史行）：跨服同 id 歌曲的
    离线文件不互通，展示他服条目会造成「能看不能离线播」
  - payload 为空（旧版本所下）无法还原元数据，跳过；单条 JSON 损坏跳过不影响其余
  - 整批 payload > 256KB 时丢 isolate 解码
- **下载侧批量只 bump 一次**：download_queue 排空统一 `state++`、自动下载整批
  `state += downloadedCount`。逐首 bump 会让 `localSongsProvider` 每首全量重读快照
- `_rescanInBackground(ref, served)`：距上次完成 <5 分钟直接返回；扫完用
  `_sameSongs` 逐项比对 **id / size / duration / title / artist**，不一致才 bump
  `localScanVersionProvider`；扫描抛错（权限被系统回收等）静默保留快照

#### 5.9.3 Isolate 扫描流程

- 唯一实现：`Isolate.run(() => _scanIsolate(dirPaths, coverPath))`
  （local_library_io.dart:38），无 compute / SendPort；web 侧走
  `local_library_web.dart`，本地段恒为空
- Isolate 负责：目录递归遍历（`followLinks: false`，扩展名白名单
  mp3/flac/m4a/aac/ogg/opus/wav）+ audio_metadata_reader 标签解析
  （标题/歌手/专辑/时长/内嵌 LRC/内嵌封面）+ fingerprint 计算 + 封面抽盘。
  纯 Dart IO，**不访问 SQLite**——sqflite 走平台通道只能主 isolate 写
- 主 isolate 负责：接收 `_ScanResult{songs, lyrics}` record → 逐条
  `AppDb.saveLyrics` 写 lyrics_local（双键：`lyricsLocalKey(fingerprint)` +
  `lyricsFallbackKey(title, artist)`）→ `saveLocalScanCache` 写歌曲快照
- 文件列表按路径排序，保证指纹顺序与快照比对稳定；单目录不可读、单文件解析
  失败均 `continue`，不阻断整体扫描
- 权限：`ensureAudioPermission()` 仅 Android 侧请求（`Permission.audio`，
  被拒回退 `Permission.storage`），失败抛 `StateError`（上层保留快照不崩）
- 扫描目录由 `localScanDirs`（core/local/local_scan_dirs.dart）按平台给默认值：
  Android `Music` + `Download`、iOS Documents、Windows `%USERPROFILE%\Music`、
  macOS/Linux `~/Music` + `~/Downloads`、鸿蒙沙箱 Documents、web 空列表

#### 5.9.4 本地歌曲身份（fingerprint）与下载产物排除

- 本地歌曲 ID：`local:{fingerprint}`，fingerprint =
  `md5(文件大小 + mtime + 头部固定 16KB + 归一化标题/歌手 + 时长)`
  - 只读头部 `_fingerprintHeadBytes = 16 * 1024`，**禁止整文件 hash**
    （大 FLAC/APE 曲库不可接受）；头部读不出时退化为 size+mtime+元数据
  - 标题/歌手先 `trim().toLowerCase()` 归一化后参与
  - 移动/重命名不改身份；路径变化仍记录在 `Song.path`
  - fingerprint 是轻量身份指纹，不是完整性校验
  - `local:` 前缀与服务器歌曲 id 天然不冲突；`localSongFingerprint(song)` /
    `localSongPath(song)` 负责反向解析
- **下载产物排除**：`isDownloadedArtifact(path)` 按文件名标记
  `--[0-9a-f]{16}\.[ext]$` 跳过。下载落盘目录（Android 公共 `Music/流声`、
  Windows 音乐库 `\流声`）与本地扫描目录重叠，不排除会让同一首歌既作为服务器
  歌曲离线副本、又以 `local:` 身份重复入库；用户自放文件几乎不匹配该模式

#### 5.9.5 快照缓存

- 复用 `library_snapshot` 表（`server_key='local'`, `kind='local_songs_v2'`），
  无独立 local_scan_cache 表；写入 `ConflictAlgorithm.replace`，`version` 列存
  本次扫描时间 ISO8601
- 落库后顺带删除旧格式行（`kind='local_songs'`，路径 id 时代）——纯可再生缓存，
  无用户数据
- 大 JSON 阈值 `_snapshotIsolateThreshold = 256KB`：payload 超阈值时解码进 isolate；
  歌曲数 >1000 时编码也进 isolate
- 缓存读写全 `try/catch` 静默：失败只影响下次秒开，不影响本次结果

#### 5.9.6 无标签回退与内嵌封面

- `readMetadata(file, getImage: true)` 抛错时回退 `AudioMetadata(file: file)`；
  标签里的标题为空则按 `歌手 - 标题` 文件名拆分（与离线下载命名规则一致），
  拆不出则整名做标题、歌手取「未知歌手」
- 内嵌封面（FLAC/Ogg/MP3 ID3）抽到 `文档目录/covers/{文件大小}_{名hashCode}.img`，
  写入前查重；`Song.localCoverPath` 指向该文件（非服务端 URL），抽取失败按无封面处理
- 显示走 `CoverArt(localCover:)`（shared/cover_art.dart:62）：本地文件优先，
  经 `localFileImage()` 门面（io=FileImage / web=null），`ResizeImage` 按
  显示尺寸×DPR 限解码（内嵌封面常 1400²+，44px 槽位不全尺寸解），文件被外部清理时
  `errorBuilder` 回退 `assets/app/default-album.png`
  - 不在 build 中做同步磁盘 stat（性能红线：本地库列表滚动每个 item 都会触发）
- 本地 `Song` 的取值约定：`albumId`/`artistId` 为空串、`playCount 0`、
  `starred false`、`rating 0`、`suffix` 取扩展名、`bitRate`/`sampleRate` 来自标签、
  `codec`/`bitDepth` 为 null、`size` 为文件字节数

### 5.10 私人 FM 页面（features/fm/fm_screen.dart）

入口只有首页 `_FmBanner`（§5.2.1 顺序 2）→ `fadeRoute(FmScreen())`。
`FmScreen` 是 `ConsumerWidget`，骨架 `AmbientBackground` →
`Scaffold(backgroundColor: transparent)`：

- **顶栏**：透明底 + `textPrimaryOf` 前景，标题「私人 FM」，唯一动作「换一批」
  （`Icons.refresh`）。`fmLoadingProvider` 为 true 时图标原地换成 18×18
  `CircularProgressIndicator(strokeWidth: 2)` 并置灰，避免连点重复补批
- **两态**：`currentSongProvider == null` → 引导态 `_StartHero`，否则 `_NowRoaming`
- **_StartHero**：`Icons.radio` 88 faint + 「从你的曲库里随机漫游」15 dim +
  `FilledButton.icon`（底 `primary .9`、`play_arrow`、「开始漫游」）→
  `fmController.start()`；返回 false（曲库取不到候选）且 `mounted` 时 toast
  「没有拿到新歌，稍后再试」（error 样式）
- **_NowRoaming**：`SingleChildScrollView(padding: h32 v16)` —— `CoverArt`
  （`size: min(320, 屏宽-64)`、`radius: 16`）→ 标题 22 bold 单行居中 →
  `{artist} · {album}` 15 dim → 36 留白 → `Row(spaceEvenly)` 四个
  `IconButton(iconSize: 30)`：
  - `thumb_down_off_alt` 不喜欢 → `skipDislike()`（先切下一首再把它移出队列）
  - `favorite` / `favorite_border` 收藏 → `likeCurrent()`（starred 时取 primary，
    否则 textDim；乐观更新失败回滚，§4.21）
  - `_PlayPauseButton`：68×68 圆（`Border.all(primary, width: 2)` + 内填
    primary .12）+ `pause`/`play_arrow` 34
  - `skip_next` → `playerActions.playNext()`
- **不做的事**：队列由全局 `queueProvider` 承载，本页只是「当前这首歌的漫游台」，
  切歌补批由常驻 `FmRefillService` 监听 `currentSongProvider` 完成（离开页面也生效），
  **页面自身不再挂 `listen`**（§4.21）

### 5.11 听歌统计页（features/stats/stats_screen.dart）

入口 = 资料库页「听歌统计」（`music_library_screen.dart:221`，§5.3）。
`AmbientScaffold` + `AppBar(toolbarHeight: 56, foregroundColor: textPrimaryOf,
title '听歌统计')`（固定顶栏 + 无缝背景，详见 §6.5）。

- **body**：`RefreshIndicator`（`_refresh` 一次性 invalidate summary/歌榜/歌手榜
  三个 provider）→ `CustomScrollView(AlwaysScrollableScrollPhysics)` →
  单个 `SliverPadding(16, 8, 16, 48)` + `SliverList`
- **滚动顺序**：`_SummaryGrid` → 28 → 「最常听的歌曲」19 bold → 8 → `_TopSongs` →
  28 → 「最爱歌手」19 bold → 8 → `_TopArtists` → 12 → 页脚
  「统计来自本机播放记录，仅计当前服务器」12 dim 居中
- **_SummaryGrid** 的四层空/错处理：加载中 120 高居中转圈；失败
  `errorRetryBox(onRetry: invalidate)`；`summary == null`（未连服务器）→
  `glassEmptyState('未连接服务器', Icons.insights)`；`totalPlays == 0` →
  `glassEmptyState('还没有播放记录\n去听几首歌再来吧')`
  - 四格 2×2 **裸排**（无卡片，§13 去卡片方向）：两行 `Row` 各两个
    `Expanded(Column(值 22 bold + 4 + 标签 12 faint))`，行距 20；标签固定
    `总播放 / 收听时长 / 听过歌曲 / 近30天播放`
  - 收听时长由 `totalDurationMs ~/ 60000` 起步，≥60 分钟才写成「X 时 Y 分」
- **_TopSongs**：spinner 80 高 / `errorRetryBox` / **空列表返回 `SizedBox.shrink()`**
  （summary 已经说过「还没有播放记录」，此处不再重复一行空态）
  - `ListTile(contentPadding: EdgeInsets.zero)`，leading = 24 宽序号 + 8 +
    `CoverArt(44, radius 6)`；**前三名序号取 primary**，其余 textFaint（14 bold）
    —— 序号即排名，不再叠加「1. 」前缀文本
  - 标题 15 / 副行歌手 13 dim / 末尾 `{n} 次` 13 faint
- **_TopArtists**：`ListTile(dense: true)` + `CircleAvatar(radius: 18,
  bg primary .18)` 内 `Icons.person` 20 primary + 歌手名 15 + `{n} 次`
- 数据来源是本地 `play_history` 表（§4.20），按当前服务器过滤，与服务端播放次数无关

### 5.12 播放队列 / 下载列表弹层（features/player/queue_modal.dart + download_queue_sheet.dart）

两个弹层共用同一套壳：`showModalBottomSheet(backgroundColor: transparent,
barrierColor: Colors.black38, isScrollControlled: true, shape:` 顶部
`GlassTokens.radiusSheet` 圆角`)`，内容再包
`ConstrainedBox(maxHeight: 屏高 × 0.6)` + `AlbumFrostedPanel`（§6.6）。
两者都**不拉满全屏**：队列/任务少时随内容收缩，多时封顶六成屏高。

#### 5.12.1 showQueueModal（播放队列）

入口：全屏播放页队列按钮（`full_screen_player_bottom.dart:240`）与迷你条
（`mini_player.dart:56`）。面板 `dominant` 取
`currentAlbumDominantProvider`——**底色随当前专辑封面主色**（与播放页同色系，
毛玻璃但近实色不透明，§4.2.6 / §13 播放页材质定稿），`padding: top 8 /
bottom 安全区+8`。

- **拖动条** 40×4（`colors.outline`，r2，注释记录该圆角为拖动条豁免）
- **头部**：`Row` 两端对齐——左 `Expanded` 的 `播放列表({n})`
  （titleMedium 16 w600，超长省略），右两枚紧凑 `FilledButton`
  （labelMedium、高 36、shrinkWrap、`AppRadius.s`；**播放页弹层同款白色半透明
  胶囊**：白 0.08 底 / onSurface 前景 / 白 0.16 按压 / focus 描 onSurface 边，
  不随封面取色）：「清空」→ `clearQueue()` +
  toast「已清空播放队列」1 秒（空队列禁用）；播放模式 → `cyclePlayMode()`
  （icon 18 + 文案）：`repeat` 顺序播放 / `shuffle` 随机播放 / `repeat_one` 单曲循环
- **空态**：footer `Padding` + `queue_music_outlined` 32 +
  「队列为空\n去首页挑几首歌开始播放」（onSurfaceVariant）
- **列表**：`ReorderableListView.builder`（padding 横向 8，与头部对齐）
  - `buildDefaultDragHandles: false`；行高只设 `minHeight: 64` 下限，
    文字随系统 TextScaler 自然撑高
  - `onReorderItem` 的 `newIndex` 已完成「移除位」修正，直接透传
    `reorderQueue(old, new)`，不回到旧版 `--newIndex` 补偿
  - `proxyDecorator` 用 `AnimatedBuilder` 让拖动副本随进度浮起：`Material`
    panelBase 底 + `AppRadius.s` + `elevation = t × 6`
- **行**：外层 `Dismissible(key: ValueKey(song.id), endToStart)`，底衬
  `errorContainer` + `delete_outline`，`margin 8/4/8/4` + `AppRadius.m`，
  只在滑开时露出 → `removeFromQueue`
  - 32 宽序号把手列：`ReorderableDragStartListener`（序号即把手），
    整行再包 `ReorderableDelayedDragStartListener` 长按可拖；
    **当前行放电平条**，其余 tabular 等宽数字右对齐（位数变化不抖动）
  - `CoverArt(40, localCover: song.localCoverPath)`——离线/本地歌走磁盘封面（§5.9.6）
  - 标题 bodyLarge（当前行 w600，前景统一 onSurface）/ 歌手 bodySmall
    onSurfaceVariant + `close` 20 删除（48 热区）
  - 当前行包 `Container(clipBehavior: antiAlias, 白 0.1, AppRadius.m)`，
    普通行只加 0.5 `outlineVariant` 底边
  - 点击行：先 `pop()` 再 `play(song)`，不留在弹层上
- **电平条单点订阅**：`_CurrentEqualizer` 只 `watch(isPlayingProvider)`，
  播放/暂停切换不再触发整表重建；流未吐首值时按「播放中」处理（`.value ?? true`），
  避免刚打开弹层就静止。`_EqualizerBars`：900ms 循环，三根 3px 竖条相位
  `[0, .38, .71]`，高度 4–16，**三角波**（`t<.5 ? t*2 : (1-t)*2`）避免锯齿波在
  循环接缝跳变；暂停时 `stop()` + `value = 0` 冻结在低位。全场仅当前行一个实例

#### 5.12.2 showDownloadQueueSheet（下载列表）

入口唯一：设置 → 存储 → 下载列表（`settings_sub_storage.dart:126`）。
面板 `AlbumFrostedPanel(dominant: null, opaque: true)`——**不随封面取色**
（后台任务与当前播的歌无关），状态源 §4.8.5。

- 头部「下载列表」16 w600；仅当存在 completed/failed 任务时才出现
  「清已完成」`TextButton` → `clearFinished()`；`Divider(height: 1,
  textPrimary .08)`
- 空态 14 faint「暂无下载任务」（`padding: vertical 48`）
- `_TaskTile` 四态一次 `switch` 出 `(icon, iconColor, statusText)`：
  waiting `Icons.schedule`/faint/「排队中」；running `downloading`/primary/
  `{pct}%`（`total <= 0` 时改「连接中…」）；completed `check_circle`/primary/「已完成」；
  failed `error_outline`/`colorScheme.error`/`task.error ?? 下载失败`
- leading 在 running 时换成 22×22 `CircularProgressIndicator(strokeWidth: 2.2,
  value: progress)`；副行 `{artist} · {状态}` 12 faint，running 且已知总长时追加
  3px `LinearProgressIndicator`（底 textPrimary .12、r2）
- trailing：running 不给按钮（避免中断中任务被误删）；failed 先「重试」
  （`refresh` 20 primary → `retry(task.id)`）再「移除」；其余只「移除」→ `remove`

### 5.13 歌曲信息页（features/home/song_info_screen.dart）

入口 = 歌曲操作弹窗「歌曲信息」（`action_sheets.dart:294`）。
`SongInfoScreen({required Song song})` 是 **StatelessWidget**——整页纯渲染，
不碰 `ref`。

- **骨架**：`AmbientScaffold` + `AppBar(toolbarHeight: 56, title '歌曲详情')` +
  **`bottomNavigationBar: const MiniPlayer()`**（从任意列表深挖进来也能直接控播），
  body 是 `CustomScrollView` → 单个 `SliverToBoxAdapter(Padding(16, 8, 16, 24))`
- **分组卡片** `_section`：标题 14 dim（padding 4,16,0,10）+
  `GlassCard(radius: AppRadius.l, padding: h AppSpacing.l / v AppSpacing.s)`；
  页身裸排、分组才用卡（§13）
- **三组字段**（后端缺字段一律显示「—」，不猜值）：
  - **基础**：标题 / 专辑（可跳）/ 专辑艺术家（`albumArtist ?? artist`）/
    歌手（可跳）/ 歌词（`parseLyricsData(song.lyrics).lines.isNotEmpty` →
    「查看歌词」可点，否则「暂无歌词」不可点）/ 年代 / 碟号 / 音轨号
  - **扩展**：文件路径（`wide: true` → 3 行省略）/ 文件大小
    （`size/1024/1024` 两位小数 + MB，`size <= 0` 显示「—」）/ 文件格式 `suffix` /
    时长 / 比特率 kbps / 采样率 kHz（1 位）/ 位深 bit / 播放次数 /
    上次播放时间 / 创建时间
  - **回放增益**：整组 `if (rg != null)` 才出现，四行为专辑/音轨的
    `_db`（1 位 + ` db`）与 `_plain`（1 位）
- **行组件**：`_row` = label 15 dim + 16 间距 + `Expanded` 值 15 primary 右对齐
  单行省略；`_navRow` 额外 `SizedBox(6)` + `chevron_right` 20 faint，
  包 `InkWell(borderRadius: AppRadius.s)`，且 **`onTap == null` 时直接退化为 `_row`**
  （不留点不动的哑箭头）
- **跳转**：专辑 → `SongListScreen(rateTargetId: albumId,
  songsProvider: albumSongsProvider(albumId), title: album, subtitle: artist)`；
  歌手 → `SongListScreen(pagedSongsProvider: artistSongsProvider(artistId),
  coverAlbumId: artistId)`（分页，§5.4/§5.5）
- **歌词弹层**：`glassDialog(title: '歌词', content: ConstrainedBox(maxHeight:
  屏高 × 0.5) + SingleChildScrollView(Text 15, height 1.7)), actions: [关闭])`
- **格式化约定**：`_num` 把 `null` 与 `<= 0` 一并归「—」；`_fmtIso` 同时吃
  ISO8601 **与 epoch 秒**（不同后端两种都给），统一输出 `yyyy-MM-dd HH:mm:ss`，
  解析失败返回 null 由调用方显示「—」；`_fmtDuration` 超一小时走 `h:mm:ss`，
  否则 `mm:ss`

---

## 六、UI 组件库详细规格

> 唯一事实来源：`lib/shared/widgets/`（`glass.dart` / `glass_quality.dart` /
> `motion.dart` / `toast.dart` / `async_states.dart` / `list_end_mark.dart`）。
> 尺寸与色值一律来自 `GlassTokens` / `SkinTokens` / `AppSpacing`（§4.14.4），
> 组件内不写死 hex；透明度与模糊一律走全局两个开关（§4.14.9）。

**主题组件命名契约**（`glass.dart:18-26`；页面层只消费语义组件，不判断皮肤枚举、
不手写颜色）：

| 契约名 | 真身 | 是否真实 typedef |
|------|------|------|
| `AppStage` | `AmbientBackground`（皮肤舞台 / 自定义背景图） | ✅ |
| `AppSurface` | `GlassSurface` | ✅ |
| `AppSheet` / `AppDialog` | `glassBottomSheet` / `glassDialog` | ❌ 仅注释约定 |
| `AppListEnd` | `ListEndMark`（`list_end_mark.dart`，列表结束提示） | ❌ 仅注释约定 |

> `GlassSurface` 的文档注释同时确立一条原则：**液态玻璃以外的主题不会退化成
> 「关掉 blur 的玻璃」**，而是走各自的实色材质（见本节末分支表）。

### 6.1 GlassSurface 系列

| 组件 | 用途 | 关键参数（真实默认值） |
|------|------|----------|
| GlassSurface | 一切玻璃质感的基元，其余三个都包它 | `radius=GlassTokens.radiusCard(16)`、`blur=blurMedium(18)`、`tint=null`、`gradientBorder=true`、`borderColor=null`、`shadow=true` |
| GlassCard | 列表项 / 网格卡（滚动区内的唯一选择） | **blur 固定 0**、`shadow: false`、`gradientBorder: true`、`onTap` 非空时套 `GestureDetector(behavior: opaque)`；`cardDisplayProvider=false` 时降级为 `_bare`（只留边距） |
| GlassPill | 胶囊标签 / Tab | `radiusPill(999)`（**不乘 radiusScale**）、`blurMedium`、`shadow: true`；StatelessWidget |
| GlassContainer | 非滚动 chrome 的内容区块 | `blurContainer(12)`、`shadow: true`、同样支持裸排降级 |
| GlassAppBar | 顶栏（配合 AmbientScaffold） | `preferredSize = Size.fromHeight(56)`；`ClipRRect(下沿 radiusCard)` + `blurMedium×scale` + 底边 `BorderSide(tokens.borderTop, 0.5)`；标题走 `theme.textTheme.titleMedium`（H3 字阶） |

**性能红线**（`GlassContainer` 文档注释原文）：`BackdropFilter` 只用于非滚动
chrome 或单卡，**列表滚动项一律用 blur=0 的 `GlassCard`，禁止逐行挂
BackdropFilter**。

**GlassSurface 绘制顺序**（`ConsumerWidget.build`，自上而下）：

1. 读三个全局设置作为响应式依赖：`glassQualityProvider`、
   `powerSaveProvider`、`glassTintOpacityProvider` —— 已保活页面与底部导航
   因此会随设置同步刷新，无需重启。
2. `blurRequested = blur > 0 && tokens.blurEnabled`；
   `useBlur = shouldUseBlur(context) && blurRequested`；
   `blurScale = glassBlurScale(context) * tokens.blurScale`。
3. `effectiveTint = tint ?? Color.alphaBlend(accent α0.08, tokens.glassTint)`；
   `scaledRadius = radius == radiusPill ? radius : radius * radiusScale`。
4. **底色三条路径**（解决「本来要挂模糊但档位关闭/省电降级时，0.30 左右的
   玻璃 tint 会直接透底」）：
   - `useBlur` → `effectiveTint` 的 α × 面板透明度系数；
   - `blurRequested` 但被降级 → `Color.alphaBlend(effectiveTint,
     tokens.surface)` 再 × 系数（**近实色补底**，观感与模糊态接近）；
   - `blur == 0`（GlassCard）→ `Color.lerp(effectiveTint, black, 0.15)`，α 乘系数。
5. `ClipRRect` → `BackdropFilter(sigma = blur × blurScale)` → `tinted()` →
   `_GradientBorderWrapper` → 投影 `Container` → `RepaintBoundary`。

**tinted() 的两处细节**：

- 高光只在 `highlightStrength > 0` 时叠加 `foregroundDecoration` 的
  `LinearGradient(topLeft → bottomCenter, [white α(0.10×highlight), white α0],
  stops [0, 0.25])`——即高光只占顶部 1/4，不做整面洗白。
- 子树包 `Material(type: MaterialType.transparency)`：否则外层带背景色的
  `DecoratedBox` 会挡住 `ListTile`/`InkWell` 的墨水（debug 断言 + 水波纹不可见）。

**投影**：`[if shadowColor.a > 0 BoxShadow(shadowColor, blur 12, offset (0,4)),
if glow.a > 0 BoxShadow(glow, blur 24)]`——光晕色只在支持它的皮肤上非零。

**_GradientBorderPainter 行为**（真实实现）：

- 绘制前 `rect.deflate(0.5)`，`strokeWidth = 1`。
- `strength <= 0`：回退纯色 `tokens.borderHairline`（不是 accent 半透明）。
- `strength > 0`：`LinearGradient(topCenter → bottomCenter,
  [alphaBlend(accent α(0.35×s), white α(0.35×s)), white α(0.08×s)])`。
- 仅当 `gradientBorder == true && borderColor == null` 时启用；显式给
  `borderColor` 则走普通边框。

**非玻璃皮肤分支** `_buildNonGlassSurface`（`tokens.language != liquidGlass`）：
先把 `tint == tokens.glassTint` 归一成 `null`（避免默认值污染），再按皮肤分派——

| 语言 | 材质 |
|------|------|
| deepSpace | 光晕 `BoxShadow(blur 18, spread -5)` |
| minimal | `divider` 色实线边框 |
| materialYou | `borderHairline` 边框 |
| sunset | 光晕 `blur 18, spread -6` |
| forest | `borderHairline` 边框 |
| terminal | 光晕 `blur 10, spread -4` |
| albumTint | `borderHairline` 边框 |
| liquidGlass | `throw StateError('Handled above')`（防御，不可达） |

**imageBgAwareTint(ref, tint)**：设置了自定义图片背景时把 α > 0.75 压到 0.75，
保证任何卡面都留住一点背景透出（自定义背景优先级最高，见 §6.5）。

### 6.2 悬浮层：glassBottomSheet / glassDialog

| 入口 | 规格 |
|------|------|
| `glassBottomSheet` | `barrierColor: black α0.38`、`backgroundColor: transparent`；内容 `Padding(all 8)` + `GlassSurface(radiusSheet 24, blurHeavy 28, padding: top 12 / bottom = safe+16 / h 16)`；顶部 36×4 `white24` 拖动条（**圆角豁免 2px**）；`scrollable` 时包 `Flexible(SingleChildScrollView)` |
| `glassSheetConstraints(context, {factor = 0.7})` | 自带滚动的自定义弹层的限高辅助函数（屏高 × factor）。**当前无调用点**——队列/下载弹层各自显式写 `ConstrainedBox(maxHeight: 屏高 × 0.6)`（§5.12），新弹层可直接复用这个函数 |
| `glassDialog` | `Dialog(transparent, elevation 0, insetPadding h28/v24)` + `GlassSurface(radiusSheet, blurHeavy, shadow: false, tint = alphaBlend(primary α0.08, glassTint), padding LTRB(20,18,20,14))`；标题 17 w700；正文 `Flexible(SingleChildScrollView)`；按钮行右对齐 |

弹层透明度不设私有硬编码：两条路径的 tint 都继续乘全局面板透明度系数，
设置页滑杆联动即时生效（§4.14.9）。

### 6.3 动效组件（motion.dart）

时长/曲线令牌清单见 §15.4；这里是消费它们的组件。

| 组件 | 行为 | 约束 |
|------|------|------|
| `fadeRoute` | 前进 `durationTransition`、返回 `durationSnappy`；`ColoredBox(AppTheme.shellOf)` 只在 `Interval(0, 0.3, easeOut)` 内不透明 → 下层页面不透出（修复弹出页「透明的」观感）；内容 curveStandard 进 / easeInCubic 退 + 位移 (0, 0.03)→0 | 路由级转场统一走它，不在页面里手写 PageRouteBuilder |
| `FadeSlideIn` | 14px 上浮 + 淡入；`Interval(min(i×0.035, 0.25), 1.0)` 即每项 35ms 错峰、封顶 25%；`durationEntrance` | **无状态**（不挂 AnimationController），可用于列表首屏 |
| `PressableScale` | `AnimatedScale` 0.97↔1、120ms easeOut + `GestureDetector(behavior: opaque)` | 按下反馈的唯一姿势，不要再叠弹跳 |
| `PopOnChange` | `TweenSequence` 1→1.25（weight 45，easeOut）→ 1.25→1（weight 55，easeInOutCubic），`durationPop`；在 `didUpdateWidget` 里按值变化触发 | 用于「状态被外部改动」的一次性强调（收藏心形、播放模式切换） |
| `AppMotion.duration(context, base)` | 省电模式下返回 `base × 0.4` | 自建动画的时长入口 |

### 6.4 AppToaster / showToast

顶部悬浮 Toast，**不依赖 BuildContext**（`static GlobalKey<AppToasterState>
toasterKey` 挂在壳层，任意位置 `showToast(msg, {error})`）。

- `show()` 自增 `_epoch` 后 setState，`Timer(duration)` 置空文本；`duration`
  为 null 时按语义取 **成功 2s / 失败 3s**。
- 渲染：顶部 `SafeArea(minimum top 8)` → `IgnorePointer`（不吃手势）→
  `Align.topCenter` → `AnimatedSwitcher(280ms, easeOutCubic 进 / easeInCubic 退)`
  → `ClipRect + SlideTransition((0,-1)→0) + FadeTransition`。
- 卡面：`ConstrainedBox(maxWidth 420)` + `GlassSurface(radiusPill, h18/v12)`
  + 16px 图标（失败 `error_outline`/error 色，成功
  `check_circle_rounded`/primary 色）+ 文本 13.5 w500 height 1.25 **maxLines 2**。

### 6.5 AmbientScaffold 页面骨架

> 二级列表页的统一骨架，解决「顶栏与页面背景不同色、滚动时文字叠字」。

```
ColoredBox(SkinTokens.shell)          ← 先垫皮肤底色，避免首帧闪主题背景
  > AmbientBackground                 ← 舞台层（皮肤装饰或自定义图）
  > Theme(appBarTheme 透明化)          ← backgroundColor / surfaceTintColor /
  > Scaffold(backgroundColor: transparent,   shadowColor 全透明，
    appBar,                            elevation 0，
    body: ClipRect(child: body),       scrolledUnderElevation 0
    bottomNavigationBar)
```

- **顶栏与页面背景无缝同色**：`GlassAppBar` 只叠一层模糊 + 0.5px 底边，
  没有独立底色，因此滚动时文字不会压在异色块上；`body` 的 `ClipRect`
  把子页的圆角/裁剪溢出挡在骨架内。
- 必传 `appBar`，可选 `bottomNavigationBar`。
- 使用范围（当前 13 个文件）：资料库全部列表二级页（`detail_screen`、
  `library_entries_screen`、`music_library_screen`、`song_info_screen`、
  `stats_screen`、`server_detail_screen`）+ **全部 7 个设置二级页**
  （`settings_sub_appearance/effects/network/playback/player_style/storage/system`）。
- 首屏级页面（壳层、登录、选服、FM）用 `Scaffold + AmbientBackground`
  直接组合（要保留各自非透明的顶栏策略）；**播放页两者都不用**（§4.14.8、§13）。
- `AmbientBackground`（`glass.dart:746`）内部：`Stack[if(!hasImage)
  _AmbientStage, if(bgImage != null) IgnorePointer(Opacity(bg.opacity.clamp,
  blur > 0 ? ImageFiltered : Image, fit: cover, gaplessPlayback)), ?child]`。
  `localFileImage()` 在 web 返回 null → 自动回退皮肤舞台；**自定义背景图优先级
  最高，命中时跳过所有舞台装饰**。舞台 painter 参数见 §4.14.8。

### 6.6 AlbumFrostedPanel（播放页弹层面板）

播放页唯一允许的面板材质（详见 §4.2.6 取色、§5.12 队列/下载弹层）：

- `albumFrostedTint(d)` = `dominant == null ? null : Color.lerp(d, black, 0.55)
  .withValues(alpha: 0.90)`。
- `AlbumFrostedPanel({required dominant, required borderRadius, padding,
  required child, opaque = false})`，底色取
  `albumSolidTint(dominant) ?? AppTheme.surfaceOf(context)`：
  - `opaque: false` → `ClipRRect > BackdropFilter(blur 28) > Container(
    withGlassTintOpacity(ref, base.withValues(alpha: 0.90)))`；
  - `opaque: true` → 去掉模糊层直接实色（反正也不透出），但仍随全局滑杆走：
    滑杆降到 100% 以下时同样变透明。歌曲上下文弹层（更多菜单 / 添加到歌单）用。
- 取色梯度定稿：**面板 0.90 / 歌曲弹层实色 / 选择器 0.90**。
- 消费点：`action_sheets.dart:113/687`、`download_queue_sheet.dart:37`、
  `full_screen_player_lyrics.dart:586/628/668/723`、
  `full_screen_player_recommend.dart:89`、`queue_modal.dart:61`。

### 6.7 异步三态组件（async_states.dart）

所有列表页共用同一套 loading / error / 空态视觉，不再各页手写三态块。
语义：`data == null` 时才显示 loading/error（**刷新时保留旧数据，不转圈清空**），
`data` 为空列表才显示空态。

| 组件 | 用途 | 关键规格 |
|------|------|----------|
| `asyncStateBox` | Box 版（普通 ListView/GridView 页） | `onData(data)` / `emptyText` / `onRetry` |
| `sliverAsyncGuard` | Sliver 版，直接展开塞进 `CustomScrollView.slivers` | 同上，返回 `List<Widget>` |
| `glassEmptyState` | 玻璃质感空态 | 64×64 `GlassSurface(radiusPill, blur 0, gradientBorder, shadow false)` 内 30px `textFaint` 图标 + 文案 14 `textDim` + `Wrap` 操作组；**空态必须给出明确出口**（同步 / 新建 / 重试），不是一句「暂无内容」 |
| `errorRetryBox` | 错误重试块（整页与分页「加载更多」失败共用） | TextButton「加载失败，点击重试」 |
| `noMatchBox` | 过滤框无结果 | padding `AppSpacing.xl`（区别于整页空态的 xxxl） |
| `LoadMoreRow` | 分页行：idle 可点 / loading 转圈 / 失败重试 | `noMore` 时整行隐藏，由 `ListEndMark` 收尾；16×16 spinner strokeWidth 2 |
| `ScrollBottomLoader` | 滚动接近底部自动触发 | `threshold = 600`，判据 `pixels >= maxScrollExtent - threshold`；**`onBottom` 自身须有 loading/noMore 防重入** |

辅助文本统一 `_stateStyle` = 14px + `AppTheme.textDimOf(context)`（随皮肤，
不写死白阶）；整页三态 padding 统一 `EdgeInsets.all(AppSpacing.xxxl)`。

### 6.8 播放页动效与唱片形态

播放页材质与取色的规格见 §4.2.6 / §6.6，这里只列动效构件与唱片视觉参数。

**页面级**（`full_screen_player.dart`）：

| 构件 | 规格 |
|------|------|
| `_CascadeIn` | 复用打开路由的时间线做错峰入场：`Interval(begin, end, curveStandard)` + 反向 `easeInCubic`，`Opacity` + `Transform.translate(0, dy×(1-v))`；`anim == null` 原样展示。区间：顶栏 0→0.45/dy14、TabBarView 0.10→0.62/dy30、底栏 0.22→0.75/dy36（后入场先退场） |
| `_TabZoom` | 当前页满幅，相邻页 `Transform.scale(0.96+0.04t)` + `Opacity(0.55+0.45t)`；三页 keep-alive，**拖动每帧只重建这层壳，子页零重建**（性能红线） |
| 下拉关闭 | `fling = velocity.pixelsPerSecond.dy > 900`；`fling || dragOffset > 120` → 位移到屏高 + `easeInCubic` 关闭，否则 `easeOutBack` 回弹 |

**唱片 / 封面**（`full_screen_player_now_playing.dart`，`part of` 播放页）：

- 尺寸常量 `const double _discSize = 280`；动画：`_spin` 18s/圈（暂停停在原位）、
  `_arm` 420ms、`_glow` `durationHalo`。三个都由
  `audioPlayerProvider.playerStateStream.map((s) => s.playing).distinct()` 驱动，
  `style.spins` 决定唱片是否转，**光晕额外要求 `!powerSaveProvider`**。
- `_SquareCover`（`square` 与 `fullBlur` 两种样式）用
  `GlassSurface(radius: AppRadius.xl, blur: blurContainer, gradientBorder: true)`
  作黑胶框——这是 611b9fa **冻结的例外**：播放页的弹层与面板必须用
  `AlbumFrostedPanel`，只有这个封面框保留玻璃描边。
- `_VinylDisc`：`RadialGradient([#2A2A2A, #161616, #060606], stops [0, .72, 1])`
  + 投影 `black45 blur 24 spread 2` + 纹路环 224（white α.05）/ 196（α.04）
  + `_fadeCover(albumId, 120, 8)`；`_Tonearm` 定位 `right 0 / top 2`。
- `_CdDisc`：`SweepGradient([#DDE2E8, #B7C6DC, #EAEFF6, #D3C3E2, #BFDAD6,
  #DDE2E8], stops [0, .18, .38, .58, .78, 1])` + 内圈 188 `#EDEFF3`
  边框 white α0.6 + `_fadeCover(150, 75)` + 中心孔 34 `#0C0E12` white24 边框。
- `_Tonearm`：支点 `(w-18, 18)`，`_raisedDeg = -10`（暂停，甩到盘缘外）↔
  `_loweredDeg = 26`（播放，落在纹路上）；臂杆 `LinearGradient([#F1F2F4,
  #9BA2AB])` 5px round，唱头 RRect 12×22 r3 `#24272D`，底座 r12 `#66000000`
  + r8 `RadialGradient([#F6F7F9, #868D96])`。
- `_fadeCover`：`AnimatedSwitcher(durationCoverFade, curveStandard 进 / easeIn 退,
  Fade + Scale 0.92→1)` > `KeyedSubtree(ValueKey(albumId))` > `_SheenCover`
  ——切歌时旧封面淡出同时新封面轻微放大落位（§4.2.6 取色连续性）。
- `_Sheen` 扫光：`TweenAnimationBuilder` 950ms，只在 `Interval(0.4, 1.0,
  easeOutCubic)` 内走，偏移 `(size+140)×(t×2-1)`，`rotate 0.5` 的 90×600
  渐变条 `[white α0, α0.16, α0]`。
- `_GlowWrap` / `_DiscGlow`：`SizedBox(280) > OverflowBox(max 280+96) >
  Stack[_DiscGlow, child]`；`t = 0.5 + 0.5×sin(glow.value×2π)`，
  280+88 圆 `RadialGradient([color α(0.28×t), α0], stops [.55, 1])`。
- `_BlurredBackdrop`（fullBlur 形态背景）：`FittedBox(CoverArt(size: 100))`
  ——**模糊背景不需要高清源**，小尺寸取源命中 300 档；
  `ImageFiltered(blur 46×glassBlurScale)` + `Opacity .55`；
  玻璃档位关闭时降级为不模糊的放大封面（低端机性能红线）。

**播放按钮**（`full_screen_player_bottom.dart`）：

- 布局占位与原 56 按钮一致：`SizedBox(72×56) > OverflowBox(88×88)`，
  光环与脉冲**外溢**不挤排版。
- `_halo`（`durationHalo` 循环呼吸）：72 圆 `border white α(0.22×t) 1.5px`，
  仅在 `isPlaying && !powerSave` 时 `repeat()`，否则 `stop()`——
  **循环动画必须挂省电门**（§13）。
- `_ping`（点击一次性扩散）：`56 + 28t` 圆
  `border white α(0.35×(1-t)) 1.5px`，`Curves.easeOut`。
- 播放/暂停图标切换：buffering 时 15px padding 的
  `CircularProgressIndicator(strokeWidth 2.5)`，否则 `AnimatedSwitcher`
  （Fade + Scale 0.6→1 + Rotation 0.8→1，`Key: ValueKey(isPlaying)`，36px 白）。
- 收藏心形与播放模式都用 `PopOnChange`（§6.3）；已收藏色 `#E57373`。
- 队列入口：`queue_music` 24 → `showQueueModal`（§5.12）。

---

## 七、数据库表结构

> 唯一事实来源：`lib/core/storage/app_db.dart`（当前 **version=6**，5 张表）。
> 表清单与迁移阶梯见 §4.17；本节只给字段级规格。
> Migration 约束：只允许 ADD COLUMN / CREATE TABLE（IF NOT EXISTS）；
> 破坏性操作仅限可再生缓存且必须注释说明。

### 7.1 library_snapshot

| 字段 | 类型 | 说明 |
|------|------|------|
| server_key | TEXT PK | 服务器 ID（auth.activeServerId ?? 'none'）；本地扫描缓存固定为 'local' |
| kind | TEXT PK | `songs_all_v2` / `albums_name_v2` / `local_songs_v2`（下表） |
| version | TEXT | 服务端变更标记（libraryVersion 返回值）；本地行为写入时间 |
| payload | TEXT | JSON 编码的完整列表数据（>256KB 时 Isolate.run 解码） |

| kind | 内容 | 为什么是 v2 |
|------|------|------|
| `songs_all_v2` | 全库歌曲（`SongQuery(sort: title, limit: 100000)`），展示顺序由 UI 侧决定 | 旧快照可能是 `getRandomSongs` 的随机子集（全库枚举上线前所存），而 `libraryVersion` 未变时会永远命中旧数据 → 只能换 kind 作废重拉 |
| `albums_name_v2` | 专辑全量（`sort: name, limit: 10000`） | 上限从 100 提到 10000，旧快照只有 100 条需作废 |
| `local_songs_v2` | 本地扫描结果（server_key 固定 `'local'`） | v2 = fingerprint ID 格式；写入后 `DELETE` 旧 `local_songs` 行（纯可再生缓存，无用户数据） |

- 插入: conflictAlgorithm=replace（UPSERT）
- 查询: WHERE server_key=? AND kind=?
- 同步判断（versionedSnapshot 语义，非 delta 增量）: cached.version == current → 直接用快照；变化 → 全量重拉替换快照；后端不提供标记（`capabilities.versionedSnapshot=false`，如 Audio Station）→ 每次全量，如实降级
- 专辑 10000 上限对齐歌曲入口；大曲库分页待专辑列表页支持加载更多后再拆

### 7.2 lyrics_local

| 字段 | 类型 | 说明 |
|------|------|------|
| lookup_key | TEXT PK | 见下方键规则 |
| title | TEXT NOT NULL | 歌曲标题 |
| artist | TEXT NOT NULL | 歌手 |
| content | TEXT NOT NULL | LRC 文本 |
| created_at | INTEGER NOT NULL | 写入时间（epoch ms） |

- 键优先级（P0-09）: 服务器歌曲 `lyrics:{serverId}:{songId}` → 本地歌曲 `lyrics:local:{fingerprint}` → 兜底 `归一化标题|归一化歌手`（v4 前历史行全部为兜底键格式，保留可命中）
- 写入时同时落主键与兜底键（fingerprint 因 mtime 变化失效后仍可兜底命中）
- 读取: AppDb.loadLyrics(List<String> keys) 按序尝试

### 7.3 scrobble_queue（Pending Queue，非历史播放表）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK AUTOINCREMENT | 自增主键 |
| server_id | TEXT NOT NULL | 归属服务器（防串号） |
| song_id | TEXT NOT NULL | 歌曲 ID |
| played_at | INTEGER NOT NULL | 播放时间（epoch ms） |
| created_at | INTEGER NOT NULL | 入队时间（epoch ms） |
| retry_count | INTEGER NOT NULL DEFAULT 0 | 已重试次数 |
| last_error | TEXT | 最近一次失败原因（截断 200 字符） |
| next_retry_at | INTEGER | 指数退避到期时间；NULL=立即可发 |

- 写入时机: scrobble 触发条件命中（50% 或 2min 先到）且本次上报失败
- flush 时机: 启动 + 网络恢复事件
- flush 规则: WHERE next_retry_at IS NULL OR next_retry_at <= now，ORDER BY created_at ASC LIMIT 50
- 成功 → DELETE 行；失败 → retry_count+1，退避 1/2/4/8/16 分钟；超过 5 次移出队列（防永久阻塞）
- 无 `flushed` 字段（成功即删，队列本质是 pending queue）

### 7.4 play_history（真实播放历史，v6 新增）

与 §7.3 的区别：`scrobble_queue` 是**待补发的上报队列**（成功即删），本表是
**本地播放历史**（只增，供统计与 FM 去重）。读写逻辑见 §4.20。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK AUTOINCREMENT | 自增主键 |
| server_id | TEXT NOT NULL | 归属服务器（统计与 FM 排除均按当前服务器过滤） |
| song_id | TEXT NOT NULL | 歌曲 ID |
| title / artist / album / album_id | TEXT NOT NULL | **元数据快照**：歌曲从曲库删除后历史仍可读 |
| duration_ms | INTEGER NOT NULL DEFAULT 0 | 该次播放的音频时长（非播放进度） |
| played_at | INTEGER NOT NULL | 记录时间（epoch ms） |

- 索引：`idx_history_played(server_id, played_at)`——支撑「近 N 天」与分组统计查询。
- 写入时机：每次实际播放达到门槛 **20s 或时长一半（先到为准）**；时长 < 40s 的
  短音频按一半算。冷启动恢复（RESTORING）期间的 position 事件不算真实播放。
- 全后端统一记录：服务端无播放计数的 fnOS / Audio Station 也有统计。
- 裁剪：每 100 次插入触发一次 `DELETE WHERE id NOT IN (…ORDER BY played_at DESC
  LIMIT 20000)`，封顶 2 万行，防 DB 无限膨胀。
- 写入失败静默（`catch`）：**历史记录失败不影响播放**。

### 7.5 download_index

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK AUTOINCREMENT | 自增主键 |
| server_id | TEXT NOT NULL DEFAULT '' | 归属服务器 |
| song_id | TEXT NOT NULL | 歌曲 ID |
| fingerprint | TEXT NOT NULL UNIQUE | `sha256('$serverId\|$songId')[0:16]`（唯一索引 idx_download_fingerprint） |
| path | TEXT NOT NULL | 下载文件绝对路径（Music/ 下） |
| size | INTEGER NOT NULL DEFAULT 0 | 文件字节数 |
| created_at | INTEGER NOT NULL | 下载完成时间 |
| last_accessed_at | INTEGER NOT NULL | 最近反查命中时间 |
| payload | TEXT | Song 元数据快照（v5 加列；本地音乐列表合并展示已下载歌曲用） |

- **指纹必须含 serverId**：多后端下不同服务器可能给出相同数字 songId，仅用
  `sha256(songId)` 会让 A 服的下载被 B 服误命中。
- 旧指纹惰性迁移（无建表迁移、不批量改写）：升级前的行是 `sha256(songId)[0:16]`，
  目录兜底扫描时按 `_legacyAdoptable` 判定能否认领——**无记录（最早期下载）或记录
  归属本服务器/无归属**才可认领；已归属其他服务器的同 id 文件**不跨服共用**。
  索引不可用时保持旧行为（认领）。
- 反查: findDownloadedSong 先查索引（O(1)），File.exists 校验；文件丢失 → 懒修复（删失效记录）；索引未命中 → 目录指纹扫描兜底并回填索引
- 下载写入 .tmp 临时文件，校验后原子 rename，成功才登记索引；启动时
  `cleanupOrphanTmpFiles()` 清理 **超过 1 小时**的 `.tmp` 残留（进行中的下载不误伤），
  否则半截文件的指纹会被目录兜底扫描与本地扫描误匹配。

> 不存在的表：`local_scan_cache`（本地扫描缓存复用 library_snapshot）、
> `autoplay_queue`（运行时队列唯一 SoT 是内存态 QueueNotifier，不持久化）。
> 长音频断点（>10min）存 SharedPreferences key=`breakpoint_<songId>`，不属于 SQLite。

---

## 八、依赖库清单

> 具体版本以 `pubspec.yaml` 为唯一事实来源，本文只记录包、用途与消费点（P0-01）。
> 消费点列的是 **import 该包的源文件**（`lib/` 相对路径）——包被删或换实现时，
> 按这一列定位改造范围，而不是按记忆猜。

### 8.1 核心运行时：状态 / 播放 / 存储

| 包 | 用途 | 消费点 |
|----|------|--------|
| flutter_riverpod | 状态管理（Provider / NotifierProvider / FutureProvider / StreamProvider） | 全局 |
| just_audio | 音频播放引擎（AudioPlayer + LockCachingAudioSource 缓存源） | player_controller.dart、player_actions.dart、audio_handler.dart |
| just_audio_windows | Windows 播放内核（just_audio 的 Windows 平台实现） | 无 import，平台插件；`main.dart` 侧靠关掉 media_kit 的 windows 让位 |
| just_audio_media_kit | Linux 播放内核（libmpv），Android/iOS/Windows 不使用 | main.dart（`ensureInitialized(linux: true, windows: false)`） |
| media_kit_libs_linux | media_kit 的 Linux 原生库打包 | 无 import，纯打包依赖 |
| audio_service | 后台播放 + 通知栏 / 锁屏 / Android Auto / CarPlay 媒体会话 | audio_handler.dart、main.dart |
| audio_session | 音频焦点与输出设备类型（Android 打断恢复、蓝牙 a2dp 判定） | core/audio/audio_session_io.dart |
| sqflite | SQLite 本地数据库（version=6，5 张表） | app_db.dart、library_sync.dart、local_library.dart、scrobble_service.dart |
| sqflite_common_ffi | Windows/Linux 与测试环境的 ffi 驱动 | core/storage/db_factory_io.dart、`test/` |
| sqflite_common_ffi_web | Web 端 SQLite（WASM sqlite 跑在 worker） | core/storage/db_factory_web.dart |
| sqlite3_flutter_libs | 桌面端 sqlite3 原生库打包（DLL / SO） | 无 import，纯打包依赖 |
| shared_preferences | 轻量配置持久化（含设置快照、断点、搜索历史） | core/settings/*、core/theme/*、player_controller.dart 等 |
| flutter_secure_storage | 服务器 secrets（password / token / salt） | core/storage/auth_store.dart、server_repository.dart |

### 8.2 网络 / 数据 / 文件系统

| 包 | 用途 | 消费点 |
|----|------|--------|
| dio | HTTP 客户端（API 调用 + 媒体流 / 下载原子写入）；适配器与下载队列共用 | core/api/*、core/network/http_factory*、download_service_io/web.dart |
| web | 浏览器互操作（下载走 Blob / a[download]，无文件系统） | core/download/download_service_web.dart |
| cached_network_image | 封面图缓存与占位 | shared/cover_art.dart、action_sheets.dart、detail_screen.dart |
| flutter_cache_manager | 缓存句柄，供「清理图片缓存」一键清空 | features/settings/settings_screen.dart（`DefaultCacheManager().emptyCache()` + `CoverCacheManager().emptyCache()`） |
| http | 封面专用缓存管理器的 HTTP 服务（IOClient 包 HttpClient，连接池限 8） | shared/cover_cache.dart |
| crypto | SHA-256（下载指纹、Jellyfin/Emby/fnOS 鉴权）/ MD5（本地歌曲指纹） | download_service_io.dart、subsonic/fnos/mediabrowser adapters、local_library_io.dart、streaming_prefs.dart |
| connectivity_plus | 网络状态监听（Stream<ConnectivityResult>），驱动自动重连与 scrobble 补传 | main.dart、scrobble_service.dart、streaming_prefs.dart |
| path | 路径拼接与扩展名判断 | download_service_io.dart、app_db.dart、local_library.dart、platform/media_store_*.dart |
| path_provider | cacheDir / documentsDir / 各平台音乐目录 | download_service_io.dart、cache_manager_io.dart、platform/local_fs_io.dart、local_scan_dirs_*.dart |
| permission_handler | 存储 / 音频读取权限请求 | core/local/local_library_io.dart |
| package_info_plus | 版本号与 build 号（关于页、User-Agent） | features/settings/settings_screen.dart |
| audio_metadata_reader | 本地音频标签解析（扫描 isolate 内执行） | core/local/local_library_io.dart |

### 8.3 UI / 平台能力

| 包 | 用途 | 消费点 |
|----|------|--------|
| palette_generator | 封面取色，驱动播放页专辑毛玻璃底色 | features/player/album_tint.dart |
| dynamic_color | Material You 壁纸动态取色 | main.dart（`DynamicColorBuilder`） |
| image_picker | 自定义背景图选择 | features/settings/settings_screen.dart |
| file_picker | 手动导入本地歌词（`FileType.custom, ['lrc','txt']`）；无选择器实现的平台与 pickFiles 一起捕获走同一错误提示 | full_screen_player_lyrics.dart |
| share_plus | 歌曲 / 歌单系统分享 | features/player/action_sheets.dart |
| home_widget | Android 4x2 桌面播放小部件数据推送（iOS WidgetKit 未接） | core/widget/home_widget_sync.dart |
| flutter_displaymode | 高刷屏强制 120Hz，动画不掉帧 | core/platform/display_mode_io.dart |
| lpinyin | 中文歌曲/歌手拼音排序与拼音检索 | core/library/song_sorting.dart、home/library_entries_screen.dart |
| cupertino_icons | Cupertino 图标字体（无 import，纯字体） | — |

### 8.4 构建 / 测试（开发依赖）

| 包 | 用途 |
|----|------|
| flutter_test（SDK） | 单元测试 / widget 测试 |
| flutter_lints ^6.0.0 | 静态规则集，由根目录 `analysis_options.yaml` 激活 |

> **未使用的常见包，别按印象补**：无 `intl`（时间统一 `inMinutes:padLeft(inSeconds%60)`
> 内联格式化，日期统一 ISO8601 自解析，见 song_info_screen.dart）、
> 无 `flutter_localizations`（文案直接中文，无 ARB）、
> 无 `wakelock_plus`（不做常亮控制，省电策略见 §4.14.9）、
> 无 `integration_test`（只有 `flutter test` 的单元/widget 测试）。

---

## 九、已知问题与限制

### 9.1 播放侧

| # | 问题 | 影响范围 | 临时对策 |
|---|------|----------|----------|
| 1 | 单 AudioPlayer 无原生 crossfade，只能做音量渐变（Soft Transition：当前曲淡出→切源→下一曲淡入），不是双流重叠 True Crossfade | 所有平台 | crossfade_seconds = 实际淡化时长（0=关闭，1-10=秒）；实现为固定 100ms tick，步数随时长派生（seconds*1000~/100），无固定步数业务语义；禁止为 crossfade 引入第二个 AudioPlayer |
| 2 | 超长歌曲 >10min 的断点续播依赖 SharedPreferences | Android 前台 | breakpoint_<songId>，切歌/seek 时落盘，播放开始命中即跳转 |
| 3 | iOS 后台播放依赖 audio_service 的 MediaSession | iOS  Only | 锁屏控制已验证 OK |
| 4 | Subsonic API 的 getPlaylists 在某些实现（如 Ampache）不返回 owner 字段 | 歌单列表 | owner 兜底为空字符串 |
| 5 | 本地歌曲 ID v2.2 起从 local:{path} 迁移为 local:{fingerprint} | 本地音乐 | 升级后首次进入重新扫描生成新 ID；旧持久化队列中的歌曲靠 Song.path 仍可播放 |

### 9.2 适配器侧

| # | 问题 | 影响范围 | 临时对策 |
|---|------|----------|----------|
| 6 | Jellyfin fetchSongs 返回的 trackNumber 字段名为 track 而非 trackNumber | Jellyfin | Song.fromJson 回退: trackNumber ?? track |
| 7 | Plex 的 sampleRate 单位是 Hz，Subsonic 系是 kHz | 全局 | _sampleRateHz(j): raw < 1000 ? raw * 1000 : raw.round() |
| 8 | Audio Station 不提供 libraryVersion() | 版本快照同步 | versionedSnapshot=false → 每次全量拉取 |
| 9 | Navidrome 转码档位实际不可用（服务端缺 ffmpeg，无损曲目可播但转码流失败） | 流量/音质设置 | resolveStream 探测 + 播放失败自动回退无损原文件（player_source_resolver） |
| 10 | `albumId` 在 fnOS / Plex 是数字 id，跨服可同值 | 封面与小部件缓存 | 缓存键一律加服务器维度（`serverId\|albumId`），下载指纹见 §7.5 |
| 11 | 部分 Subsonic 实现忽略 `songOffset`，恒返同一页 | 全库枚举 | 分页去重 + 尊重 `start` 偏移 + 末页截齐（§4.10，快照 kind 已升 `songs_all_v2`） |

### 9.3 性能侧

| # | 问题 | 影响范围 | 临时对策 |
|---|------|----------|----------|
| 12 | 首次进入曲库无快照时须全量拉取（`songs_all_v2` 上限 10 万 / `albums_name_v2` 上限 1 万），慢网下可达数十秒 | 冷启动（仅首次） | 版本标记未变直接读 SQLite 快照免拉取；首页五分区另走 SWR 磁盘快照秒回（§4.19） |
| 13 | 专辑 4 列网格在数千张专辑的曲库上一次性构建会掉帧 | 资料库专辑页 | `GridView.builder` 懒构建 + `ScrollBottomLoader` 分页追加（loadMore），不做全量一次性 build |
| 14 | 大 JSON 快照（>256KB）主 isolate 解码会卡顿 | 曲库/本地库回放 | encode/decode 超阈值走 `runInIsolate`（web 无 isolate，直接算）；本地扫描结果 >1000 条同样后台编码 |
| 15 | 图片背景 + 玻璃模糊叠加在低端机上 GPU 压力大 | 所有玻璃表面 | 三档 `glassQualityProvider`（关闭/标准/增强）+ 全局「面板透明度」；装饰性循环动画挂 `powerSaveProvider`（§13） |

### 9.4 设备与移植侧

| # | 问题 | 影响范围 | 说明 |
|---|------|----------|------|
| 16 | MIUI 后台冻结会在调试中途切断 adb | 真机验证 | 现象是设备从 `adb devices` 消失；重插并重新授权即可，不要循环重试 |
| 17 | iOS / macOS / Linux / Windows 构建未在本机验证 | 桌面与 Apple 平台 | 代码侧已按平台条件编译（media_kit / just_audio_windows / ffi 驱动分工），缺构建环境；Windows 先行 |
| 18 | 鸿蒙依赖 flutter_ohos 生态，尚未跟进 | ohos | 播放与后台链路是共同缺口，等平台侧成熟（§15.7） |
| 19 | 桌面小部件仅 Android（`LiusoundWidgetProvider`） | 小部件 | iOS WidgetKit 需原生扩展，未接；非 Android 平台 `HomeWidgetSync.push` 直接 return |

---

## 十、版本历史

| 版本 | 日期 | 变更摘要 |
|------|------|----------|
| v2.0 | 2026-09-01 | 初始代码梳理：6-backend adapter layer + Riverpod state management |
| v2.1 | 2026-09-04 | Liquid Glass UI system + 5 themes via SkinTokens ThemeExtension |
| v2.1.1 | 2026-09-05 | 资料库复用修复：歌曲入口→全部歌曲倒序 / 歌单切换 / 专辑 4 列网格 |
| v2.1.2 | 2026-09-06 | 设置页 tab 内层 AppBar 移除 / 本地扫描 isolate + SQLite 缓存 / 迷你条双语下一句 |
| v2.2.0 | 2026-09-07 | 架构一致性 P0 整改：DB v4 迁移（scrobble 重试防护 + download_index）/ 下载原子写入 / 本地歌曲指纹 ID / 歌词缓存键分级 / Player Restore 严格顺序 / incrementalSync→versionedSnapshot 正名 / Unsupported-Failure 语义分离 / Invariants & Anti-Patterns 章节 |
| v2.3.0 | 2026-09-07 | 架构一致性 P1 整改：PlayerActions 七 part 拆分（行为零变化）/ Shuffle 全队列遍历序 + 游标 / Crossfade 100ms tick 语义统一 / NetworkSettings 显式注入（去 global mutable）/ AppError sealed 错误模型 / MotionTokens / AutoDownload 触发归属业务层 / 平台能力矩阵（§15） |
| v2.4.0 | 2026-09-17 | **代码侧**：遗留问题清零 + 后台下载队列 + 下载落公共音乐目录 / 首页五分区 SWR 快照（磁盘秒回）/ 搜索历史与空态 / 设置二级页顶栏不透明 + 弹层透明度收口 / 服务器编辑（新凭证完整验证）/ 动效升级（皮肤舞台 Lissajous 漂移 + 星点闪烁、播放页级联入场与 Tab 缩放联动、封面 punch-in + 扫光、唱片呼吸光晕、播放键 morph + 脉冲、PopOnChange、列表错峰）+ 全部循环动画挂省电门 / 切歌取色连续性（沿用上一首 + 莫奈兜底）/「卡片透明度」更名「面板透明度」/ 二级列表页 AmbientScaffold 统一固定顶栏。**文档侧**：第六~九、十一~十二、十五章按代码逐条重核——依赖表改为「包/用途/消费点」并删除不存在的包，§4.10 更名「曲库版本快照同步」并改对 `_load` 回退链，§12 全章替换为真实回退路径（原引用的 `showEmpty`/`RetryConsumer`/`UnsupportedDialog`/`resizeableActivity` 等均不存在），§13 新增视觉不变量 20–25 与对应反模式，§15.4 补全 13 个时长 token，§15.7 平台矩阵改为 7 平台并修正小部件/Auto 状态 |

---

## 十一、设计参考

### 11.1 历史设计素材（不入库）

`UI/` 目录曾用于存放竞品/方向截图并驱动逐屏对齐。**2026-09-11 起 `UI/` 已列入 `.gitignore` 且从 git 历史中清除，仓库内不存在这些文件**，下表仅作设计决策的历史溯源保留，不能作为当前 UI 依据：

| 历史文件 | 对应页面 | 当时的关键设计决策 |
|------|----------|-------------|
| UI/资料库.jpg | 资料库首页 | 顶部导航（歌曲/专辑/歌手/歌单）+ 网格入口 |
| UI/播放界面.jpg | 播放详情页 | 全屏封面 + 滚动歌词 + 底部控制面板 |
| UI/评分.jpg | 评分交互 | 五星点击 + 颜色填充（空心→实心） |
| UI/浮动歌词.jpg / 1 / 2 | 浮动歌词 | 半透明浮窗 + 透明度/字号/位置调节 + 版权保护模式 |
| UI/选曲单.jpg | 播放队列 | 列表式 + 删除手势 + 清空按钮 |
| UI/翻译.jpg | 双语歌词 | 原文/翻译交替显示 + 颜色区分 |
| UI/滚动效果.jpg / 2 | 滚动歌词、专辑详情 | 随滚动进出的行级动画 |
| UI/隐藏键盘.jpg | 通用交互 | 输入完成即 `FocusScope.unfocus()` |

> **当前视觉的唯一权威来源是第六章**（主题与视觉系统）。本节与第六章冲突时，一律以第六章为准。
> 另需注意：2026-09-10 的「去卡片化」决策后，浏览类页面默认裸排（`cardDisplayProvider` = false），玻璃材质只保留在悬浮表面上。

### 11.2 设计令牌（以代码为准）

所有视觉属性必须来自令牌，不允许在页面里手写色值与尺寸（§13）。定义位置：`lib/core/theme/app_theme.dart`、`skin_tokens.dart`、`motion_tokens.dart`。

| 体系 | 实际取值 |
|------|----------|
| 间距 `AppSpacing` | xs=4 / s=8 / m=12 / l=16 / xl=24 / xxl=32 / xxxl=48（异步态留白）/ huge=64（滚动尾部安全区） |
| 圆角 `AppRadius` | s=8 / m=12 / l=16 / xl=24 / xxl=32 / pill=999；皮肤可用 `radiusScale` 整体缩放 |
| 字阶 `AppText`（const 上下文用） | h1=28/w700 · h2=22/w600 · h3=19/w500 · body=16 · aux=14 · caption=12；Widget 内优先 `Theme.of(context).textTheme` 对应槽位 |
| 语义色 `SkinTokens` | 20 字段（background / shell / detailBg / surface / divider / glassTint / tintLight / borderTop / borderBottom / borderHairline / shadowColor / textDim / textFaint / textPrimary / glow / blurScale / blurEnabled / highlightStrength / radiusScale / language），经 `SkinTokens.of(context)` 读取，随皮肤切换 |
| 点缀色 `AppTheme` | 与皮肤无关、保持 const：indexGreen `0xFF3EC06C` / accentSoft `0xFF9EC1F0` / heartRed `0xFFE57373` / actionBlue `0xFFB2D7F7` / ratingGold `0xFFFFC53D`，以及音质徽标三档色板 |
| 动效 `MotionTokens` | 13 个时长 + 3 条曲线，见 §15.4；禁止在页面里写裸 `Duration(...)` 表达"标准过渡"这类语义 |

交互与无障碍底线：

1. **对比度**：正文 ≥ 4.5:1；`AppText.caption` 的浅灰只用于非关键辅助信息。
2. **可点区域**：列表行与图标按钮以整行为单位扩加热区，不依赖图标自身尺寸。
3. **状态完备**：可交互元素至少覆盖 idle / pressed / disabled；禁用态降透明度而非换色。
4. **循环动画必须挂省电门**（`powerSaveProvider`），详见 §13；一次性入场/过渡动画不受此限。
5. **动效服务于识别**，不做无意义的弹跳/旋转（§6.8）。

---

## 十二、边界情况与回退策略

本章逐条对应真实代码路径；写"回退"一栏时给的是实际执行的文件/方法，便于回归定位。

### 12.1 网络与服务器异常

| 场景 | 表现 | 回退（实际实现） |
|------|------|------|
| 离线 + 有库快照 | 曲库正常展示（可能偏旧） | `library_sync._load`：`libraryVersion()` 5s 超时 → `current == null` → 命中 `cachedPayload` 直接解码 |
| 离线 + 无快照 | 页面进错误态，可下拉重试 | `_load` 兜底也没有快照时**重新抛出**；不立即发起第二次全量请求（弱网下只会加倍等待） |
| 版本标记查询超时但网络半通 | 用快照，不做全量拉取 | 同上：`current == null \|\| current == cachedVersion` 即返回快照 |
| 快照写库失败 | 数据显示正常 | 落库单独 `try/catch`，**不吞掉已成功的 fetch 结果**，快照留待下次进入补写 |
| 首页模块冷启动 | 先回放缓存再后台刷新 | §4.19 SWR 快照：有缓存就不转圈，刷新失败保留旧数据 |
| Token 失效（401） | 用户无感继续 | `ReauthInterceptor`（`QueuedInterceptor`）：`extra['liusoundReauthRetried'] != true` → `reauthenticate()` → `applyFreshCredentials(opts)` → 重放 `dio.fetch(opts)`；重登失败才回落原始 401。MediaBrowser 改 header、Plex 改 query |
| 听歌排行上报失败 | 用户无感 | `scrobble_queue` 表排队 + 指数退避补发（1/2/4/8 分钟，`_maxRetries = 5`）；超过上限删行放弃 |
| 服务端转码档位不可用 | 仍能播放 | 见 §12.3 播放侧回退 |

### 12.2 数据异常

| 场景 | 表现 | 回退（实际实现） |
|------|------|------|
| `Song.title` / `artist` 缺字段 | 显示"未知歌曲"/"未知歌手" | `Json.str(j, 'title', '未知歌曲')`（`abstract final class Json` 的 `str/strOf/intOf/boolOf`） |
| 新版 Navidrome `/api/album` 移除 `artist`/`artistId` | 专辑仍有艺人 | `Json.strOf(j, ['name','title','album'], '未知专辑')` 多键回退链 |
| `maxYear` 与 `year` 并存 | 优先 `maxYear` | `year: (j['maxYear'] as num?)?.toInt() ?? (j['year'] as num?)?.toInt()` |
| 封面拉取失败 / albumId 为空 / 本地封面文件被清理 | 显示默认专辑图 | `CoverArt`：`assets/app/default-album.png` 占位；网络分支 `CachedNetworkImage` 的 placeholder，本地分支 `errorBuilder: (_,_,_) => placeholder` |
| 歌词 JSON/LRC 解析失败 | 歌词区显示空态，不崩 | `parseLyricsData` 失败返回空数据；`parseLyricsTracks` catch → `const []`；`parseLrcText` 无法解析时间行 → 空列表 |
| 曲库快照 payload 损坏 | 退回实时拉取 | `_decodePayload` 抛错被 `_load` 外层捕获，走 fetch 分支 |

### 12.3 播放异常

| 场景 | 表现 | 回退（实际实现） |
|------|------|------|
| 转码流不可用（服务端缺 ffmpeg） | 实际以无损播放 | `player_source_resolver`：`if (!hint.transcode)` 之外，转码源失败后 try/catch 回退原始流；Navidrome 档位问题见 §9.2 |
| 播放源整体失败 | Toast「播放失败，请检查服务器连接」 | `player_source_resolver._notify(...)`，命中后进入 error 态，保留当前队列 |
| 本地文件不可读（被外部删除/权限收回） | Toast「本地文件播放失败：文件不可读」 | 同上 `_notify`，随后走一次网络源回退 |
| 切歌竞态（旧请求晚到） | 只认最后一次 | `_playGeneration` 代数守卫：回调内 `gen == _playGeneration` 才落地 |
| 失败前已缓存的播放进度 | 进度可能丢失 | `_pendingResumeMs` 一次性消费语义，属已知可接受权衡（代码内有注） |
| 冷启动恢复播放态 | 短暂占位后正常 | Player Restore 严格顺序 `RESTORING → 绑定 → READY`（§13） |
| 下载中断 | 队列内标红可重试 | `download_queue`：`_patch(status: failed, error: '下载失败')`，「重试失败任务」重建为干净等待态；`.tmp` 不会被认为有效最终路径（§13） |

### 12.4 权限异常

| 场景 | 表现 | 回退（实际实现） |
|------|------|------|
| Android 音频权限未授予 | 本地扫描结果为空并提示 | `ensureAudioPermission()`：先 `Permission.audio.request()`，被拒回退 `Permission.storage.request()`（兼容 Android ≤ 12）；非 Android 直接 `return true` |
| 悬浮歌词无系统权限 | 入口仅 Android 可见 | `FloatingLyrics.supported => AppPlatform.isAndroid`；`hasPermission()` 为假时不启动；iOS 无对应能力，设置入口隐藏 |
| 后台播放被系统回收 | 通知栏控制缺失 | Manifest 已声明 `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`、`WAKE_LOCK`，`AudioService` 的 `foregroundServiceType="mediaPlayback"` |
| MIUI 冻结 adb/进程导致调试断连 | 设备侧连接掉线 | 见 §9.4：**不要循环重试**，需要物理重插 |

### 12.5 平台差异

| 能力 | Android | iOS / iPadOS | Web | Windows / Linux | HarmonyOS (ohos) |
|------|---------|--------------|-----|-----------------|------------------|
| 播放内核 | just_audio | just_audio | just_audio（`just_audio_web` 平台实现，随主包间接引入） | just_audio；Windows 走 `just_audio_windows`（main.dart 显式关掉 media_kit 的 windows） | just_audio（依赖上游 ohos 适配） |
| 浮动歌词 | 支持（`MethodChannel com.silencetop.liusound/floating_lyrics`） | 不支持，入口隐藏 | 不支持 | 不支持 | 不支持 |
| 本地音乐扫描 | 支持（`Isolate.run` + 权限申请） | 支持（沙盒目录，见 `local_scan_dirs` 各平台实现） | 不支持（`local_library_web`） | 支持 | 目录由 `local_scan_dirs_ohos` 提供 |
| 下载落盘 | 公共音乐目录，失败回退私有 Documents/Music | 应用容器 | 不适用（`download_service_web`） | 公共音乐目录（Windows）/ 用户目录（Linux） | 同桌面路径策略 |
| 数据库 | sqflite（平台通道） | sqflite（平台通道） | `sqflite_common_ffi_web` WASM 工厂（worker `web/sqflite_sw.js` 由 `:setup` 生成并入库） | `sqflite_common_ffi` | sqflite（依赖上游 ohos 适配） |
| 桌面小部件 | 已实现：`.LiusoundWidgetProvider` + `@xml/liusound_widget_info`；`HomeWidgetSync.push` 在非 Android 直接 return | 未实现 | 未实现 | 未实现 | 未实现 |
| 系统级播控 | 通知栏 + MediaBrowser（Android Auto 侧为**部分支持**：`MediaBrowserService` + `playFromMediaId` 已声明，但未提供 `automotive_app_desc`，车机入口不保证出现） | 锁屏 / 控制中心（audio_service） | 浏览器媒体键 | 依赖上游平台实现 | 依赖上游平台实现 |
| 刷新率档位（省电） | 支持：`FlutterDisplayMode.setLowRefreshRate/setHighRefreshRate`，幂等（`_lastDisplayPowerSave` 未变化不重设） | 无（`applyDisplayPowerSave` 有 `AppPlatform.isAndroid` 守卫，非 Android 直接 return） | 无（`display_mode_web.dart` 是 no-op） | 无 | 无 |
| 深色/浅色 | 系统级 | 系统级 | 系统级 `prefers-color-scheme` | 系统级 | 系统级 |

> 分屏/窗口化：**未在 Manifest 声明 `android:resizeableActivity`**，也不存在 `automotive_app_desc`。此前文档中"支持分屏（resizeableActivity=true）"的描述无代码依据，已删除；如需平板分屏适配需先在 `AndroidManifest.xml` 显式声明并实测。

---

## 十三、Architecture Invariants（架构不变量，P0-18）

任何新增代码必须遵守；违反即为 bug，review 时应拒绝合并。

1. UI 不直接访问 Dio / SQLite / SharedPreferences / 文件系统
2. Provider / Controller 不负责长时间 IO（大扫描、全量拉取、整文件 hash）
3. Adapter 不依赖 Flutter Widget；不负责 UI 状态
4. Repository 是 SQLite 访问唯一入口（当前收敛点：AppDb）
5. PlayerActions 是 AudioPlayer 唯一 owner；全库只允许一个 AudioPlayer 实例
6. QueueNotifier（queueProvider）是运行时播放队列唯一 Source of Truth；禁止第二个队列状态源（无 autoplay_queue 表）
7. 状态归属：position/playing/duration → AudioPlayer；currentSong → currentSongProvider；queue → queueProvider；settings → 各 settings provider；server session → AuthController；remote library → LibrarySync 版本快照；local library → local_library 快照；download → download_index
8. Local Song ID 必须基于稳定 fingerprint（local:{md5(size+mtime+头16KB+metadata)}）；Server Song ID 与 Local Song ID 通过 local: 前缀命名空间隔离
9. Unsupported（null/能力开关关闭）/ Empty（空列表）/ Failure（异常）三种语义必须分开，不得用 null 同时表达
10. Cache（temp/just_audio_cache，LRU 可回收）与 Download（docs/Music，长期保存）目录、容量治理完全分离；AutoDownload 不得触发 AudioCache.enforceLimit
11. 单 AudioPlayer 上的 crossfade 只允许音量渐变（Soft Transition）；禁止双流重叠/第二个 AudioPlayer
12. 数据库 migration 只允许 ADD COLUMN / CREATE TABLE；破坏性操作仅限可再生缓存且注释说明
13. 下载必须 .tmp + 校验 + 原子 rename + 索引登记后才算可用
14. 后台任务（扫描/同步/下载/flush）必须有 running guard 与防重入；跨服务器异步结果写入前确认 serverId 仍有效
15. 大 JSON 快照（>256KB / >1000 条）的 encode/decode 必须在 Isolate.run 中执行
16. Player Restore 严格顺序：RESTORING → 绑定事件 → READY；READY 前禁止自动播放/切歌/自动下载/上报
17. 业务 UI 不允许硬编码 Color(...)；纯装饰与 Canvas painter 内部除外
18. 不新增 global mutable singleton（P1 已消除 NetworkRuntime.settings 全局可变状态：NetworkSettings 经 createAdapter 构造参数显式注入各 adapter；同类全局可变状态禁止再出现）
19. Feature 内不得直接创建 Dio / SQLite 实例
20. 无限循环装饰动画必须受省电门控制：启动前读 `powerSaveProvider`，并 `ref.listen` 该 provider 以在切换时 `stop()/repeat()`（现有实现：`glass.dart` 的 `_syncLoops`、`full_screen_player_now_playing.dart` 的 `_syncAnimations` 唱片旋转、`full_screen_player_bottom.dart` 的呼吸光环）。一次性入场/过渡不受此限，但时长统一经 `AppMotion.duration` 压缩（§15.4）
21. 全屏播放页**不与皮肤/玻璃系统关联**（硬规则，commit 8fe1748）：播放页表面一律取封面主色的 `AlbumFrostedPanel`（`features/player/album_tint.dart`），不走 `GlassSurface`、不吃 `SkinTokens.glassTint`。唯一例外 `_SquareCover` 的黑胶边框为定稿视觉（611b9fa 冻结，不再随手改）。切换皮肤不得改变播放页任何表面材质
22. 自定义图片背景（`backgroundProvider`）优先级最高：设置图片后，皮肤背景色与玻璃 tint 退让为其让位；档位（`GlassLevel`）只决定模糊强度，面板透明度（`glassTintOpacityProvider`，0.2–1.0）全局所有皮肤生效，二者不得混用为一个开关
23. 浏览类页面默认裸排（`cardDisplayProvider` = false）：卡片/玻璃只用于真正悬浮于内容之上的表面（迷你条、弹层、对话框、吸顶栏）。禁止卡片套卡片；面板内部分区用间距/字阶/左边框表达
24. 视觉属性一律取 token：颜色 → `SkinTokens` / `AppTheme` 点缀色；间距 → `AppSpacing`；圆角 → `AppRadius`；字阶 → `AppText` 或 `textTheme` 槽位；时长与曲线 → `MotionTokens`。不变量 17 是颜色子集，本条覆盖尺寸与动效
25. 零等待体验：有快照/缓存的数据页首帧必须先回放本地数据再后台刷新，不得以转圈阻塞或先清空（§4.19 SWR、§4.10 版本快照、§12.1 回退链）

## 十四、Anti-Patterns（禁止模式，P0-19）

- Widget 中调用 Dio / SQLite / SharedPreferences
- Provider 中进行无限/长时间扫描
- 多处创建 AudioPlayer，或创建第二套 queue state
- 使用文件路径作为 Local Song ID
- Cache / Download 混用目录或容量限制
- shuffle 模式只换随机起始曲而不完整遍历队列（P1 起 shuffleOrderProvider 为全队列随机遍历序 + 游标，一轮内不重复；修改遍历逻辑必须同时保证 nextSongProvider 预测 == 实际播放）
- UI 错误分类基于 Exception.toString() 字符串匹配（必须 catch core/errors/app_error.dart 的 AppError 具体子类）
- catch (_) 后把请求失败折叠成 null（=不支持）
- Capability=false 后仍假定能力存在
- 新增 global mutable singleton
- 业务组件硬编码 Color(...)
- 为了拆 Adapter 引入巨大 Domain Layer / 复杂状态机 / 任务调度中心 / Event Sourcing
- 大规模一次性重命名文件、修改依赖版本、删除数据而无 migration
- `AnimationController` 未接 `powerSaveProvider` 就 `repeat()`（对应不变量 20）
- 播放页新增 `GlassSurface` / 直接读 `SkinTokens` 做背景，或把 `_SquareCover` 黑胶框当"顺手优化"改掉（21）
- 把「玻璃档位」与「面板透明度」合并成一个开关，或让透明度只作用于 liquidGlass 一档（22）
- 浏览页给列表分组套 Card、或在 Card 内再套 Card（23）
- 页面里写裸 `Color(0x…)` / 裸 `fontSize` / 裸 `Duration(milliseconds:)` 来表达已有语义的属性（24，遗留清单见 §15.4）
- 数据页 `await` 全量网络请求后才出首帧，或刷新失败时清空已有列表（25）

---

## 十五、P1 架构整改补充（v2.3.0；§15.4 / §15.7 于 v2.4.0 重核）

### 15.1 PlayerActions 拆分（P1 渐进式）

`player_controller.dart` 保留全部 Provider 状态源与 `playerActionsProvider` 门面（外部导入路径不变），类体按职责拆为 part 文件：

| 文件 | 职责 |
|------|------|
| player_actions.dart | PlayerActionsBase（共享私有状态）+ 事件绑定 / 初始化 / 播放上一首下一首 / shuffle 遍历序 / 队列管理 / stop |
| player_source_resolver.dart | play()（源解析、音质档、转码探测、无损回退、断点续播） |
| player_error_handler.dart | _notify / _debugLog |
| player_breakpoint.dart | >10min 超长曲断点落盘与续播 |
| player_persistence.dart | 播放状态持久化（500ms debounce，仅 _restored 后） |
| player_restore.dart | 冷启动恢复（RESTORING → bind → READY 严格顺序） |
| player_crossfade.dart | 100ms tick 音量渐变 Soft Transition |

约束：mixins 声明为 `on PlayerActionsBase`（链式依赖需列出前置 mixin）；mixins 私有成员可见性依赖 part 同库，禁止跨文件以 `PlayerActions.` 形式调用私有成员（静态成员需 `PlayerActionsBase._x` 限定）。

### 15.2 Shuffle 遍历序（shuffleOrderProvider）

`ShuffleOrderState(order, pos)`：order 为全队列歌曲 ID 的随机遍历序，pos 为当前歌在 order 中的游标。

- playNext：游标 +1；到轮末重新洗牌一轮（排除当前曲作轮首）
- playPrevious：游标 -1；轮首不动
- 队列增删 → _syncShuffleOrder 增量维护（移除 ID 顺延游标，新 ID 随机插入当前游标后）
- nextSongProvider 预测 = order[pos+1]，与实际播放严格一致
- 遍历序随 player_state 持久化（shuffleOrder + shufflePos）：冷启动恢复时剔除已不在队列中的 ID，游标对齐当前歌

### 15.3 AppError 错误模型（core/errors/app_error.dart）

`sealed class AppError implements Exception`，子类：NetworkError / AuthError / UnsupportedFeatureError / NotFoundError / PermissionError / StorageError / PlaybackError / ServerError。adapter 层认证/服务器异常已抛 AppError。UI 展示统一走 `appUserMessage(error)`（同文件）：AppError 读 message、SocketException/TimeoutException 映射网络文案、其余给安全兜底，禁止把原始异常串暴露给用户（已接入：登录页、服务器连接检测）。

### 15.4 MotionTokens（core/theme/motion_tokens.dart）

`abstract final class MotionTokens` 静态动效 token（对齐 AppSpacing/AppRadius 风格）。页面转场 / 弹层 / MiniPlayer / 淡入淡出 / AnimatedSize / 列表入场一律取值于此，禁止散落 Duration/Curve 字面量。

**通用时长（3）**

| Token | 值 | 用途 |
|------|------|------|
| durationFast | 150ms | 微反馈 |
| durationNormal | 250ms | 默认过渡 |
| durationSlow | 400ms | 较慢的显著变化 |

**场景时长（10）**

| Token | 值 | 用途（源码注释） |
|------|------|------|
| durationTransition | 300ms | 页面转场（fadeRoute）/ 跟手落位 / 歌词自动滚动 / 封面淡入 |
| durationSnappy | 220ms | 快速反馈类小动画（转场退场 / 导航指示条） |
| durationCoverFade | 350ms | 封面切换淡入（全屏唱片档） |
| durationAmbient | 600ms | 氛围/背景类大渐变过渡 |
| durationEntrance | 320ms | 列表项入场（FadeSlideIn） |
| durationPop | 380ms | 图标状态切换弹跳（PopOnChange） |
| durationPulse | 320ms | 播放键点击扩散脉冲 |
| durationHalo | 2400ms | 播放键呼吸光环循环周期 |
| durationAmbientLoop | 26s | 背景光斑漂移循环周期（Lissajous 一整圈） |
| durationTwinkle | 4s | 深空星点闪烁循环周期 |

**曲线（3）**：`curveStandard = Curves.easeOutCubic` / `curveEmphasized = Curves.easeInOutCubicEmphasized` / `curveDecelerated = Curves.easeOutCirc`。

**省电联动**：`AppMotion.duration(context, base)`（`shared/widgets/motion.dart`）在省电模式下把基准时长压到 **40%**，保留过渡反馈同时降 GPU 压力；无限循环动画另有独立开关门（不变量 20）。

已落地：motion.dart 转场/入场曲线、app_shell.dart 翻页曲线、cover_art.dart fadeIn 时长（精确值替换，行为零变化）。**迁移遗留**：`lib/` 内仍有 16 处裸 `Duration(milliseconds:)` 字面量（120/200/250/260/280/300×2/400/420×2/500/600/900/950/2500ms），其中部分是一次性业务时序（如 debounce、进度轮询）而非动效，不能机械并入 token，需逐处判定。

### 15.4.1 SettingsRepository 裁量说明

不引入独立 SettingsRepository 抽象层：所有设置已通过各 settings Notifier provider 中转读写，UI 不直连 SharedPreferences（不变量 1 已满足）；直连 prefs 的仅运行时状态（播放状态/断点/转码探测缓存），属持久化而非「设置」。再抽一层只有间接成本、无行为收益。

### 15.5 NetworkSettings 显式注入

见 §4.15 与 §13 不变量 18：`createAdapter(config, secrets, [networkSettings])`，serverAdapterProvider watch 网络设置变更即重建 adapter。

### 15.6 AutoDownload 触发归属

触发点收敛于业务层（main.dart / 收藏成功），播放器不负责：① serverAdapterProvider null→非 null；② 网络切至 Wi-Fi；③ 收藏成功回调。见 §4.8.4。

### 15.7 平台能力矩阵（Platform Capability Matrix）

目标是 7 个平台（Android / iOS / macOS / Windows / Linux / Web / 鸿蒙 ohos）。**运行时能力差异见 §12.5**，本节只列系统集成侧：

| 能力 | Android | iOS | macOS | Windows | Linux | Web | ohos |
|------|---------|-----|-------|---------|-------|-----|------|
| 后台音频 | `AudioService` 前台服务（`foregroundServiceType="mediaPlayback"`） | `UIBackgroundModes: audio`（Info.plist 已声明） | audio_service | audio_service | audio_service | 浏览器策略决定（切后台可被挂起） | 依赖 flutter_ohos 上游 |
| 锁屏/通知控制 | `MediaStyle` 通知 + `MediaButtonReceiver` | 锁屏 Now Playing | 系统媒体键 | 系统媒体键 | 依赖上游 | 页面 Media Session | 依赖上游 |
| 车机 / 车载投送 | **部分**：`MediaBrowserService` 与 `android.media.browse.MediaBrowserService` intent-filter 已声明，`audio_handler` 实现了 `getChildren` / `playMediaItem` / `playFromMediaId`（可浏览亦可点播，`playFromMediaId` 正是为修「能浏览不能点播」而补）；但**未提供 `automotive_app_desc`**，Auto 入口不保证出现 | 无 CarPlay 集成（未引入 CarPlay 插件/entitlement），仅锁屏控制 | — | — | — | — | — |
| 浮动歌词 | 支持（`SYSTEM_ALERT_WINDOW`，Manifest 已声明） | 不支持，入口隐藏 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| 桌面小部件 | **已实现**：`.LiusoundWidgetProvider` + `@xml/liusound_widget_info`，Dart 侧 `HomeWidgetSync.push`（`updateWidget(name: 'LiusoundWidgetProvider')`） | 未实现（`HomeWidgetSync.push` 在非 Android 直接 return） | 未实现 | 未实现 | 未实现 | 未实现 | 未实现 |
| Material You 动态取色 | `DynamicColorBuilder`：仅 `AppSkin.materialYou` 且用户未显式选色时以 `darkDynamic.primary` 为主色（main.dart） | 不适用 | 不适用（该皮肤在桌面端不取动态色） | 同左 | 同左 | 同左 | 不适用 |
| 刷新率档位 | `FlutterDisplayMode.setLow/HighRefreshRate`（省电） | 无（`AppPlatform.isAndroid` 守卫直接 return） | 无 | 无 | 无 | 无（no-op 实现） | 无 |
| 沙盒文件访问 | `READ_MEDIA_AUDIO`（≤32 回退 `READ_EXTERNAL_STORAGE`） | 应用容器 + Documents 对「文件」App 可见 | `assets.music` / `downloads` / `user-selected.read-write` 等 entitlement 已声明 | 用户目录 | 用户目录（沙盒外） | 不适用 | 依赖上游 |
| 本机构建验证状态 | 已实测（Redmi 2203121C） | 未本机验证 | 未本机验证 | 未本机验证 | 未本机验证 | 真浏览器冒烟已过 | 未验证（等 flutter_ohos 生态） |

> 修正记录：v2.3.0 及更早的矩阵把「桌面小部件」「Android Auto」记为**未实现**，并给出「分屏 `resizeableActivity=true`」。两者与代码不符——小部件两端（Manifest Provider + Dart 推送）均已落地，Auto 侧是**已实现服务但缺 `automotive_app_desc`**；`AndroidManifest.xml` 中**不存在** `resizeableActivity`。v2.4.0 起以本表为准。

---

**覆盖级别**: 全量代码逐个字段/方法/枚举/参数/边界情况级细节

**文档版本**: v2.4.0
**生成日期**: 2026-09-07
**最后校对**: 2026-09-17 —— 对齐 CHANGELOG 2026-09-08→09-17 全部批次与 lib/ 当前源码逐条重核（第六~九、十一~十二、十五章）。已修正的文档漂移：依赖表按真实 import 重写、§4.10 版本快照回退链、§12 全章边界回退、§15.4 动效 token 全集、§15.7 平台矩阵；`UI/` 素材与其中不存在的符号（`showEmpty` / `RetryConsumer` / `UnsupportedDialog` / `resizeableActivity` 等）已从依据中移除。

## 十六、元数据插件系统（外部头像 / 相似歌曲 / 歌手简介）

### 16.1 动机与形态

相似歌曲与歌手简介此前完全依赖音乐服务器自身元数据（仅 Navidrome/Subsonic 原生支持，且 Navidrome 需服务端配置 Last.fm 凭据），其余后端分区直接隐藏。元数据插件把这三类取数外置为可独立开发、可导入的声明式插件：**插件 = JSON 描述（HTTP 端点 + 提取路径 + 可选 key 注入），不含可执行代码**；官方模板与用户导入的第三方描述走同一条执行管道（受 DeepSeek Cordis「声明式组件加载」思路启发）。

### 16.2 组成（lib/core/metadata/）

| 文件 | 符号 | 职责 |
|------|------|------|
| metadata_plugin.dart | `MetadataPlugin` | 契约：`fetchArtistAvatar` / `fetchSimilarArtistNames` / `fetchArtistBio`；失败一律返回 null/空列表 |
| plugin_descriptor.dart | `PluginDescriptor.parse` / `AuthSpec` / `FetchStep` / `SimilarStep` / `BioStep` / `extractJsonPath` | 描述 v1 schema 解析校验 + 点分提取路径（数字段=下标、`*`=数组通配、`\|` 分隔备选取首个非 null；bio 支持两步流 `idPath`+`fetchUrl`） |
| plugin_executor.dart | `DescriptorPlugin` / `JsonFetcher` / `dioJsonFetcher` | 描述执行：占位符 `{artist}`（URL 编码）/`{id}`（两步流）、auth query/header 注入、required 无 key 短路、bio HTML 清洗与 maxLength 截断 |
| metadata_store.dart | `MetadataStore` / `PluginState` | prefs：全局开关、官方停用项、导入描述、结果缓存；secure storage：插件 key（`metadata_plugin_key_<id>`） |
| metadata_orchestrator.dart | `officialPluginAssets` / `metadataEnabledProvider` / `pluginDioProvider` / `pluginRegistryProvider` / `pluginKeysProvider` / `pluginCapsProvider` / `pluginArtistAvatarProvider` / `pluginArtistBioProvider` / `pluginSimilarNamesProvider` / `InstalledPlugin` | 编排与 Riverpod 装配 |

schema 硬约束：所有端点强制 https；`id` 限 `[a-z0-9_-]{1,64}`；描述至少含 avatar/similar/bio 一节。

### 16.3 编排规则

- **注册表顺序**：官方（assets/plugins/deezer.json → theaudiodb.json → baike.json）→ 用户导入；取数按序取第一个有结果者
- **必败短路**：`auth.required` 且 key 未填的插件跳过，不打请求
- **能力派生**：`pluginCapsProvider`（avatar/similar/bio 三位）= 全局开 && 任一启用插件具备该节且非「required 无 key」；UI 据此解锁播放页分区（Jellyfin/Emby/Plex/Audio Station/fnos 原生缺失后端同样受益）
- **结果缓存**（prefs `metadata_cache_v1`，按歌手名）：头像 URL 30 天 / 简介 7 天 / 「确认无结果」负缓存 7 天；写队列串行防覆盖。头像图片本体复用 CoverCacheManager
- **网络**：插件请求走 `pluginDioProvider`（复用 NetworkRuntime 的用户代理/超时/证书配置）；全局开关关闭时不发起任何外部请求

### 16.4 相似歌曲的本地映射（播放约束）

外部相似结果不可直接播放（外部曲库引用 ≠ 本地 Song），故编排为：插件取**相似歌手名列表** → `_normalizeArtistName`（去空白+小写）映射回 `artistsProvider` 本地曲库 → 对每个命中歌手 `fetchArtistSongs(limit: 3)`、总量 12 上限。名字脚本不一致（如本地中文标签 vs Deezer 英文名）的歌手映射不上，自然降级不出现在结果中。

### 16.5 接线点

| 面 | 位置 |
|----|------|
| 头像 | `EntityCover(artistName:)` → `_EntityFallbackCover` 插件头像优先、专辑封面次之（歌手列表/搜索行/SongListScreen 头部） |
| 相似歌曲 | `similarSongsProvider`：原生非空直用；空/无能力走插件映射 |
| 简介 | `artistBioProvider`：原生 `fetchArtistBio` 非空直用；空/无能力走 `pluginArtistBioProvider`（按当前歌歌手名） |
| 设置 | settings_sub_plugins.dart（`_PluginsSettingsPage`）：官方启停 / key 编辑（glassDialog）/ 导入 / 删除；主页入口副标题展示生效能力 |

### 16.6 官方插件

| id | 提供 | key | 实测（2026-09-20，国内直连） |
|----|------|-----|------|
| deezer | 头像（`data.0.picture_xl`）+ 相似歌手（`/artist/{id}/related` → `data.*.name`） | 免 key | 华语覆盖良好（周杰伦/陈粒/告五人均命中），相似歌手含陈奕迅/JJ Lin/王力宏等 |
| theaudiodb | 头像（`artists.0.strArtistThumb`）+ 简介（`search.php` 取 id → `artist.php`，`strBiographyCN\|strBiographyEN` 中文优先） | 免 key（公共测试 key 2 内置在 URL） | 国际歌手中文简介覆盖良好（Coldplay/Adele/Taylor Swift 实测均有 CN 简介），无华语歌手条目 |
| baike | 简介（`abstract\|desc`，一步流） | 免 key（开放接口公共 appid 内置在 URL） | 华语歌手中文简介稳定（周杰伦/林俊杰/陈奕迅/邓紫棋 4/4 命中，abstract 400 字级）；必须带 UA+Referer（headers 声明），否则返回空 |

> Last.fm 描述原为官方预设，实测 `ws.audioscrobbler.com` 国内直连 403（2026-09-20）而移出；需自备代理+key 的用户可按 §16.2 schema 自行导入。
> 国内源盘点（2026-09-20 实测）：网易云头像可用但与 Deezer 重叠且有灰占位图风险、简介接口已迁加密 weapi，QQ 音乐 smartbox 返回空/v8 详情 404/相似接口需 POST，酷狗 info 可用但搜索需签名无法声明式取 id——均不入选。

