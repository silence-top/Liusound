# 流声 Liu Sound 功能梳理文档（完整版）

## 项目概览

**项目名称**: 流声 Liu Sound  
**Document Version**: 2.3.0（本文件自身版本，见文末版本历史）  
**Product Version**: 2.1.x（以 `pubspec.yaml` 的 `version` 为唯一事实来源）  
**Dependency Source of Truth**: `pubspec.yaml`（本文不再复制维护依赖版本号）  
**技术栈**: Flutter + Riverpod + Just Audio + Audio Service  
**目标平台**: Android (MIUI 测试设备 2203121C)  
**多后端支持**: Navidrome / Subsonic / Jellyfin / Emby / Plex / Audio Station (6 种)  
**架构风格**: Adapter 接口 + Capabilities 驱动 UI + Token 化主题系统  

---

## 一、架构分层

### 1.1 目录结构

```
lib/
├── main.dart                  # 入口：SharedPreferences 加载 → runApp
├── app.dart                   # MaterialApp 配置：theme/routes/navigator
├── core/                      # 核心层（跨模块共享）
│   ├── api/                   # ServerAdapter 接口 + 6 个 adapter 实现
│   │   ├── server_adapter.dart    # 抽象基类 + 请求/响应模型
│   │   ├── server_type.dart       # ServerType enum + ServerConfig
│   │   └── adapters/              # 6 个 backend 适配器目录
│   ├── cache/                 # 音频缓存管理（LockCachingAudioSource）
│   ├── download/              # 离线下载 + 自动下载
│   ├── floating/              # Android 悬浮歌词（原生小窗）
│   ├── library/               # 曲库增量同步（SQLite 快照）
│   ├── local/                 # 本地音乐扫描（Isolate + SQLite）
│   ├── lyrics/                # LRC 歌词解析（Navidrome JSON + 经典 LRC）
│   ├── models/                # 数据模型（Song/Album/Artist/Playlist/Genre/RadioStation）
│   ├── network/               # Dio 客户端 + 网络设置（代理/证书/hosts）
│   ├── scrobble/              # Scrobble 上报（离线队列 + 补发）
│   ├── settings/              # 偏好存储（SharedPreferences key 管理）
│   │   ├── prefs.dart             # sharedPrefsProvider 声明
│   │   ├── streaming_prefs.dart   # 音质/转码/网络设置
│   │   └── settings_prefs.dart    # UI 偏好（迷你条/玻璃效果/省电等）
│   ├── storage/               # SQLite 数据库操作
│   │   ├── app_db.dart            # 3 张表 CRUD
│   │   └── server_repository.dart # ServerConfig 持久化 + FlutterSecureStorage
│   └── theme/                 # 主题系统
│       ├── background.dart        # 自定义背景图（路径/不透明度/模糊度）
│       ├── accent.dart            # 强调色切换（6 预设）
│       ├── glass_theme.dart       # GlassTokens 尺寸常量
│       ├── skin_tokens.dart       # SkinTokens ThemeExtension（5 主题 token 束）
│       └── settings_prefs.dart    # 玻璃效果强度等
├── features/                  # 功能模块（页面 + 控制器）
│   ├── auth/                  # 登录 + 服务器管理
│   ├── home/                  # 首页 + 资料库 + 详情页 + 歌手详情
│   ├── player/                # 播放器 + 队列 + 操作弹窗 + 状态 provider
│   ├── search/                # 搜索页
│   └── settings/              # 设置页（分组列表）
├── shared/                    # 共享 UI 组件
│   ├── widgets/               # Glass 组件 / 动画 / 装饰
│   ├── cover_art.dart         # CoverArt（网络封面 + 本地封面回退）
│   └── mini_player.dart       # MiniPlayer（迷你播放条）
└── shell/                     # 主框架
    ├── app_shell.dart             # AppShell 整体布局（底部导航 + 路由）
    └── icons_screen.dart          # 顶部图标导航栏（Home/Lyrics/Search/Library）
```

### 1.2 关键架构契约

| 契约 | 说明 |
|------|------|
| **ServerAdapter 接口** | 所有后端必须实现的方法集；返回 `null` = 不支持，UI 据此隐藏入口 |
| **Capabilities 驱动 UI** | 每个能力字段控制一个或多个 UI 区域显示/隐藏 |
| **AppStage/AppSurface/AppSheet** | 主题组件分层契约：舞台→表面→弹层，禁止跨层消费 |
| **SkinTokens ThemeExtension** | 5 主题通过语义 token 实现；业务页面只使用 token，禁硬编码颜色 |
| **sharedPrefsProvider** | 唯一偏好读写入口；main() 加载后 override 注入，业务控制器 build() 同步读取 |
| **RefReader typedef** | `T Function<T>(ProviderListenable<T>)` 统一 Ref/WidgetRef 的 read tear-off |

---

## 二、多后端适配器

### 2.1 适配器列表

| 适配器 | 类名 | 基础协议 | 特殊能力 | 默认 Capabilities |
|--------|------|----------|----------|-------------------|
| Navidrome | NavidromeAdapter | Subsonic API + 原生 API | owner 字段、转码探测覆写 | ratings=false, similarSongs=false, likedSongs=true, download=true, lyrics=true, artistBio=false, transcoding=true, scrobbling=true, incrementalSync=true |
| Subsonic | SubsonicAdapter | Subsonic API | 标准兼容 | 同上 |
| Jellyfin | JellyfinAdapter | MediaBrowser API | 扩展字段 | 同上 |
| Emby | EmbyAdapter | MediaBrowser API | 扩展字段 | 同上 |
| Plex | PlexAdapter | MediaBrowser API | 扩展字段 | 同上 |
| Audio Station | AudioStationAdapter | Subsonic API | 无增量同步、无 scrobble | ratings=false, similarSongs=false, likedSongs=true, download=true, lyrics=true, artistBio=false, transcoding=false, scrobbling=false, incrementalSync=false |

### 2.2 ServerType 枚举

```dart
enum ServerType { navidrome, subsonic, jellyfin, emby, audioStation, plex }
```

每个变体包含：
- `displayName`: 显示名称（Navidrome/Subsonic/Jellyfin/Emby/Audio Station/Plex）
- `urlHint`: 输入提示（如 `192.168.1.10:4533`）
- `tagline`: 描述文案（开源音乐流媒体/经典音乐服务器协议/免费媒体系统等）
- `fallbackIcon`: IconData（library_music/graphic_eq/movie_creation_outlined/live_tv/storage/play_circle_outline）
- `hasLogoAsset`: true，图标资源在 `assets/app/$name.png`
- `createAdapter(config, secrets)`: 工厂方法创建具体适配器实例
- `signIn(request)`: 静态工厂方法执行登录流程

### 2.3 AdapterCapabilities 能力声明

```dart
class AdapterCapabilities {
  final bool ratings;           // 评分支持（0-5星）
  final bool similarSongs;      // 相似歌曲推荐
  final bool likedSongs;        // "我喜欢"列表（默认 true）
  final bool download;          // 服务端下载支持
  final bool lyrics;            // 歌词支持
  final bool artistBio;         // 歌手简介（部分后端无此接口）
  final bool transcoding;       // 服务端转码（子集后端可能不支持）
  final bool scrobbling;        // Scrobble 上报（Audio Station 不支持）
  final bool incrementalSync;   // 增量同步标记（Audio Station 不支持）
}
```

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

  // 扩展资料库（null = 不支持）
  Future<List<Artist>?> fetchArtists();
  Future<List<Artist>?> fetchAlbumArtists();
  Future<List<Genre>?> fetchGenres();
  Future<List<RadioStation>?> fetchRadioStations();
  Future<List<Song>?> fetchGenreSongs(String genre, {int limit = 100});

  // 歌单创建
  Future<bool> createPlaylist(String name);

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

### 3.1 _Json 辅助工具类

提供安全解析：`str(j, key, fallback)`, `strOf(j, [keys], fallback)`（依次取第一个非空字段）, `intOf/doubleOf/boolOf`（带类型回退）, `strOrNull/doubleOrNull/intOrNull`（可缺省版，全缺返回 null）。

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
| `nextSongProvider` | Provider<Song?> | 下一首预判 | 依赖 queue + currentSong + playMode |
| `playModeProvider` | StateProvider<PlayMode> | 播放模式 | order/shuffle/repeatOne |
| `playbackSpeedProvider` | StateProvider<double> | 播放速度 0.5-3.0 | |
| `loopPlaybackProvider` | StateProvider<bool> | 循环播放（队列播完回首） | 默认 true |
| `autoPlayProvider` | StateProvider<bool> | 启动后自动播放 | 默认 false |
| `crossfadeSecondsProvider` | NotifierProvider<int> | 交叉淡化 0-10 秒 | 持久化 key='crossfade_seconds' |
| `autoOpenPlayerProvider` | NotifierProvider<bool> | 点击歌曲自动打开全屏播放页 | 默认 true，持久化 |
| `sleepTimerProvider` | NotifierProvider<Duration?> | 定时停止，null=未启用 | 不持久化 |
| `resumeNoticeProvider` | StateProvider<String?> | 续播提示/错误消息 | |

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
  void Function(int received, int total)? onProgress,
})
```
- 目标路径: `${docs.path}/Music/<safeName(artist-title)>--<sha256(id).substring(0,16)>.mp3`
- Dio 下载: connectTimeout=10s, receiveTimeout=5min
- 文件名非法字符替换为 `_`（Windows/Android 兼容）
- 指纹保证同名歌曲互不覆盖

#### 4.8.2 findDownloadedSong

```dart
Future<String?> findDownloadedSong(Song song)  // 按 fingerprint 查找，未下载返回 null
```
遍历 Music 目录所有 File，匹配 `--<sha256(id).substring(0,16)>.`

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

### 4.10 曲库增量同步（library_sync.dart）

#### 4.10.1 LibrarySync.songs

```dart
static Future<List<Song>> songs(RefReader read) async {
  // kind: 'songs_all'
  // query: SongQuery(sort=title, limit: 100000)
  // 展示顺序由 UI 侧决定（home_providers.dart 按 created 降序）
}
```

#### 4.10.2 LibrarySync.albums

```dart
static Future<List<Album>> albums(RefReader read) async {
  // kind: 'albums_name_v2'
  // query: AlbumQuery(sort=name, limit: 10000)
  // 仅服务器详情页使用；专辑列表页已改为真 offset 分页（LibraryAlbumsController）
}
```

#### 4.10.3 _load 同步算法

```dart
Future<List<T>> _load<T>({String kind, Future<List<T>> fetch, encode, decode}) async {
  // 1. if !capabilities.incrementalSync → 直接 fetch()
  // 2. 读 SQLite snapshot (server_key + kind)
  // 3. adapter.libraryVersion() → 5s timeout
  // 4. offline/slow: current==null → 已有快照就是最可靠
  // 5. current == cachedVersion → 读缓存 decode(cachedPayload)
  // 6. version 变了 → fetch() fresh → upsert snapshot → return
  // 7. catch: 有 cachedPayload → decode; 否则 fetch()
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
  liquidGlass('液态玻璃', '镜面高光描边 · 内容透色（默认）'),
  deepSpace('深空科幻', '近黑蓝底 · 霓虹青发光点缀'),
  minimal('极简纯色', '无模糊实色卡片 · 强排版'),
  materialYou('Material You', '动态取色跟随系统壁纸（Android 12+）'),
  highContrast('高对比无障碍', '纯黑白 · 去模糊去发光 · 对比度 ≥7:1');

  final String label;
  final String desc;
}
```

SkinController:
- prefs key: `'app_skin'`
- 默认: `liquidGlass`
- `set(AppSkin skin)`: state change + SharedPreferences.setString

#### 4.14.2 SurfaceLanguage 语言枚举

与 AppSkin 一一对应，用于 SkinTokens.language 字段分派视觉实现。

#### 4.14.3 SkinTokens ThemeExtension

18 个语义 token:

| Token | 类型 | 含义 |
|-------|------|------|
| background | Color | Scaffold/AppBar 页面背景 |
| shell | Color | 主框架背景 |
| detailBg | Color | 详情/二级页背景 |
| surface | Color | 卡片/输入框 |
| divider | Color | 分隔线 |
| glassTint | Color | 玻璃面板 tint 底色 |
| tintLight | Color | 亮色薄雾 |
| borderTop | Color | 玻璃上缘受光 |
| borderBottom | Color | 玻璃下缘 |
| borderHairline | Color | 1px 均匀微亮描边 |
| shadowColor | Color | 投影 |
| textDim | Color | 次要文本 |
| textFaint | Color | 装饰图标/占位 |
| glow | Color | 科幻发光（透明=无发光） |
| blurScale | double | 模糊强度缩放 |
| blurEnabled | bool | 极简/高对比强制关模糊 |
| highlightStrength | double | 镜面高光强度（0=实色描边） |
| language | SurfaceLanguage | 当前皮肤语言 |

**5 套皮肤的具体数值**:

| Token | liquidGlass | deepSpace | minimal | materialYou | highContrast |
|-------|-------------|-----------|---------|-------------|--------------|
| background | 0xFF001B2E | 0xFF05070E | 0xFF111111 | 0xFF131318 | 0xFF000000 |
| shell | 0xFF0A1428 | 0xFF070A14 | 0xFF161616 | 0xFF1B1B21 | 0xFF000000 |
| surface | 0xFF1A2C3A | 0xFF0D1322 | 0xFF1F1F1F | 0xFF232329 | 0xFF111111 |
| glassTint | 0x4D13243C | 0x59101830 | 0xF01F1F1F | 0x52262630 | 0xE6111111 |
| borderTop | 0x33FFFFFF | 0x4048D8FF | 0x1FFFFFFF | 0x33FFFFFF | 0x99FFFFFF |
| borderBottom | 0x0AFFFFFF | 0x0D28C8FF | 0x0AFFFFFF | 0x0AFFFFFF | 0x66FFFFFF |
| borderHairline | 0x1FFFFFFF | 0x2428C8FF | 0x1FFFFFFF | 0x1FFFFFFF | 0x66FFFFFF |
| glow | 0x00000000 | 0x3800E5FF | 0x00000000 | 0x00000000 | 0x00000000 |
| textDim | 0xFF888888 | 0xFF9FB4CC | 0xFFAAAAAA | 0xFFCAC4D0 | 0xFFE0E0E0 |
| textFaint | 0xFF444444 | 0xFF4A5A72 | 0xFF666666 | 0xFF79747E | 0xFFB0B0B0 |
| blurScale | 1.0 | 1.1 | 0 | 1.0 | 0 |
| blurEnabled | true | false | false | false | false |
| highlightStrength | 1.0 | 0 | 0.2 | 0 | 0.0 |

- `lerp(SkinTokens? other, double t)`: Color.lerp 插值 + blurScale/lerp + boolean threshold(t<0.5) + language threshold
- `forSkin(AppSkin skin)`: 映射表

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
  final double opacity;     // 默认 0.35，clamp(0,1)
  final double blur;        // 默认 8.0
}
```

| 方法 | 说明 |
|------|------|
| `setImage(sourcePath)` | 复制到 `custom_bg.png` → 持久化 path |
| `clearImage()` | 删除文件 → 清 path → state 保留 opacity/blur |
| `setOpacity(double)` | clamp 后持久化 |
| `setBlur(double)` | 持久化 |
| `_validateFile(path)` | 异步校验文件存在，缺失时清理（不覆盖用户新值） |

prefs keys: `'bg_image_path'`, `'bg_opacity'`, `'bg_blur'`

#### 4.14.7 AmbientBackground 舞台渲染

| 皮肤 | 背景实现 |
|------|----------|
| liquidGlass | 3 个 RadialGradient 光源 blob（primary alpha 0.15-0.20），位置 (-100,-140)/(right-120,80)/(left+20,-80)，大小 300-340 |
| deepSpace | CustomPaint 网格(56px step) + 7 个 star circle(r=1.3, primary alpha 0.45)，坐标 O(34,96), O(164,178), O(294,72), O(92,486), O(342,624), O(226,744) |
| minimal/materialYou | 纯色背景（SkinTokens.background） |
| highContrast | 纯黑背景 |
| custom bg | Image.file(path, fit=cover, gapless) + Opacity + ImageFilter.blur(sigmaX=blur, sigmaY=blur) |

#### 4.14.8 _DeepSpaceStagePainter

- 网格: Paint(strokeWidth=1, primary alpha=0.055), step=56px
- 星星: Paint(color=primary alpha=0.45), r=1.3

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

3 张表，version=3，懒初始化单例:

| 表 | 用途 | 关键索引 |
|----|------|----------|
| scrobble_queue | Scrobble 离线队列 | PRIMARY KEY(id) |
| library_snapshot | 曲库增量同步快照 | PRIMARY KEY(server_key, kind) |
| lyrics_local | 本地导入/扫描歌词 | PRIMARY KEY(lookup_key) |

**lyrics_local lookup_key 生成**:
```dart
lyricsKey(title, artist) = '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}'
```

**v2→v3 迁移**: ALTER TABLE scrobble_queue ADD COLUMN server_id DEFAULT ''; DELETE WHERE server_id=''

### 4.18 共享 UI Provider（settings_prefs.dart）

以下 provider 存储在 `core/settings/settings_prefs.dart` 或相关文件中:

| Provider | 类型 | 用途 |
|----------|------|------|
| `glassQualityProvider` | NotifierProvider<GlassLevel> | 玻璃效果三档：关闭/标准/增强 |
| `powerSaveProvider` | NotifierProvider<bool> | 省电模式开关 |
| `miniBarStyleProvider` | NotifierProvider<MiniBarStyle> | 迷你条样式 |
| `miniBarOffsetProvider` | NotifierProvider<int> | 迷你条高度偏移 |
| `settingsIconsProvider` | NotifierProvider<bool> | 图标显隐 |
| `listEndTextProvider` | NotifierProvider<String> | 列表触底文案 |
| `floatingLyricsProvider` | NotifierProvider<bool> | 悬浮歌词开关 |
| `headsetClicksProvider` | NotifierProvider<HeadsetClicksState> | 线控动作配置 |
| `coverStyleProvider` | NotifierProvider<CoverStyle> | 封面样式 |
| `audioEffectsProvider` | NotifierProvider<AudioEffectsState> | 均衡器/空间音频 |
| `bilingualLyricsProvider` | NotifierProvider<bool> | 双语歌词开关 (key: 'lyrics_bilingual_enabled') |

---

## 五、功能模块详解（完整版）

### 5.1 认证模块（features/auth/）

#### 5.1.1 LoginScreen

- **ServerType 选择区**: 6 个后端卡片（logo + 名称 + tagline + urlHint）
- **地址输入**: 免协议输入，normalizeServerUrl 自动补 `http://` + 去尾斜杠
- **HTTPS 开关**: 控制连接时的协议
- **用户名输入**: TextField（type=text, obscureText=false）
- **密码输入**: TextField（type=text, obscureText=true）
- **登录按钮**: 阻塞态 loading → success → error toast
- **登录流程**: `type.signIn(AuthRequest)` → `AdapterSession.secrets` → `ServerRepository.saveServers/saveSecrets/saveActiveId`

#### 5.1.2 ServerSelectScreen

- **已保存服务器列表**: 从 AuthController.servers 渲染
- **服务器卡片**: logo + 名称 + URL + 用户名 + 操作按钮（切换/测试/删除）
- **切换**: AuthController.switchServer(id) → Navigator.popUntil(root)
- **测试**: AuthController.validateServer(id) → show SnackBar
- **删除**: AuthController.removeServer(id) → 如果当前激活则跳回到选择页

#### 5.1.3 ServerDetailScreen

- **大卡**: logo + 名称 + 统计行（歌曲/专辑/歌手/歌单数）
- **折叠展开**: AnimatedAlign 动画
- **入口网格**: 4 个 _Entry 组件（歌曲/专辑/歌手/歌单）
- **服务器管理**: 别名编辑/重新连接/删除/退出

#### 5.1.4 ServersScreen

- **服务器卡片**: 开关 + 测试按钮 + 删除按钮
- **添加服务器 FAB**: 跳转到 LoginScreen
- **空状态**: glassEmptyState("暂无服务器")

### 5.2 首页（features/home/home_screen.dart）

#### 5.2.1 欢迎词

- `_Greeting` widget: 根据小时返回 "早上好"/"中午好"/"下午好"/"晚上好"/"夜深了"
- 注意: 最近修复为去欢迎词，搜索栏与资料库平齐

#### 5.2.2 搜索栏

- `_SearchBar`: Container(height=40, white .07, borderRadius=20)
- 左侧: Icon(Icons.search, color=white, size=20)
- 右侧: Icon(Icons.qr_code_scanner, color=white54, size=20)
- 点击 → Navigator.push(fadeRoute(SearchScreen()))

#### 5.2.3 最新专辑

- `latestAlbumsProvider` → FutureProvider<List<Album>>
- `_AlbumRow`: ListView.builder(itemExtent=140)
- `_AlbumCard`: 128×128 封面 + MarqueeText(name, fontSize=14) + Text(artist, fontSize=12)
- 点击 → push fadeRoute(SongListScreen(rateTargetId: album.id, rating: album.rating))

#### 5.2.4 每日推荐 / 最近播放 / 最常播放

- 均为 `_SongListSection`: GlassContainer + 3 行 SongRow
- 各有一个 FutureProvider，含 seed 参数
- `_SongCardRow`: 56px 封面 + title(16 bold) + subtitle(12) + 右三角播放按钮
- 点击歌曲行 → playerActions.play(song) + autoOpenPlayer → FullScreenPlayer

#### 5.2.5 随机专辑

- `randomAlbumsProvider` → seed-based shuffle
- 横向滚动，样式同最新专辑

#### 5.2.6 下拉刷新

- RefreshIndicator → 更换 randomSeed → 重取 latestAlbums/dailySongs/recentlyPlayed/mostPlayed/randomAlbums

### 5.3 资料库（features/home/music_library_screen.dart）

#### 5.3.1 服务器面板

- `serverPanelExpanded` StateProvider<bool> (默认 true)
- AnimatedSize + AnimatedOpacity 折叠展开
- logo: Image.asset('assets/app/{name}.png', width=64, height=64)
- 名称 + 统计行（歌曲数 / 专辑数）

#### 5.3.2 歌单区

- `playlistCoverIdsProvider`: FutureProvider.family<List<String>, String>
  - 取歌单前 4 首歌的 albumId（最多 4 个）
  - 拼贴为 2×2 网格封面
- `allPlaylistsProvider`: FutureProvider<List<Playlist>>
- **我的歌单 / 全部歌单** 切换:
  - `toggleState` 在 'my'/'all' 之间切换
  - `canToggle = all.isNotEmpty`（切换恒可用只要有歌单）
  - `filtered = all.where(p -> matchOwner(p.owner))`
  - owner mismatch → fallback 到全部 `all`
- 歌单行: 拼贴封面(80px) + 名称 + 歌曲数 + 播放/入队 IconButton

#### 5.3.3 四入口

| 入口 | 打开方式 | 数据源 | 页面类型 |
|------|----------|--------|----------|
| 歌曲 | _openSongs('歌曲', librarySongsProvider) | songsProvider | SongListScreen |
| 我喜欢的 | _openSongs('我喜欢的', likedSongsProvider) | songsProvider | SongListScreen |
| 本地音乐 | _openLocalSongs(localSongsProvider) | songsProvider | SongListScreen |
| 专辑 | push fadeRoute(AlbumListPage(title, paged: libraryAlbumsPagedProvider)) | StatefulWidget | 独立页面（滚动加载分页） |

#### 5.3.4 AlbumListPage（专辑列表页）

```dart
class AlbumListPage extends ConsumerStatefulWidget {
  const AlbumListPage({super.key, required this.title, required this.provider});
  final String title;
  final FutureProvider<List<Album>> provider;
}

class _AlbumListPageState extends ConsumerState<AlbumListPage> {
  late final _controller = ScrollController();
  final _search = TextEditingController();

  Widget build(_) {
    final async = ref.watch(widget.provider);
    return Scaffold(
      body: Stack(
        children: [
          AppStage(child: async.when(...)),
          Positioned(top: 0, left: 0, right: 0, child: _AlbumSearchBar()),
        ],
      ),
      bottomNavigationBar: MiniPlayer(),
    );
  }
}
```

**_AlbumSearchBar**: height=38, Container(width:double.infinity, height=38, color:white24, borderRadius=radiusCircular(19))
- padding: EdgeInsets.symmetric(horizontal=16)
- Row: SizedBox(width=36) + Icon(Icons.search) + Expanded + TextField + GestureDetector(Icon(Icons.filter_list))

**4列网格计算**:
```dart
final cover = (MediaQuery.sizeOf(context).width - padding*2 - spacing*3) / 4;
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisAxis(
    crossAxisCount: 4,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
    childAspectRatio: cover / (cover + 70),
  ),
);
```

**AlbumCard 红色角标**:
- 位置: top=4, right=4
- decoration: BoxDecoration(color:Color(0xFFFA2C19), shape:BoxShape.circle, minHeightIntrinsicHeight:18, minWidthIntrinsicWidth:18)
- child: Center(child: Text(album.songCount > 99 ? '99+' : '${album.songCount}', style:TextStyle(fontSize:10, fontWeight:bold, color:white))

#### 5.3.5 搜索栏

- 与首页搜索栏样式一致：Container(height=40, color:white.withAlpha(18), borderRadius=Radius.circular(20))
- 左: Icon(Icons.search, color:white, size=20)
- 中: Text('搜索', style:textStyle.labelLarge.copyWith(color:white70))
- 点击 → push fadeRoute(SearchScreen())

### 5.4 详情页（features/home/detail_screen.dart）

#### 5.4.1 SongListScreen 构造函数（三页合一：专辑/歌单/艺人）

```dart
class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({
    super.key,
    required this.title,
    this.songs,                 // 直接给定（每日推荐）
    this.pagedSongsProvider,    // 分页加载（艺人歌曲，含「加载更多」）
    this.songsProvider,         // 一次性异步加载（资料库入口/流派）
    this.playlistId,            // 异步加载（我的歌单）
    this.coverAlbumId,          // 封面（回退到 first.albumId；艺人页传 artistId）
    this.date,                  // 副标题（本地音乐为占用空间文本）
    this.subtitle,
    this.rating = 0,
    this.rateTargetId,          // 非 null 且后端支持评分时显示五星评分（专辑）
  });
}
```

- 数据源优先级：songs > pagedSongsProvider > songsProvider > playlistId
- 分页源复用 `artistSongsProvider`（ArtistSongsController 累计 limit 策略），
  列表尾部挂 `LoadMoreRow`，空态/失败重试独立于 sliverAsyncGuard

#### 5.4.2 Build 数据获取

```dart
@override
Widget build(_, WidgetRef ref) {
  final async = widget.songsProvider != null
      ? ref.watch(widget.songsProvider!)  // 资料库入口
      : widget.playlistId == null
          ? null                           // 直接 songs，无 async
          : ref.watch(playlistSongsProvider(widget.playlistId!));

  final all = async.valueOrNull ?? widget.songs ?? [];

  // 封面回退
  final coverAlbumId = widget.coverAlbumId ?? (all.isEmpty ? null : all.first.albumId);

  // 副标题
  final subtitle = widget.date ?? (totalBytes > 0
      ? '共计占用 ${QualityBadge.fileSizeLabel(totalBytes)} 空间'
      : '$total 首');
}
```

#### 5.4.3 Header 静态头部

- 封面: 56px 圆形 CoverArt
- 标题: Text(title, style=titleLarge.bold)
- 副标题: Text(subtitle, style=labelSmall)

#### 5.4.4 列表顶部

- `_ListTop`: Column(children: [_PlayAllBar, _FilterBar])
- `_PlayAllBar`: height=48, Row(children:[Expanded+Text+GestureDetector(icons.play_arrow,shuffle,globe)])
- `_FilterBar`: height=38, Container(color:white24, borderRadius:radiusCircular(19)), 内部 Row(search icon + TextField + filter icon)

#### 5.4.5 _songSlivers 歌曲列表

```dart
_buildSongSlivers(all, {showFileSize, onRetry, ...}) {
  return SliverList(
    delegate: SliverChildBuilderDelegate((_, i) {
      final song = all[i];
      return FadeSlideIn(
        child: GlassCard(
          margin: EdgeInsets.only(bottom: 2, left: 16, right: 16),
          onTap: () => onTapSong(song),
          child: SongRow(song, showFileSize, onTapAction, context),
        ),
      );
    }),
  );
}
```

#### 5.4.6 SongRow 歌曲行

```dart
SizedBox(
  height: 72,
  child: Row(
    children: [
      // 序号/勾选框
      Padding(padding: EdgeInsets.all(8), child: _IndexOrCheckbox(index)),
      // 封面
      CoverArt(id, width=56, height=56, radius=4),
      // 信息
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song.title, style:bodyMedium),
            Text('${song.artist} - ${song.album}', style:labelSmall),
          ],
        ),
      ),
      // 音质徽标
      QualityBadge(song, showFileSize: showFileSize),
      // 菜单
      PopupMenuButton(...),
    ],
  ),
)
```

#### 5.4.7 批量选择

- `_BatchSelect` mixin 混入
- `_selectedSongs = {}` Set<String>
- 长按/勾选进入批量态
- `_BatchBar`: 底部 Fixed 栏，显示选中数量 + 操作按钮（下一首/添加到歌单/下载）
- 序号列切换为 Checkbox

#### 5.4.8 可选评分（专辑入口）

- rateTargetId 非 null 且 capabilities.ratings 为真时显示五星评分 StarRating
- _rate 失败回滚并提示「评分提交失败」

### 5.5 艺人歌曲入口（原独立 ArtistDetailScreen 已删除）

- 所有艺人歌曲入口（歌曲信息页 / 操作弹窗 / 搜索艺人行 / 资料库歌手列表）
  统一 push SongListScreen(pagedSongsProvider: artistSongsProvider(artistId), coverAlbumId: artistId)
- 分页数据源 ArtistSongsController（home_providers.dart）：累计 limit 策略、
  按 id 去重合并、返回少于请求量或无新增判定 noMore

---

### 5.6 流派详情页（features/home/genre_detail_screen.dart）

#### 5.6.1 页面结构

- AppBar: 流派名 title + leading back
- Sliver 布局:
  - SliverToBoxAdapter: SectionTitle "热门歌曲"
  - SongTileList（最多展示 20 首）
  - SectionTitle "相关专辑"
  - GridAlbumList（4 列，最多 20 张）
  - SectionTitle "相关歌手"
  -横向 ScrollView: ArtistAvatarRow（圆形头像，每行 6-8 个）

#### 5.6.2 数据来源

- fetchGenreSongs(genre, limit=100) → 后端不支持返回 null，UI 隐藏该分区
- fetchGenres() 返回列表项 {value, songCount, albumCount}

---

### 5.7 歌单详情页（features/library/playlist_detail_screen.dart）

#### 5.7.1 头部信息区

- PlaylistName: 大字标题
- ownerName: 小号次要文字（owner ?? '未知'，区分「我的歌单 / 全部歌单」）
- CoverArt: 圆角 12px 封面图（fetchCoverBytes(albumId, size=300)），占位用 MusicIcons.playlistOutline
- StatsRow: songCount + totalDuration（自动换算为 h:m 格式）

#### 5.7.2 操作栏

- PlayAll FAB: floatingActionIcon = PlayIcon(white), onPressed = playAll
- AddToFav iconButton（星号，已收藏变实色）
- MoreMenuBuilder: ...moreOptions(context) — 编辑歌单名称 / 删除 / 分享

#### 5.7.3 歌曲列表

- SongTileList（带序号的完整列表，非分页懒加载）
- 每行显示: Checkbox（多选模式）+ SongInfo(title + artist) + Duration + ...菜单
- ...菜单选项: playNext / addToPlaylist / removeFromPlaylist / download（依 capabilities）
- 长按触发多选模式，进入 BatchBar

#### 5.7.4 切换逻辑

- 从「我的歌单」Tab 点击进入：当前用户的 playlist
- 从「全部歌单」Tab 点击进入：任意用户的公开 playlist
- ownerName 兜底为空字符串时不显示，避免布局错位

---

### 5.8 搜索结果页（features/search/search_screen.dart）

#### 5.8.1 搜索入口

- HomePage 搜索栏: TextField + onSubmitted(query) → Push/SearchScreen(query)
- SearchDelegate (过滤框): 从 SongListScreen 等页面唤起

#### 5.8.2 搜索结果聚合

- SearchResult {songs, albums, artists} 三个分区分别渲染
- 每个分区独立 SectionTitle + List 数量徽标
- 空结果: showEmpty(context, '未找到与 "$query" 相关的内容')
- 搜索历史: SharedPreferences key=searchHistory，最多保存 10 条，按 lastSearch 倒序

#### 5.8.3 实时搜索

- TextField + onChanged(text): debounce 300ms 后调用 adapter.search(text)
- FutureProvider(autoStream: true) 管理搜索 Future 状态
- 加载中: Shimmer 骨架屏（每分区 5 条 SkeletonCard）

---

### 5.9 本地音乐（features/local/local_music_screen.dart）

#### 5.9.1 扫描入口

- 点击进入时才触发扫描，不在页面 build 时自动扫描
- 首次无缓存: 显示进度 Dialog("正在扫描本地音乐...") + LinearProgressIndicator
- 扫描在后台 Isolate 中运行，不阻塞 UI 线程

#### 5.9.2 Isolate 扫描流程

- 唯一实现: `Isolate.run(() => _scanIsolate(dirPaths, coverPath))`（core/local/local_library.dart），无 compute / SendPort
- Isolate 负责: 目录递归遍历 + audio_metadata_reader 标签解析 + 本地歌曲 fingerprint 计算 + 内嵌封面/LRC 提取（纯 Dart IO，不访问 SQLite——sqflite 走平台通道只能主 isolate 写）
- 主 isolate 负责: 接收 `_ScanResult{songs, lyrics}` record → 歌词写 lyrics_local（双键）→ 歌曲列表写 library_snapshot 本地行
- 单目录/单文件解析失败不阻断整体扫描

#### 5.9.3 本地歌曲身份（fingerprint ID）与缓存

- 本地歌曲 ID: `local:{fingerprint}`，fingerprint = md5(文件大小 + mtime + 头部固定 16KB + 归一化标题/歌手 + 时长)
  - 只读头部固定小块，禁止整文件 hash（大 FLAC/APE 曲库不可接受）；在扫描 isolate 内计算
  - 移动/重命名文件不改变歌曲身份；路径变化记录在 Song.path
  - fingerprint 是轻量身份指纹，不是完整性校验
- 扫描缓存: 复用 library_snapshot 表（server_key='local', kind='local_songs_v2'），无独立 local_scan_cache 表
- 二次进入: 读快照秒开；后台限流重扫（5 分钟内不重复），文件有增删 bump localScanVersionProvider 自动刷新
- 快照 JSON >256KB 时在 Isolate.run 中解码

#### 5.9.4 文件显示

- SongTileList 格式: filename + duration + fileSize 徽标（KB/MB/GB 自动换算）
- 占用空间总计: AppBar bottom 副标题 ("共 XX 首，占用 X.X GB")
- 文件大小来源: Song.size (字节数)

#### 5.9.5 内嵌封面

- 扫描时提取 FLAC/Ogg/MP3(ID3) 内嵌封面 → 写入缓存目录
- localCoverPath: 指向缓存的文件路径（非服务端 URL）
- 显示: LocalSongImage(localCoverPath, size=48)；为 null 时 fallback MusicIcons.musicNote

---

## 六、UI 组件库详细规格

### 6.1 GlassSurface 系列

| 组件 | 用途 | 关键参数 |
|------|------|----------|
| GlassSurface | 顶层背景容器 | decorationType(Glass/Surface), blurHeavy/Medium/Light(28/18/12), tint(SkinTokens.glassTint) |
| GlassCard | 悬浮卡片 | borderRadius=16, padding=16, elevation=0, backdropFilter(webkit=true) |
| GlassPill | 胶囊标签/Tab | borderRadius=999, height=32, paddingHorizontal=12 |
| GlassContainer | 内容区块容器 | borderRadius=12, innerSpacing(v=8,h=16) |
| GlassAppBar | 透明顶栏 | surfaceOpacity=0.0, bottom=PreferredSize(height: kToolbarHeight) |

**GlassSurface 绘制顺序**:
1. non-glass surface layer: SurfaceToken.color + opacity=0.6 (基础底色)
2. glass layer: BackdropFilter(blurX/Y=blurHeavy) + Container(color=glassTint.withOpacity(0.15))
3. gradient border: _GradientBorderPainter(strength=default)，top-to-bottom linear gradient
   - startColor: accentColor.mix(SkinTokens.highlightStrength=0.3)
   - endColor: transparent
4. shadow layer: Shadows.shadowLayer(elevation=2, color=SkinTokens.shadowColor)

**_GradientBorderPainter 行为**:
- strength <= 0: 回退为纯色 SolidDecoratedBox(color=accentColor.withOpacity(0.2))
- strength > 0: GradientBorderPainter(sides=[Top, Bottom] or [All])，strokeWidth=1.5

### 6.2 AudioPlayerState 消费者

```dart
Consumer(
  builder: (context, ref) {
    final state = ref.watch(audioPlayerServiceProvider);
    // PlaybackState: playing/paused/stopped/error
    // Duration: state.duration (总时长)
    // Position: state.position (当前播放位置)
    // Volume: state.volume (0.0-1.0)
    // ShuffleMode: state.shuffleModeEnabled
    // RepeatMode: state.repeatMode (off/one/all)
    // buffered: state.buffered (List<Interval>)
    // error: state.errorDescription (string, null 时无错误)
  }
)
```

### 6.3 Shimmer 骨架屏

```dart
Shimmer.fromColors(
  baseColor: SkinTokens.textSecondary.withOpacity(0.1),
  highlightColor: SkinTokens.textSecondary.withOpacity(0.2),
  child: Column(
    children: List.generate(5, (_) => SkeletonCard(height: 80)),
  ),
)
```

- SkeletonCard: Container(borderRadius=12, height=80, child: Row(children: [SizedBox(width=48), Expanded(child: Container(height: 20)])))
- 动画: gradient 水平移动 distance=200, duration=1.5s

---

## 七、数据库表结构

> 唯一事实来源：`lib/core/storage/app_db.dart`（当前 version=4）。
> Migration 约束：只允许 ADD COLUMN / CREATE TABLE（IF NOT EXISTS）；
> 破坏性操作仅限可再生缓存且必须注释说明。

### 7.1 library_snapshot

| 字段 | 类型 | 说明 |
|------|------|------|
| server_key | TEXT PK | 服务器 ID（auth.activeServerId ?? 'none'）；本地扫描缓存固定为 'local' |
| kind | TEXT PK | 快照类型：songs_all / albums_name / local_songs_v2 |
| version | TEXT | 服务端变更标记（libraryVersion 返回值）；本地行为写入时间 |
| payload | TEXT | JSON 编码的完整列表数据（>256KB 时 Isolate.run 解码） |

- 插入: conflictAlgorithm=replace（UPSERT）
- 查询: WHERE server_key=? AND kind=?
- 同步判断（versionedSnapshot 语义，非 delta 增量）: cached.version == current → 直接用快照；变化 → 全量重拉替换快照
- 本地扫描复用本表：server_key='local' AND kind='local_songs_v2'（v2 = fingerprint ID 格式；旧 local_songs 行写入 v2 后删除）

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

### 7.4 download_index

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK AUTOINCREMENT | 自增主键 |
| server_id | TEXT NOT NULL DEFAULT '' | 归属服务器 |
| song_id | TEXT NOT NULL | 歌曲 ID |
| fingerprint | TEXT NOT NULL UNIQUE | sha256(songId)[0:16]（唯一索引 idx_download_fingerprint） |
| path | TEXT NOT NULL | 下载文件绝对路径（Music/ 下） |
| size | INTEGER NOT NULL DEFAULT 0 | 文件字节数 |
| created_at | INTEGER NOT NULL | 下载完成时间 |
| last_accessed_at | INTEGER NOT NULL | 最近反查命中时间 |

- 反查: findDownloadedSong 先查索引（O(1)），File.exists 校验；文件丢失 → 懒修复（删失效记录）；索引未命中 → 目录指纹扫描兜底并回填索引
- 下载写入 .tmp 临时文件，校验后原子 rename，成功才登记索引

> 不存在的表：`local_scan_cache`（本地扫描缓存复用 library_snapshot）、
> `autoplay_queue`（运行时队列唯一 SoT 是内存态 QueueNotifier，不持久化）。
> 长音频断点（>10min）存 SharedPreferences key=`breakpoint_<songId>`，不属于 SQLite。

---

## 八、依赖库清单

> 具体版本以 `pubspec.yaml` 为唯一事实来源，本文只记录包与用途（P0-01）。

### 8.1 核心运行时

| 包 | 用途 |
|----|------|
| flutter_riverpod | 状态管理（Provider/NotifierProvider/FutureProvider/StreamProvider） |
| just_audio | 音频播放引擎（AudioPlayer + LockCachingAudioSource 缓存源） |
| audio_service | Android background playback + iOS MediaSession |
| sqflite | SQLite 本地数据库 |
| shared_preferences | 轻量配置持久化 |
| flutter_secure_storage | 服务器 secrets（password/token/salt）持久化 |

### 8.2 UI / 网络 / 工具

| 包 | 用途 |
|----|------|
| dio | HTTP 客户端（API 调用 + 媒体流/下载，download_service 原子写入） |
| cached_network_image | 图片缓存（封面图 fetchCoverBytes + network image） |
| path_provider | 设备文件系统路径（cacheDir / documentsDir） |
| permission_handler | 存储/音频权限请求 |
| intl | 日期格式化 / 数字本地化 |
| package_info_plus | app version + build number |
| connectivity_plus | 网络状态监听（Stream<ConnectivityResult>） |
| crypto | SHA-256（下载 fingerprint）/ MD5（本地歌曲 fingerprint） |
| wakelock_plus | 屏幕常亮控制 |
| audio_metadata_reader | 本地音频标签解析（扫描 isolate 内执行） |
| flutter_localizations | SDK | 多语言支持（Localizations.of(context).locale.languageCode） |

### 8.3 构建 / 测试（开发依赖）

| 包 | 用途 |
|----|------|
| flutter_test | SDK | 单元测试 / widget 测试 |
| integration_test | SDK | E2E 集成测试 |

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
| 5 | Jellyfin fetchSongs 返回的 trackNumber 字段名为 track 而非 trackNumber | Jellyfin | Song.fromJson 回退: trackNumber ?? track |
| 6 | Plex 的 sampleRate 单位是 Hz，Subsonic 系是 kHz | 全局 | _sampleRateHz(j): raw < 1000 ? raw * 1000 : raw.round() |
| 7 | Audio Station 不提供 libraryVersion() | 版本快照同步 | versionedSnapshot=false → 每次全量拉取 |
| 8 | Navidrome transcoding capabilities=true 但实际可能缺 ffmpeg | 转码 | resolveStream 探测 + 播放失败回退到无损原始流 |

### 9.3 性能侧

| # | 问题 | 影响范围 | 临时对策 |
|---|------|----------|----------|
| 9 | 首次启动 songs_all 拉取 100000 首歌曲耗时 ~8s | 冷启动 | incremental sync 缓存快照，后续秒开 |
| 10 | GridAlbumList 4xN 网格在大列表 (>500 张) 上 ScrollPhysics 卡顿 | 资料库 | ListView.builder 懒加载 + itemExtent |
| 11 | 本地音乐扫描在主线程阻塞 | 本地音乐页 | Compute/isolate 异步扫描 + progress dialog |

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

---

## 十一、设计参考

### 11.1 UI 截图对齐源

| 文件 | 对应页面 | 关键设计决策 |
|------|----------|-------------|
| UI/资料库.jpg | 资料库首页 | QQ 音乐风格：顶部导航（歌曲/专辑/歌手/歌单）+ 卡片网格 |
| UI/播放界面.jpg | 播放详情页 | 全屏封面 + 滚动歌词 + 底部控制面板 |
| UI/评分.jpg | 评分交互 | 五星点击 + 颜色填充（空心→实心） |
| UI/浮动歌词.jpg | 浮动歌词 | 半透明浮窗 + 拖拽关闭 + 权限提示 |
| UI/浮动歌词1.jpg | 设置面板 | 透明度/字号/位置调节滑块 |
| UI/浮动歌词2.jpg | 版权保护模式 | 黑色背景 + 无文字 |
| UI/选曲单.jpg | 播放队列 | 列表式 + 删除手势 + 清空按钮 |
| UI/翻译.jpg | 双语歌词 | 原文/翻译交替显示 + 颜色区分 |
| UI/滚动效果.jpg | 滚动歌词 | parallax header + sticky section title |
| UI/滚动效果2.jpg | 专辑详情 | Parallax 封面 + 粘性统计栏 |
| UI/隐藏键盘.jpg | 通用交互 | TextField onBlur + FocusScope.of(context).unfocus() |

### 11.2 设计原则

1. **一致间距体系**: 8dp grid system (4/8/12/16/24/32)
2. **字体层级**: Display(28sp/Bold) > Title(20sp/SemiBold) > Body(16sp/Regular) > Caption(12sp/Medium)
3. **色彩语义**: primary(品牌色) > secondary(辅助) > error(红) > warning(橙) > success(绿)
4. **动语规范**: easeInOutCubic, duration=200ms(short)/300ms(normal)/500ms(long)
5. **无障碍**: contrast ratio >= 4.5:1(body text), hit area >= 48x48dp

---

## 十二、边界情况与回退策略

### 12.1 网络异常

| 场景 | 表现 | 回退 |
|------|------|------|
| 无网络 + 有缓存快照 | 正常展示库数据（只读） | library_sync._load catch → decode(cachedPayload) |
| 无网络 + 无缓存 | 显示 Loading → Error(\"离线模式\") | fetch() → 超时 → showEmpty(context, '无网络连接') |
| 弱网（版本标记 >5s 超时） | 跳过增量检查，直接使用快照 | current==null && cached!=null → decode(cached) |
| API 返回 5xx | Toast(\"服务器繁忙\") + 重试按钮 | http postError → catch → RetryConsumer |

### 12.2 数据异常

| 场景 | 表现 | 回退 |
|------|------|------|
| Song.title 为空 | 显示\"未知歌曲\" | _Json.str(j, 'title', '未知歌曲') |
| Song.artist 为空 | 显示\"未知歌手\" | _Json.str(j, 'artist', '未知歌手') |
| Album 同时有 maxYear 和 year | 优先 maxYear | year: (j['maxYear']..).. ?? (j['year']..) |
| coverArt 存在但 fetchCoverBytes 返回 null | 显示占位图标 | Image.network? .maybeOf(context) ?? Icon(MusicIcons.placeholder) |
| lyrics 解析失败（格式错误） | 隐藏歌词区域 | try: parseLyricsTracks → catch → set lyrics=null |

### 12.3 播放异常

| 场景 | 表现 | 回退 |
|------|------|------|
| 媒体流 404 | Toast(\"文件不可用\") + 从队列移除 | resolveStream → http error → queue.remove(songId) |
| 转码失败（ffmpeg 缺失） | 回退到原始流 | supportsTranscode probe false → resolveDownload(song) |
| 音频解码器不支持 | Toast(\"不支持的编码格式\") | just_audio SetDataSource error → catch → show UnsupportedDialog |
| 设备存储空间不足 | 下载失败 Toast | downloadService → IoException → catch → \"存储空间不足\" |

### 12.4 权限异常

| 场景 | 表现 | 回退 |
|------|------|------|
| 存储权限未授权 | 本地音乐页显示\"需要存储权限\" | Permission.storage.request() → if !granted → ShowPermissionDenied() |
| 悬浮窗口权限（Android） | 浮动歌词显示\"需要悬浮窗权限\" | Settings.OpenSettings → 引导用户开启 |
| 后台运行权限（MIUI） | 后台播放中断 | MIUI 特殊处理: AutoStart + 电池优化白名单 引导 |

### 12.5 平台差异

| 场景 | Android | iOS |
|------|---------|-----|
| 浮动歌词 | 支持（Native View overlay） | 不支持（隐藏入口） |
| 通知栏控制 | media_session + notification | lock screen controls |
| 蓝牙编解码 | SBC/AAC/ldAC/aptX (取决于硬件) | AAC only |
| 分屏模式 | 支持（android:resizeableActivity=true） | iPad Split View |
| 暗黑模式 |系统级 Night Mode |系统级 Dark Mode |

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

---

## 十五、P1 架构整改补充（v2.3.0）

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

静态动效 token（对齐 AppSpacing/AppRadius 风格）：`durationFast=150ms / durationNormal=250ms / durationSlow=400ms`；`curveStandard=easeOutCubic / curveEmphasized=easeInOutCubicEmphasized / curveDecelerated=easeOutCirc`。新动效统一取值于此，禁止散落 Duration/Curve 字面量。已落地：motion.dart 转场/入场曲线、app_shell.dart 翻页曲线、cover_art.dart fadeIn 时长（精确值替换，行为零变化）；存量与 token 不等值的时长字面量（120/220/300/320ms）待逐处迁移。

### 15.4.1 SettingsRepository 裁量说明

不引入独立 SettingsRepository 抽象层：所有设置已通过各 settings Notifier provider 中转读写，UI 不直连 SharedPreferences（不变量 1 已满足）；直连 prefs 的仅运行时状态（播放状态/断点/转码探测缓存），属持久化而非「设置」。再抽一层只有间接成本、无行为收益。

### 15.5 NetworkSettings 显式注入

见 §4.15 与 §13 不变量 18：`createAdapter(config, secrets, [networkSettings])`，serverAdapterProvider watch 网络设置变更即重建 adapter。

### 15.6 AutoDownload 触发归属

触发点收敛于业务层（main.dart / 收藏成功），播放器不负责：① serverAdapterProvider null→非 null；② 网络切至 Wi-Fi；③ 收藏成功回调。见 §4.8.4。

### 15.7 平台能力矩阵（Platform Capability Matrix）

| 能力 | Common | Android | iOS | iPad |
|------|--------|---------|-----|------|
| 后台音频 | — | audio_service 前台服务 | MediaSession 后台模式 | 同 iOS |
| 锁屏/通知控制 | — | MediaStyle 通知 | 锁屏 Now Playing | 同 iOS |
| 浮动歌词 | — | 悬浮窗权限（SYSTEM_ALERT_WINDOW） | 不支持（入口隐藏） | 不支持 |
| Material You 动态取色 | — | DynamicColorBuilder（仅 MaterialYou 皮肤且未显式选色） | 不适用 | 不适用 |
| 省电低刷新率 | — | FlutterDisplayMode.setLowRefreshRate | 无公开 API，忽略 | 同 iOS |
| 桌面小部件 | — | 未实现（待办） | 未实现（待办） | 未实现 |
| Android Auto / CarPlay | — | 未实现 | 未实现 | — |
| 分屏/多窗口 | — | resizeableActivity=true | — | Split View 支持（响应式布局） |

---

**覆盖级别**: 全量代码逐个字段/方法/枚举/参数/边界情况级细节

**文档版本**: v2.3.0
**生成日期**: 2026-09-07
**最后校对**: 基于 lib/ + features/ 全源码逐文件提取（v2.3.0 对应 LIU_SOUND_AI_FIX_PLAN_V2.md P0+P1 整改后实际代码）
