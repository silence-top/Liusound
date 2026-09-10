# Liu Sound AI 修复与架构一致性整改方案

> 项目：流声 Liu Sound  
> 文档用途：交给 AI Coding Agent（Qoder / Codex / Cursor / Claude Code 等）执行项目整改  
> 整改性质：**架构一致性修复 + 技术债治理 + 文档/代码对齐**
>
> 本文不是重新设计产品，不是要求重写项目，也不是增加大量新功能。
> 核心目标是：**在保留现有产品功能和 UI 方向的前提下，消除现有实现中的冲突、重复状态源、职责膨胀和文档不一致。**

---

# 0. AI 执行总规则

## 0.1 总目标

本次整改必须遵守：

1. **不推翻现有产品功能。**
2. **不擅自改变现有 UI 信息架构。**
3. **不因为“架构更漂亮”而引入重型 Clean Architecture。**
4. **优先修复真实存在的冲突和风险。**
5. **保持现有 Riverpod + Adapter + SQLite + Design Token 主方向。**
6. **改动必须尽量小步、可验证、可回滚。**
7. **先检查实际源码，再修改；不得仅根据本文猜测代码。**
8. **现有代码与本文描述冲突时，以“实际源码 + 本文目标约束”共同判断，不得盲目复制旧实现。**
9. **禁止为了完成任务引入 Kafka、RabbitMQ、Redis、CQRS、Event Sourcing、复杂 DI Container、复杂调度中心等无必要基础设施。**

---

# 1. 当前项目基线

当前项目为 Flutter 音乐播放器，核心技术栈：

- Flutter
- Riverpod
- just_audio
- audio_service
- SQLite / sqflite
- SharedPreferences
- FlutterSecureStorage
- Dio / HTTP 网络层
- Isolate 本地音乐扫描
- 多后端 Adapter
- Capabilities 驱动 UI
- SkinTokens / GlassTokens Design System

当前支持的后端方向：

- Navidrome
- Subsonic
- Jellyfin
- Emby
- Plex
- Audio Station

当前主要模块：

```text
core/
features/
shared/
shell/
```

现有设计方向应继续保留：

```text
Adapter
Capabilities
Riverpod
SQLite
Local Scan + Isolate
SkinTokens
Glass UI
单一播放器 AudioPlayer
```

---

# 2. 本次整改优先级

## P0：必须完成

### P0-01 文档版本定义统一

当前文档存在产品版本、功能版本、依赖版本描述不一致的问题。

要求：

- 产品版本只维护一个事实来源。
- 依赖具体版本以 `pubspec.yaml` 为准。
- FEATURES.md 不再复制维护所有 dependency version。
- 文档版本与产品版本分离。

建议：

```text
Document Version: 2.2.0
Product Version: 2.1.x
Dependency Source of Truth: pubspec.yaml
```

---

# 3. P0-02 数据库 Schema 必须统一

## 当前问题

文档不同章节对数据库表数量和字段描述存在冲突。

出现过：

```text
scrobble_queue
library_snapshot
lyrics_local
local_scan_cache
autoplay_queue
```

但其他章节仍描述为 3 张表。

同时 `scrobble_queue` 存在两套 schema 定义：

### 方案 A

```text
id
server_id
song_id
created_at
```

### 方案 B

```text
id
song_id
played_at
created_at
flushed
```

必须统一。

---

## 目标 Schema

本阶段建议统一为：

```text
library_snapshot
local_scan_cache
lyrics_local
scrobble_queue
download_index
```

`autoplay_queue` 暂不作为独立持久化状态源。

播放器运行时队列继续使用：

```text
QueueProvider / QueueNotifier
```

作为唯一 Source of Truth。

---

# 4. P0-03 Remote Library 不再称为“真正增量同步”

当前实现实际上更接近：

```text
libraryVersion
    ↓
版本相同
    ↓
读取本地 snapshot

版本变化
    ↓
重新 fetch 完整列表
    ↓
替换 snapshot
```

这属于：

> Versioned Library Snapshot

而不是 Delta / Incremental Sync。

## 修改要求

将：

```text
incrementalSync
```

在文档语义上调整为：

```text
versionedSnapshot
```

或：

```text
remoteLibrarySnapshot
```

保留现有逻辑，不要求当前阶段实现真正的 added/updated/deleted delta sync。

未来若服务器真正支持：

```text
added
updated
deleted
```

再升级成真正 Delta Sync。

---

# 5. P0-04 ServerAdapter 能力模型整改

## 当前问题

`ServerAdapter` 已经承担：

- Auth
- Library
- Search
- Playlist
- Rating
- Lyrics
- Artist
- Genre
- Scrobble
- Playback
- Download
- Transcode
- Cover
- Session

接口已经明显偏胖。

同时存在：

```text
Capability=false
```

但 API 仍然返回：

```text
Future<List<T>>
```

容易把：

```text
Unsupported
Empty
Failure
```

混为一谈。

---

## 目标

保留：

```text
ServerAdapter
```

但逐步按能力拆分：

```text
AuthCapability
LibraryCapability
SearchCapability
PlaylistCapability
PlaybackCapability
LyricsCapability
RatingCapability
ScrobbleCapability
DownloadCapability
ArtistCapability
```

不要求一次拆完全部代码。

优先从新增/高频能力开始，保证：

> Adapter 不再继续无限膨胀。

---

# 6. Unsupported / Empty / Failure 必须分开

禁止：

```text
null = 不支持 / 空结果 / 请求失败
```

必须明确区分：

```text
Unsupported
Empty
Failure
```

建议引入：

```dart
UnsupportedCapabilityException
```

或者统一错误模型。

例如：

```dart
sealed class AdapterError {}
class UnsupportedCapabilityError extends AdapterError {}
class NetworkError extends AdapterError {}
class ServerError extends AdapterError {}
class NotFoundError extends AdapterError {}
class ParseError extends AdapterError {}
```

要求：

- 空列表表示“支持此能力，但没有数据”。
- Unsupported 表示“后端不提供该能力”。
- Failure 表示“本次请求失败”。

---

# 7. P0-05 本地音乐扫描方案统一

当前文档存在两套描述：

```text
Isolate.run(...)
```

以及：

```text
compute
SendPort
ReceivePort
```

还存在“Isolate 是否直接写 SQLite”的描述冲突。

## 统一目标

采用单一流程：

```text
LocalLibraryService
        ↓
LocalScanWorker
        ↓
Isolate.run()
        ↓
文件发现
Metadata 解析
Fingerprint
Cover 提取
        ↓
ScanResult
        ↓
Main Isolate
        ↓
LocalLibraryRepository
        ↓
SQLite Transaction
```

---

## Isolate 负责

- 文件遍历
- 音频 metadata 解析
- fingerprint 计算
- 基础音频信息
- 内嵌封面提取

## Repository 负责

- SQLite
- transaction
- upsert
- delete
- query

## Provider 负责

- loading
- error
- refresh
- 页面状态

禁止：

```text
Widget → FileSystem
Widget → SQLite
Provider → 长时间文件扫描
```

---

# 8. P0-06 Cache 与 Download 必须完全分离

这是本项目的关键整改项。

## AudioCache

定位：

```text
临时播放缓存
自动清理
LRU
容量限制
可被系统回收
```

## DownloadLibrary

定位：

```text
用户下载
长期保存
用户主动删除
默认不参与播放 Cache LRU
```

禁止两个系统共用同一个容量限制概念。

---

# 9. AutoDownload 修复

当前逻辑存在：

```text
AutoDownload
    ↓
downloadSongFile()
    ↓
AudioCache.enforceLimit()
```

但下载文件和 AudioCache 实际可能不在同一个目录。

这会产生“清理不到自动下载”的问题。

## 修改要求

统一成：

```text
AutoDownloadService
       ↓
DownloadLibrary
       ↓
DownloadIndex
```

AudioCache：

```text
AudioCache
```

独立管理。

---

# 10. P0-07 增加 DownloadIndex

禁止长期使用：

```text
遍历 Music 目录所有文件
```

作为每次：

```text
findDownloadedSong()
```

的查询方式。

新增：

```text
download_index
```

建议字段：

```text
id
server_id
song_id
fingerprint
path
size
created_at
last_accessed_at
```

要求支持：

- 查询已下载歌曲
- 更新下载状态
- 删除下载记录
- 统计下载大小
- 检查文件是否仍然存在
- 避免重复下载

---

# 11. P0-08 Local Song ID 必须稳定

当前：

```text
local:${file.path}
```

不适合作为长期稳定的歌曲 ID。

移动文件、换目录、换存储位置都会导致 ID 改变。

## 修改目标

采用：

```text
local:{fingerprint}
```

例如：

```text
local:a8f31c...
```

fingerprint 可基于：

```text
file size
mtime
partial file hash
音频基础 metadata
```

具体实现必须结合现有扫描性能，不允许每次完整读取超大音频文件。

---

# 12. P0-09 Lyrics Cache Key 调整

当前：

```text
title|artist
```

存在碰撞风险。

优先级：

```text
服务器歌曲:
serverId + songId

本地歌曲:
local fingerprint

兜底:
normalized title + artist + album
```

建议：

```text
lyrics:{serverId}:{songId}
```

或：

```text
lyrics:local:{fingerprint}
```

---

# 13. P0-10 Scrobble Queue 统一

最终推荐：

```text
scrobble_queue

id
server_id
song_id
played_at
created_at
```

不建议继续保留：

```text
flushed
```

成功上报：

```sql
DELETE
```

失败：

```text
保留
```

队列本质是：

> Pending Queue

不是历史播放表。

---

# 14. P0-11 禁止第二套 Playback Queue

现有：

```text
QueueProvider
QueueNotifier
```

继续作为：

> 唯一运行时播放队列 Source of Truth。

不要再引入：

```text
autoplay_queue
```

作为第二套运行时队列。

如果需要重启恢复：

```text
player_state
```

保存：

```text
queue
currentSong
currentIndex
position
playMode
```

---

# 15. P0-12 Architecture Invariants

新增章节：

```text
Architecture Invariants
```

必须明确：

1. UI 不直接访问 Dio。
2. UI 不直接访问 SQLite。
3. UI 不直接访问 SharedPreferences。
4. Provider 不负责长时间 IO。
5. Adapter 不依赖 Flutter Widget。
6. Repository 是数据库访问唯一入口。
7. PlayerController 是 AudioPlayer 唯一 owner。
8. QueueProvider 是运行时播放队列唯一 Source of Truth。
9. ServerAdapter 不负责 UI 状态。
10. Platform-specific API 必须隔离。
11. 业务 UI 不允许硬编码颜色。
12. Local Song ID 必须基于稳定 fingerprint。
13. Server Song ID 与 Local Song ID 必须命名空间隔离。
14. Unsupported / Empty / Failure 必须不同语义。
15. Cache 与 Download 必须完全分离。
16. 不允许创建第二个播放队列状态源。
17. 不允许无必要增加 global mutable singleton。
18. Feature 内不得直接创建 Dio / SQLite 实例。

---

# 16. P0-13 Anti-Patterns

新增：

```text
Anti-Patterns
```

禁止：

```text
Widget 中调用 Dio
Widget 中访问 SQLite
Widget 中直接读 SharedPreferences
Provider 中进行无限/长时间扫描
多处创建 AudioPlayer
创建第二套 queue state
使用 path 作为 Local Song ID
Cache / Download 混用目录
随机 next 实现完整 shuffle
Exception.toString() 驱动 UI 错误分类
新增 global mutable singleton
业务组件硬编码 Color(...)
Capability=false 后仍假定能力存在
用 null 同时表示 unsupported / empty / failure
```

---

# 17. P1：PlayerActions 拆分

当前 PlayerActions 已经承担大量职责，已经出现 God Object 趋势。

不要直接重写播放系统。

采用渐进式拆分：

```text
player/
├── player_controller.dart
├── player_actions.dart
├── player_queue.dart
├── player_source_resolver.dart
├── player_restore.dart
├── player_persistence.dart
├── player_crossfade.dart
├── player_breakpoint.dart
└── player_error_handler.dart
```

---

# 18. PlayerController 职责

只负责：

```text
AudioPlayer 生命周期
播放器核心事件
播放状态桥接
```

不负责：

```text
SQLite
SharedPreferences
Download
Scrobble
Network settings
```

---

# 19. PlayerQueue 职责

负责：

```text
add
replace
remove
reorder
next
previous
insertAfterCurrent
shuffle
repeat
```

---

# 20. PlayerSourceResolver

负责：

```text
本地文件
已下载歌曲
服务器直连
服务端转码
Fallback
Unavailable
```

建议统一优先级：

```text
1. 有效本地文件
2. 有效下载文件
3. Server direct stream
4. Server transcode
5. fallback
6. unavailable
```

具体是否调整顺序必须结合现有播放行为，不要无理由改变用户体验。

---

# 21. Shuffle 必须避免随机重复

当前：

```text
随机挑选非当前歌曲
```

不足以实现高质量 shuffle。

建议维护：

```text
shuffleOrder
shuffleIndex
```

例如：

```text
queue:
A B C D E

shuffleOrder:
C A E B D
```

这样：

```text
next
previous
```

都有稳定历史。

要求：

- 不重复当前项。
- 尽可能完整遍历队列后再重新生成。
- Previous 能正确回退。
- 修改队列后正确重建 shuffle order。

---

# 22. Crossfade 规格统一

当前文档对：

```text
0~10 秒
24 steps
约 0.8 秒
```

存在语义冲突。

统一：

```text
crossfadeSeconds = 实际淡化时长
```

例如：

```text
0 = disabled
1~10 = actual seconds
```

实现可以使用：

```text
50ms ~ 100ms
```

级别的 tick。

不要固定“24 steps”作为业务语义。

业务配置必须等于实际用户体验。

---

# 23. P1：NetworkRuntime 去掉全局可变配置

当前存在：

```text
NetworkRuntime.settings = net
```

这种 global mutable state。

建议：

```text
NetworkSettings
      ↓
AdapterDependencies
      ↓
Adapter
```

例如：

```dart
createAdapter(
  config,
  secrets,
  networkSettings,
);
```

目标：

- Server A 不影响 Server B。
- 网络设置变化具有明确生命周期。
- Adapter 不读取隐式全局状态。

---

# 24. P1：SettingsRepository

当前 SharedPreferences 被多个模块直接使用。

引入：

```text
SettingsRepository
        ↓
SharedPreferences
```

Provider / Controller：

```text
Provider
   ↓
SettingsRepository
```

分组：

```text
player settings
streaming settings
network settings
theme settings
UI settings
cache settings
```

目标：

> SharedPreferences 只是存储实现，不是业务 API。

---

# 25. P1：Error Model

建议定义：

```text
AppError
├── NetworkError
├── AuthError
├── UnsupportedError
├── NotFoundError
├── PermissionError
├── StorageError
├── PlaybackError
└── ServerError
```

目标流程：

```text
Adapter
 ↓
AdapterError
 ↓
Service
 ↓
AppError
 ↓
Provider
 ↓
UI
```

禁止 UI 根据：

```text
Exception.toString()
```

判断具体错误类型。

---

# 26. P1：ServerConfig / ServerSecrets 分离

推荐：

```text
ServerConfig
├── id
├── type
├── url
├── displayName
└── metadata
```

Secret：

```text
ServerSecrets
├── username
├── password
├── token
└── session
```

存储：

```text
ServerConfig → 普通持久化
ServerSecrets → FlutterSecureStorage
```

UI 不应该持有 password/token 等敏感数据。

---

# 27. P1：Design System 完整化

当前：

```text
SkinTokens
GlassTokens
AppSkin
```

继续保留。

新增：

```text
ColorTokens
TypographyTokens
SpacingTokens
ShapeTokens
MotionTokens
ElevationTokens
GlassTokens
```

---

# 28. 禁止业务 UI 硬编码颜色

如果已有：

```dart
Color(0xFF...)
Colors.white.withOpacity(...)
```

且属于业务语义，应逐步改成：

```text
context.colors.error
context.colors.surface
context.colors.onSurface
context.colors.onSurfaceSecondary
context.colors.divider
context.colors.success
context.colors.warning
```

注意：

纯装饰、第三方 API、Canvas painter 内部允许存在必要的底层颜色，但不得破坏业务 Design Token 体系。

---

# 29. P1：Motion Tokens

新增：

```text
MotionTokens
```

建议至少包含：

```text
durationFast
durationNormal
durationSlow

curveStandard
curveEmphasized
curveDecelerated
```

统一：

- Page transition
- Sheet
- MiniPlayer
- Fade
- AnimatedSize
- AnimatedOpacity
- List entrance

---

# 30. P1：Platform Capability Matrix

必须明确：

```text
Common
Android
iOS
iPad
```

至少覆盖：

```text
Background Audio
Lock Screen
Notification
Floating Lyrics
Material You
Dynamic Island
Android Auto
CarPlay
Split View
Widgets
```

Platform-specific 代码统一隔离。

---

# 31. P1：Platform 目录规范

建议：

```text
platform/
├── android/
│   └── floating_lyrics/
└── ios/
    ├── widgets/
    └── carplay/
```

Common 层不要散落：

```text
MethodChannel(...)
Platform.isAndroid
Platform.isIOS
```

平台判断应尽量集中。

---

# 32. P1：AutoDownload 从 PlayerActions 移出

不要：

```text
PlayerActions constructor
    ↓
maybeAutoDownload()
```

应该：

```text
AutoDownloadController
        ↓
Auth
Settings
Connectivity
        ↓
DownloadLibrary
```

播放器不负责自动下载业务。

---

# 33. P1：Scrobble 保持独立

继续保持：

```text
ScrobbleService
```

监听：

```text
position
connectivity
```

Player 不直接负责 Scrobble Queue。

---

# 34. P1：状态 Source of Truth

必须建立以下规则：

| 状态 | Source of Truth |
|---|---|
| position | AudioPlayer |
| playing | AudioPlayer |
| duration | AudioPlayer |
| currentSong | PlayerController |
| queue | QueueProvider |
| playMode | PlayModeProvider |
| settings | SettingsRepository |
| server session | AuthController / AuthRepository |
| remote library | LibraryRepository |
| local library | LocalLibraryRepository |
| download | DownloadIndex |
| lyrics | LyricsRepository |

禁止为同一状态建立第二个长期状态源。

---

# 35. P1：Remote Library Snapshot 保留现有实现

当前：

```text
library_snapshot
```

可以继续使用。

不要求现在立即改成：

```text
songs
albums
artists
playlist_songs
```

只有当以下情况出现时再考虑 normalized SQLite：

```text
> 50,000 songs
```

或者：

```text
搜索明显变慢
排序明显变慢
内存显著增长
```

当前目标：

> 先保证正确性和稳定性，再考虑极端规模优化。

---

# 36. P2：SQLite Normalization

未来可升级：

```text
songs
albums
artists
genres
playlists
playlist_songs
library_meta
```

并以：

```text
library_meta.version
```

管理服务器版本。

当前阶段：

> 不强制实施。

---

# 37. P2：Local Scan Cache 优化

当前：

```text
path
mtime
size
```

继续支持快速命中。

可逐步增加：

```text
fingerprint
metadata_hash
scan_version
```

目标：

```text
未变化文件 → 不解析
变化文件 → 只重扫该文件
```

---

# 38. 性能要求

必须关注：

## 首次曲库

避免：

```text
每次启动都全量网络请求
```

## 本地音乐

避免：

```text
主 isolate 阻塞
```

## Download

避免：

```text
每次播放遍历整个 Music 目录
```

## Queue

避免：

```text
播放下一首重新随机全队列
```

## UI

避免：

```text
1000+ item Widget 一次性 build
```

---

# 39. 测试要求

## Unit Test

至少覆盖：

```text
Server URL normalization
Fingerprint
Song.fromJson
Unsupported capability
Library snapshot
ShuffleOrder
Crossfade
Scrobble queue
DownloadIndex
Lyrics cache key
```

## Widget Test

至少覆盖：

```text
MiniPlayer
Player
Library
Search
Settings
SongList
```

## Integration Test

至少覆盖：

```text
Login
Server switching
Play
Pause
Next
Previous
Queue
Download
Local scan
Scrobble retry
Playback restore
```

---

# 40. Migration 要求

每次数据库结构变化必须：

```text
version N
    ↓
migration N+1
```

禁止：

```text
直接删数据库
```

除非明确是开发环境破坏性迁移。

生产环境必须：

```text
旧数据可迁移
```

---

# 41. 代码修改顺序

AI 必须按照以下顺序执行：

## Phase 1

```text
1. 检查实际源码
2. 建立当前结构报告
3. 确认当前实际数据库 schema
4. 确认当前实际 PlayerActions
5. 确认当前实际 Local Scan
6. 确认当前实际 Download
7. 确认当前实际 Adapter
```

### 禁止直接修改。

先确认现实状态。

---

## Phase 2

修复 P0：

```text
Schema
Scrobble
Queue
Local ID
Lyrics key
Cache / Download
Local scan
Capability semantics
Snapshot naming
```

---

## Phase 3

修复 P1：

```text
PlayerActions
NetworkRuntime
SettingsRepository
Error Model
Design Tokens
Platform
AutoDownload
```

---

## Phase 4

补测试：

```text
Unit
Widget
Integration
Migration
```

---

## Phase 5

更新 FEATURES.md

必须做到：

> 文档描述 = 实际代码。

禁止继续保留已经废弃的旧方案。

---

# 42. Git 提交建议

不要一个 commit 改完整个项目。

建议：

```text
refactor: normalize database schema
refactor: separate cache and download systems
refactor: stabilize local song identity
refactor: clarify adapter capability semantics
refactor: split player responsibilities
refactor: remove mutable network runtime state
refactor: introduce settings repository
refactor: introduce app error model
refactor: normalize design tokens
test: add architecture regression tests
docs: update features specification
```

这样方便回滚和定位问题。

---

# 43. AI 实施过程中的禁止事项

## 禁止 1

为了拆 Adapter，突然引入巨大 Domain Layer。

## 禁止 2

为了管理状态，新增复杂状态机。

## 禁止 3

为了下载系统，引入复杂任务调度中心。

## 禁止 4

为了缓存，引入 Redis。

## 禁止 5

为了同步，引入 Event Sourcing。

## 禁止 6

为了“解耦”，创建几十个空壳 Service。

## 禁止 7

大规模一次性重命名所有文件，导致无法 review。

## 禁止 8

改变用户已有 UI 行为而不说明。

## 禁止 9

修改依赖版本而没有必要。

## 禁止 10

删除旧数据或数据库而不提供 migration。

---

# 44. 验收标准

整改完成后必须满足：

### 架构

```text
UI
 ↓
Provider / Controller
 ↓
Service
 ↓
Repository / Adapter
 ↓
External API / SQLite / FileSystem
```

---

### 播放

```text
PlayerController
    ↓
PlayerQueue
    ↓
PlayerSourceResolver
    ↓
AudioPlayer
```

---

### Remote Library

```text
Adapter
    ↓
LibraryService
    ↓
Versioned Snapshot
    ↓
SQLite
```

---

### Local Library

```text
LocalLibraryService
    ↓
Isolate
    ↓
ScanResult
    ↓
Repository
    ↓
SQLite
```

---

### Download

```text
DownloadService
    ↓
DownloadLibrary
    ↓
DownloadIndex
```

与：

```text
AudioCache
```

完全分离。

---

### Settings

```text
Provider
 ↓
SettingsRepository
 ↓
SharedPreferences
```

---

### Error

```text
AdapterError
 ↓
AppError
 ↓
Provider
 ↓
UI
```

---

# 45. 最终完成检查表

## P0

- [ ] 版本定义统一
- [ ] 数据库表定义统一
- [ ] scrobble schema 统一
- [ ] autoplay_queue 不再作为第二队列
- [ ] Library Snapshot 命名统一
- [ ] Adapter Unsupported 语义统一
- [ ] Local Scan 实现统一
- [ ] Cache / Download 分离
- [ ] DownloadIndex
- [ ] Local Song Fingerprint
- [ ] Lyrics Cache Key
- [ ] Architecture Invariants
- [ ] Anti-Patterns

## P1

- [ ] PlayerActions 拆分
- [ ] ShuffleOrder
- [ ] Crossfade 语义统一
- [ ] NetworkRuntime 去 global mutable
- [ ] SettingsRepository
- [ ] AppError
- [ ] ServerConfig / Secret 分离
- [ ] Design Tokens
- [ ] Motion Tokens
- [ ] Platform Matrix
- [ ] AutoDownload 独立
- [ ] PlayerSourceResolver

## P2

- [ ] normalized SQLite
- [ ] 本地扫描进一步优化
- [ ] 完整 Integration Test
- [ ] Performance Benchmark

---

# 46. 最终架构目标

整改完成后的核心关系：

```text
                         ┌─────────────────────┐
                         │      Flutter UI     │
                         └──────────┬──────────┘
                                    │
                         ┌──────────▼──────────┐
                         │ Provider / Controller│
                         └──────────┬──────────┘
                                    │
             ┌──────────────────────┼──────────────────────┐
             │                      │                      │
     ┌───────▼───────┐      ┌───────▼───────┐      ┌───────▼───────┐
     │ Player Layer  │      │ Library Layer │      │ Settings Layer│
     └───────┬───────┘      └───────┬───────┘      └───────┬───────┘
             │                      │                      │
     ┌───────▼───────┐      ┌───────▼────────┐      ┌───────▼────────┐
     │AudioPlayer    │      │Repository      │      │SettingsRepo    │
     │Queue          │      │Adapter         │      │                │
     │SourceResolver │      │LocalWorker     │      │                │
     └───────────────┘      └───────┬────────┘      └───────┬────────┘
                                    │                       │
                           ┌────────▼────────┐      ┌───────▼────────┐
                           │ SQLite / File   │      │SharedPreferences│
                           └─────────────────┘      └─────────────────┘
```

---

# 47. 最重要原则

本项目本次整改的核心不是：

> “把代码改得更复杂。”

而是：

> **把每一个状态、每一个职责、每一种失败语义、每一种持久化方式都确定唯一归属。**

重点解决：

```text
谁负责？
谁保存？
谁读取？
谁是 Source of Truth？
什么是不支持？
什么是空数据？
什么是失败？
什么是缓存？
什么是下载？
什么属于平台？
什么属于业务？
```

回答清楚这些问题以后，后续增加功能时才能继续保持稳定。

---

# 48. AI 最终执行指令

请严格按照本文执行：

1. **先扫描实际代码，不要立即重构。**
2. 输出当前实际结构与本文目标之间的差异。
3. 优先处理 P0。
4. 每完成一个逻辑域后运行对应测试。
5. 不修改无关功能。
6. 不改变现有 UI 信息架构。
7. 不引入本文未要求的大型基础设施。
8. 保留兼容能力，必要时添加 migration。
9. 最终必须同步更新 FEATURES.md。
10. 最终输出：
   - 修改文件列表
   - 每个文件的修改目的
   - 数据库 migration
   - 测试结果
   - 未完成项
   - 潜在风险

**禁止以“理论上可行”作为完成标准。必须以实际代码、实际编译和实际测试结果作为完成标准。**

---

# 49. P0-CF-01 单 AudioPlayer Crossfade 物理约束

当前播放器架构使用单一 `AudioPlayer`。

必须明确：

> 单个 `AudioPlayer` 在本架构下只允许维持一个当前播放源，不得尝试使用单 Player 同时解码并叠加两条独立音频流。

因此，本项目 Crossfade 的定义为：

```text
当前歌曲接近结束
        ↓
Fade Out / Volume Ramping
        ↓
当前 AudioSource 结束
        ↓
切换到下一首 AudioSource
        ↓
Fade In / Volume Ramping
```

这是：

```text
Soft Transition / Volume Ramping
```

不是：

```text
True Overlap Crossfade
```

AI 禁止：

- 在单 `AudioPlayer` 上创建双流重叠播放。
- 尝试在同一个 Player 内同时解码两个独立音源。
- 为实现 Crossfade 擅自增加第二个 `AudioPlayer`。
- 以两个 `AudioSource` 同时输出为前提设计当前 Crossfade。

如果未来需要真正的双流重叠 Crossfade，必须作为独立的播放内核架构升级，不属于本次整改范围。

---

# 50. P0-ID-01 Local Fingerprint 性能约束

Local Song Fingerprint 必须是：

> **轻量身份指纹，而不是完整文件完整性校验。**

严禁默认读取整个大文件执行：

```text
MD5(full_file)
SHA1(full_file)
SHA256(full_file)
```

尤其禁止对大规模 FLAC / APE / WAV 曲库进行全量 Hash。

推荐算法：

```text
fingerprint =
MD5(
    file_size
    + mtime
    + first_16KB
    + normalized_title
    + normalized_artist
    + normalized_duration
)
```

可选增强：

```text
+ last_16KB
```

但不得因此读取整个文件。

要求：

1. `file_size` 必须参与。
2. `mtime` 必须参与。
3. 文件头只读取固定小块，例如 16KB。
4. metadata 参与。
5. fingerprint 计算运行于 `Isolate.run()`。
6. 对超大文件不得产生与文件大小线性增长的无谓 IO。
7. fingerprint 用于本地歌曲身份和扫描缓存命中，不代表完整文件内容校验。
8. 如未来提供“完整性校验”，必须设计为用户主动操作，不得作为默认扫描动作。

---

# 51. P0-SC-01 Scrobble Queue 永久阻塞防护

`scrobble_queue` 不得因为单条永久失败记录阻塞整个队列。

最终建议字段：

```text
id
server_id
song_id
played_at
created_at
retry_count
last_error
next_retry_at
```

错误分类：

## 网络错误 / Timeout

```text
retryable = true
```

采用指数退避，例如：

```text
1m
2m
4m
8m
16m
```

## HTTP 5xx

```text
retryable = true
```

采用指数退避。

## HTTP 4xx

例如：

```text
400
401
403
404
```

如果确认属于客户端不可恢复错误：

```text
retryable = false
```

不得永久留在 pending 队列。

## 最大重试

默认：

```text
5
```

超过最大次数：

```text
archive
```

或从 pending queue 移除。

## Flush 规则

只处理：

```text
next_retry_at IS NULL
OR
next_retry_at <= now
```

不能每次定时任务无条件重复发送失败记录。

单条不可恢复记录不得导致后续正常记录永久无法发送。

---

# 52. P0-LIB-01 大 JSON Snapshot Isolate 约束

当前阶段允许继续使用：

```text
library_snapshot.payload
```

保存完整 JSON TEXT。

但是：

> 大型 JSON 的 encode / decode 必须在 `Isolate.run()` 中完成。

禁止主 Isolate 直接执行大型：

```dart
jsonDecode(payload)
jsonEncode(largeLibrary)
```

推荐：

```text
SQLite
   ↓
payload String
   ↓
Isolate.run(jsonDecode)
   ↓
typed model list
   ↓
Main Isolate
   ↓
Provider
```

写入：

```text
typed model list
   ↓
Isolate.run(jsonEncode)
   ↓
payload String
   ↓
SQLite
```

建议设置大小阈值：

```text
payload > 256KB
```

时强制 worker isolate。

具体阈值允许基于真实 benchmark 调整。

同时避免 Main Isolate 长时间同时持有：

```text
raw JSON
+
decoded list
+
duplicate transformed list
```

大对象生命周期应尽量短。

---

# 53. P0-DB-01 SQLite Migration 数据安全约束

生产数据库 Migration 默认禁止未经保护的数据破坏。

禁止直接：

```sql
DROP TABLE
DELETE FROM user_data
```

作为普通 schema 修改手段。

允许使用 destructive operation 的场景仅限：

1. 对象明确属于临时缓存。
2. 没有用户数据价值。
3. 本次 migration 明确说明其破坏性影响。

新增表：

```sql
CREATE TABLE IF NOT EXISTS ...
```

新增字段：

```sql
ALTER TABLE ... ADD COLUMN ...
```

复杂表结构修改必须采用：

```text
create_new_table
        ↓
copy / transform old data
        ↓
validate
        ↓
atomic switch / rename
        ↓
旧表清理
```

必须保证：

- version 明确递增。
- migration 顺序确定。
- 可以从历史版本升级。
- 不主动删除用户下载、歌词、未上报 Scrobble 等用户数据。
- migration 中途失败时尽量保留旧数据。
- migration 完成前不得认为新结构已经生效。

---

# 54. P0-PLAYER-01 Player Restore 严格初始化顺序

播放器恢复必须是单向、可观测的初始化流程。

推荐状态：

```text
CREATED
   ↓
RESTORING
   ↓
QUEUE_RESTORED
   ↓
CURRENT_SONG_RESTORED
   ↓
POSITION_RESTORED
   ↓
EVENTS_BOUND
   ↓
READY
```

严格顺序：

```text
Restore Queue
    ↓
Restore Current Song
    ↓
Seek Position
    ↓
Bind Player Events
    ↓
Ready
```

恢复阶段：

```text
isRestoring = true
```

必须禁止：

- 自动播放。
- Scrobble 上报。
- Crossfade。
- AutoDownload 触发。
- `processingState == completed` 自动跳下一首。
- 由于 restore 导致的新断点持久化。
- restore 过程中再次调用 restore。
- 因恢复过程触发页面导航。

只有：

```text
READY
```

之后才进入正常事件处理。

Restore 失败：

```text
安全降级到空队列 / 默认状态
```

禁止：

```text
无限 restore loop
```

ScrobbleService 必须能识别：

```text
playerReady == false
```

并忽略恢复期间产生的 position 状态。

---

# 55. P0-DL-01 Download 原子写入

用户下载必须采用临时文件 + 原子提交。

推荐：

```text
download.tmp
    ↓
完整下载
    ↓
校验
    ↓
atomic rename
    ↓
写入 download_index
```

禁止直接把不完整下载写入最终文件名。

如果下载中途失败：

```text
临时文件可以保留用于续传
```

但：

```text
最终下载路径
```

不得被认为有效。

只有：

```text
下载完成
+
校验成功
+
index 更新成功
```

才认为下载可用。

---

# 56. P0-DL-02 DownloadIndex / File Consistency

`download_index` 与实际文件必须最终一致。

查询到：

```text
DB record exists
```

不能直接认为文件一定存在。

播放/读取下载文件时应检查：

```text
File.exists()
```

如果：

```text
DB 有记录
但文件不存在
```

执行：

```text
lazy repair
    ↓
删除失效 index
    ↓
重新 resolve source
```

不要让坏的 download index 永久阻塞播放。

---

# 57. P1-BG-01 Background Task Concurrency

后台任务必须具备生命周期控制：

```text
LocalScan
LibrarySync
AutoDownload
ScrobbleFlush
```

同类型任务禁止无限并发。

至少具备：

```text
running guard
cancellation / stale detection
duplicate prevention
```

特别是服务器切换场景：

```text
Server A sync
        ↓
切换 Server B
        ↓
Server B sync
```

旧 Server A 任务不得把结果写入 Server B 的状态或缓存。

任何异步结果写入前应确认：

```text
serverId / taskGeneration
```

仍然有效。

---

# 58. P0 完整清单（更新版）

```text
P0-01  版本/文档事实来源统一
P0-02  数据库 Schema 统一
P0-03  Remote Library Snapshot 语义统一
P0-04  Adapter Capability 语义统一
P0-05  Local Scan 实现统一
P0-06  Cache / Download 完全分离
P0-07  DownloadIndex
P0-08  Local Fingerprint
P0-09  Lyrics Cache Key
P0-10  Scrobble Queue 永久阻塞防护
P0-11  单 AudioPlayer Crossfade 物理约束
P0-12  大 JSON Snapshot Isolate
P0-13  SQLite Migration 数据安全
P0-14  Player Restore 严格顺序
P0-15  禁止第二套 Playback Queue
P0-16  Download 原子写入
P0-17  DownloadIndex/File 一致性
P0-18  Architecture Invariants
P0-19  Anti-Patterns
```

---

# 59. AI 最终执行硬约束

在任何代码修改前：

```text
1. 阅读实际源码。
2. 找到真实 Source of Truth。
3. 对照本计划标记差异。
4. 不根据旧文档猜测不存在的代码。
5. 不一次性重写整个模块。
```

每个 P0 任务完成后：

```text
修改
 ↓
format
 ↓
analyze
 ↓
unit test
 ↓
integration test（适用时）
 ↓
review diff
```

最终必须输出：

```text
1. 修改文件
2. 删除文件
3. 新增文件
4. 数据库 migration
5. API / model 变化
6. 测试结果
7. 未解决问题
8. 潜在回归风险
```

---

# 60. 不允许的“伪完成”

以下情况不得声明完成：

```text
代码能编译
```

但：

```text
Migration 未验证
Download 未验证
Restore 未验证
Scrobble Retry 未验证
Local Scan 未验证
```

也不得因为：

```text
测试数量增加
```

而认为架构整改完成。

完成标准必须是：

```text
源码
=
文档
=
测试
=
实际行为
```

---

# 61. 修改原则

本次整改优先级：

```text
Correctness
    >
Data Safety
    >
Lifecycle Safety
    >
Performance
    >
Maintainability
    >
Architecture Elegance
```

不要为了：

```text
“看起来更 Clean”
```

而增加无实际价值的抽象层。

