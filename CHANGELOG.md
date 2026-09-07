# Changelog — 流声 Liu Sound

产品版本号以 `pubspec.yaml` 的 `version` 为唯一事实来源。变更按主题分节，架构侧详情见 `FEATURES.md`（§13 Invariants / §14 Anti-Patterns / §15 P1 整改补充）。

## 2026-09-07（深夜 II）— 列表页统一复用 + 拼音索引
- **歌手列表页**（资料库「歌手」/「专辑艺术家」）：顶部加常驻搜索栏（复用专辑列表 ListSearchBar，按名称或拼音过滤）；右侧 A-Z 索引条支持中文拼音首字母——中文名经 lpinyin 取无音调拼音排序归组（阿悄→A、周杰伦→Z），罕见字转换失败回退 '#' 组
- **流派歌曲列表**：删除独立的 GenreSongsPage，点击流派瓷砖改跳 PlaylistDetailScreen（与歌曲/我喜欢的/歌单同一套 header + 顶部操作栏 + 批量选择结构）；`genreSongsProvider` 改为返回非空 `List<Song>`（后端不支持流派歌曲时返回空列表由页面空态兜底）
- 新增依赖 lpinyin 2.0.3（中文→拼音）

## 2026-09-07（深夜）— 三处导航修复 + 歌手页永远加载根因
- **歌手页永远加载（根因修复）**：`ArtistSongsController` 在 Notifier.build() 返回前同步读写 state，Riverpod 2.6.1 抛 StateError 且请求被吞，页面永远停在初始 loading 态；首取改为 microtask 延迟，并补回归测试（build 期禁止同步改 state）
- **Navidrome 歌手歌曲过滤修正**：`/api/song` 不支持 `artist_id` 过滤器（会被忽略返回全库歌曲），改用参与者过滤 `artists_id`（覆盖专辑艺人+艺人角色，Navidrome ≥0.55）
- 搜索结果专辑行接通专辑详情跳转（此前无点击响应）
- 资料库「专辑艺术家」入口改为进该歌手的专辑列表页（复用 AlbumListPage 网格 + artistAlbumsProvider），「歌手」入口仍进歌曲列表

## 2026-09-07（晚）— 资料库/搜索 UI 对齐 + 封面清晰度
- 歌手详情页移除专辑横滑区，改为圆头像 header + 纯歌曲列表（无专辑有歌的歌手不再被空态卡住）
- 搜索结果歌曲行复用详情页 SongRow：序号 / 长按操作弹窗 / 替换队列整表播放，与详情页行为一致
- 封面源尺寸按显示尺寸×DPR 分档（300/600/900/1200）：全屏播放器大封面不再恒取 300px 源（3x 屏偏糊）；Navidrome/Subsonic adapter 响应 size 参数；模糊背景改用 300 档小图源
- 解码尺寸上限从 300px 放开到显示尺寸×DPR（内存仍受 imageCache 64MB 全局红线约束）

## 2026-09-07 — 架构一致性整改（P0 + P1 + 收尾）

### P0（0b48d33）
- DB v4 迁移：scrobble 队列重试防护字段（played_at/retry_count/last_error/next_retry_at）+ download_index 表
- 下载改为 .tmp + 校验 + 原子 rename + 索引登记后才可用
- 本地歌曲 ID 从 `local:{path}` 迁移为稳定指纹 `local:{md5(size+mtime+头16KB+metadata)}`
- 歌词缓存键分级：服务器 / 本地指纹 / 「标题|歌手」兜底，旧键仍可命中
- Player Restore 严格顺序：RESTORING → 绑定事件 → READY，READY 前禁止自动播放/切歌/上报
- `incrementalSync` 正名为 `versionedSnapshot`；Unsupported / Empty / Failure 语义分离

### P1（f851984 … 650aa91）
- **PlayerActions 拆分**：拆为 player_actions 主库 + 6 个职责 part（源解析/交叉淡化/断点/持久化/恢复/错误处理），行为零变化，外部导入路径不变
- **Shuffle 遍历序**：整队列随机全排列 + 游标，一轮内不重复、previous 可回退，nextSongProvider 预判与实际取歌严格一致
- **Crossfade 语义统一**：crossfade_seconds = 实际淡化时长，固定 100ms tick 派生步数，淡化目标 = UI 预判曲
- **NetworkRuntime 去全局可变状态**：NetworkSettings 经 `createAdapter(config, secrets, networkSettings)` 显式注入 6 个 adapter
- **AutoDownload 触发归属业务层**：adapter 就绪 / Wi-Fi 切换 / 收藏成功三处触发，播放器不再负责
- **AppError 错误模型**：sealed 层级（Network/Auth/Unsupported/NotFound/Permission/Storage/Playback/ServerError），adapter 层 15 处裸 Exception 类型化
- **MotionTokens**：动效时长/曲线统一令牌
- 测试：P1 回归 11 例（错误模型/能力语义/指纹 ID/歌词键/Song 序列化/Shuffle 预判一致性）

### 收尾（e737e4c … b4ce817）
- Shuffle 遍历序随 player_state 持久化，冷启动恢复游标对齐当前歌
- `appUserMessage()` 统一用户侧错误文案（AppError 读 message / 网络异常映射 / 安全兜底），接入登录页与服务器连接检测，不再暴露原始异常串
- MotionTokens 落地 motion.dart / app_shell.dart / cover_art.dart（精确值替换）
- DB-backed 测试：sqflite_common_ffi 驱动，覆盖 v2→v4 迁移、download_index 指纹唯一约束、歌词键三级优先级
- FEATURES.md 对齐至 v2.3.0（§4 播放侧 / §9.1 / §13 / §14 / 新增 §15：拆分说明、ShuffleOrderState、AppError、MotionTokens、平台能力矩阵、SettingsRepository 裁量）

### 评估后维持不做
- SettingsRepository 抽象层（设置已全部经 provider 中转，直连 prefs 仅运行时持久化，见 FEATURES.md §15.4.1）
- Platform 目录物理移动（MethodChannel/Platform.is 分散度低，§15.7 能力矩阵替代）

## 2026-09-06 — 播放体验与资料库优化
- 本地音乐扫描移入后台 isolate + SQLite 缓存（秒开）
- 迷你播放条非双语模式显示下一句歌词
- 设置 tab 移除内层 AppBar，避免与顶部导航双层标题

## 2026-09-05 — 资料库对齐设计图
- 歌曲入口改全部歌曲按加入时间倒序
- 专辑列表 4 列网格 + 常驻搜索栏 + 红色角标
- 本地音乐等歌曲页显示占用空间与文件大小徽标
- 歌单切换修复（ownerName 兜底 / 切换恒可用）

## 2026-09-04 — 主题系统化（v2.1）
- 5 主题皮肤 via SkinTokens ThemeExtension + AppStage/AppSurface 契约
- Liquid Glass 组件库（GlassSurface / AmbientBackground / glassEmptyState）
