# Changelog — 流声 Liu Sound

产品版本号以 `pubspec.yaml` 的 `version` 为唯一事实来源。变更按主题分节，架构侧详情见 `FEATURES.md`（§13 Invariants / §14 Anti-Patterns / §15 P1 整改补充）。

## 2026-09-08 — P3 主题整改：评分金/音质色板入 AppTheme + 黑胶拟物色收拢
- **评分金令牌**：新增 `AppTheme.ratingGold`（0xFFFFC53D），star_rating 默认色与空星灰（改 textFaintOf，随皮肤走）接入，消除硬编码
- **音质徽标色板入 AppTheme**：quality_badge 三档 Hi-Res（金色琥珀）/无损（沿用 formatBorder/formatBg/formatText）/有损（中灰半透明）全部改引用 AppTheme 常量；P0 清理时误删的 format* 令牌补回（无损档仍在用）
- **黑胶拟物色收拢 `_VinylPalette`**：full_screen_player 黑胶盘面三层径向渐变、CD 六色扫光、CD 轴心/中孔、唱臂银色渐变、唱头壳、支点阴影/高光共 8 处写死色收拢为私有常量类——拟物装饰色按审计约定保持皮肤无关，集中管理便于后续调整

## 2026-09-08 — P2 主题整改：六页硬编码颜色令牌化清扫
- **settings_screen（约 80 处）**：分组卡/开关行/弹窗与底部弹层文本模板全部接入 textPrimary/textDim/textFaint，危险操作红统一 `AppTheme.heartRed`（原 Colors.redAccent），滑块 inactive、筛选胶囊边框接 borderHairline/textFaint
- **full_screen_player**：顶栏/歌曲区/歌手简介/歌词页/底部控制区文本与图标令牌化；Tab 胶囊高亮改 `Color.lerp(textDim, textPrimary, t)`；歌词渐变遮罩由写死 #0a1428ee 改为 `_lyricFadeColor(context)`（SkinTokens.background × 0.93，随皮肤走）；歌词当前行/译文白阶、音量胶囊填充（改 colorScheme.primary）、进度条三色、收藏红（0xFFE57373 与 heartRed 去重）全部令牌化；黑胶/CD 拟物色与阴影 scrim 按约定保留
- **detail_screen**：搜索栏图标/占位 0xFF888888/0xFFAAAAAA → textFaint，副标题 0xFFBBBBBB → textDim，封面占位容器 0xFF1A2C3A → surface，分隔线 → divider，播放全部圆钮底色 → colorScheme.primary×0.18，禁用态 white24 → textFaint；`_filterAction/_action` 补 BuildContext 传参
- **music_library_screen**：首页搜索栏/资料库搜索框容器白 0.07 → surface，分隔线 → divider，队列占位图标 → textFaint
- **servers_screen / server_detail_screen**：文本与图标令牌化，redAccent 全部统一 heartRed，服务器类型兜底图标容器 → surface，详情页 `_divider` 改传 context 接 divider 令牌
- 残留白色均为有意的半透明叠加效果（Tab 胶囊填充、唱片高光、封面边框、头部渐变），六页 Colors.white 硬编码清零（拟物/叠加除外）

## 2026-09-08 — P1 主题整改：textPrimary 令牌 + 共享组件文本接入
- **SkinTokens 新增 `textPrimary`**：每套皮肤独立白阶主文本色（liquidGlass 纯白 / deepSpace 冷白 0xFFE8F4FF / materialYou M3 0xFFE6E1E5 / minimal 0xFFF5F5F5 / highContrast 纯白），copyWith/lerp 同步支持，AppTheme 暴露 `textPrimaryOf(context)`
- **共享组件文本令牌化**（跨页生效）：ListSearchBar（图标/占位→textFaint，输入文本→textPrimary）、SongRow 详情页歌曲行（标题→textPrimary、副标题硬编码 0xFFB0BAC6→textDim、菜单图标→textPrimary）、AlbumCard（专辑名→textPrimary、歌手→textDim）、异步态组件（加载/错误/空态/无匹配/加载更多文本→textDim，图标→textFaint），消除对 Colors.white 与写死灰色的依赖

## 2026-09-08 — 专辑歌曲数角标主题化
- **首页最新/随机专辑卡加歌曲数角标**：与资料库专辑网格同款（右上角胶囊，>99 显示 99+）
- **角标主题适配**：抽取共享 `SongCountBadge`，颜色由写死的设计图红改为 `colorScheme.primary/onPrimary`，五套皮肤自动跟随

## 2026-09-08 — P0 主题整改：弹层 tint 违规清零 + 死代码清理
- **弹层禁自定义 tint（glass-style 契约）**：action_sheets 歌曲操作弹窗/添加到歌单弹窗、full_screen_player 底部控制区、detail_screen 批量选择栏共 4 处删除 `tint: Colors.black.withValues(...)`，回退 GlassSurface 默认 `GlassTokens.tint(context)`（随皮肤走）
- **死代码清理**：AppTheme 删除零引用的 `primary/bar/searchbar/miniPlayer/queuePanel/queueActive` 令牌与 `dark` getter（primary 已全量迁移 colorScheme.primary）

## 2026-09-08 — 分页列表改为触底自动加载
- 新增共享 `ScrollBottomLoader`（NotificationListener，距底 600px 内触发）；专辑列表网格与 SongListScreen 艺人歌曲分页列表统一接入，`LoadMoreRow` 退化为状态展示（转圈/失败点击重试），不再是手动入口；触发回调沿用控制器 loading/noMore 防重入

## 2026-09-08 — 专辑列表滚动加载分页 + 搜索栏居中加固
- **专辑列表改为真 offset 分页（滚动加载）**：原 `LibrarySync.albums` 快照一次性取（曾写死 limit 100 导致只显示一部分）；新增 `LibraryAlbumsController`（每页 60，`fetchAlbums` 原生 start/limit 追加翻页）+ `libraryAlbumsPagedProvider`，AlbumListPage 数据源二选一（provider 全量 / paged 分页）；网格尾部复用 LoadMoreRow（加载中/失败重试/无更多）；快照保留供服务器详情页专辑总数使用，kind 升级 `albums_name_v2` 作废旧缓存
- **列表搜索栏垂直居中加固**：isCollapsed 固有行高方案受 CJK 字体度量影响文字整体偏高，改为 `expands: true + textAlignVertical.center` 撑满固定高度精确居中；提示/输入字号 15→16 对齐设计图

## 2026-09-08 — 播放页黑胶唱针方向修正
- **唱针起落画反**：_TonearmPainter 摆向为正 x 分量，「落针」（播放）时唱针被甩出画布外（视觉上停在右上角），「抬针」（暂停）时反而压在盘面上；镜像为负 x 分量并重调角度（-10° 抬起甩到盘缘外 / 26° 落针落在纹路上），唱头随臂杆角度同步摆正

## 2026-09-08 — 歌曲列表页三页合一（SongListScreen）
- **修复回归**：专辑入口合并时漏传数据源触发构造断言（专辑详情打不开），5 处调用点补上 `songsProvider: albumSongsProvider(album.id)`
- **AlbumDetailScreen + PlaylistDetailScreen 合并为 `SongListScreen`**：消除两份逐字重复的 `_playAll/_playShuffle/_enqueue` 与过滤状态；评分改为可选参数（rateTargetId + capabilities.ratings 门控），数据源四选一（songs / pagedSongsProvider / songsProvider / playlistId）
- **新增分页能力**：`pagedSongsProvider` 接 `artistSongsProvider`（ArtistSongsController 累计 limit 策略），列表尾部 LoadMoreRow「加载更多」
- **删除 ArtistDetailScreen**（~90% 与 Playlist 同构 / ~25% 复用度评估后收敛）：歌曲信息页、歌曲操作弹窗、搜索艺人行、资料库歌手列表全部改跳 SongListScreen(paged)，封面用 artistId；同时删除临时方案 `artistAllSongsProvider`（1000 上限一次性取全量）
- 歌曲列表页实现从 3 种收敛为 1 种；FEATURES.md §5.4/§5.5 同步改写

## 2026-09-07（深夜 II）— 列表页统一复用 + 拼音索引
- **歌手列表页**（资料库「歌手」/「专辑艺术家」）：顶部加常驻搜索栏（复用专辑列表 ListSearchBar，按名称或拼音过滤）；右侧 A-Z 索引条支持中文拼音首字母——中文名经 lpinyin 取无音调拼音排序归组（阿悄→A、周杰伦→Z），罕见字转换失败回退 '#' 组
- **歌手列表行点击**：改跳 PlaylistDetailScreen（与流派/歌曲/我喜欢的同一套结构），新增 artistAllSongsProvider 一次性取全量（上限 1000）；歌手详情页仍供歌曲信息页/操作弹窗/搜索入口使用
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
