# Changelog — 流声 Liu Sound

产品版本号以 `pubspec.yaml` 的 `version` 为唯一事实来源。变更按主题分节，架构侧详情见 `FEATURES.md`（§13 Invariants / §14 Anti-Patterns / §15 P1 整改补充）。

## 2026-09-08 — 修复：播放页内容区与控制区之间的横线

- 真机反馈播放页控制区上沿有一条线：非液态玻璃皮肤的 `GlassSurface` 非玻璃面（`_buildNonGlassSurface`）一律画 `borderHairline` 描边（极简为 `divider`），播放页底部控制区是全贴边 radius 0 的面，描边上边缘就成了横线；改为全贴边面（radius 0）不画描边，有圆角的悬浮面照旧——歌曲详情页底部操作条同规则受益

## 2026-09-08 — 修复：图片背景只在顶部生效（三页嵌套 Scaffold 不透明底遮挡）

- 真机反馈背景图只有状态栏/顶部导航区域可见：壳三页（首页/资料库/设置）各自嵌套 `Scaffold` 默认继承不透明 `scaffoldBackgroundColor`，把壳层 `AmbientBackground`（背景图/皮肤舞台）整片盖住——顶部导航在壳层直接透明所以唯一透出；三页 Scaffold 改 `backgroundColor: Colors.transparent`，内容卡片表面不受影响

## 2026-09-08 — 定时停止/播放速度选择器改近实色取色底

- 用户反馈「也不要透明，毛玻璃近实色底」：歌曲操作弹窗进入的定时停止/播放速度选择器 tint 从半透明（alpha 0.55）换为近实色封面取色（`albumFrostedTint`：主色 lerp 黑 0.55 + alpha 0.90，与播放页毛玻璃面板同公式）；GlassSurface 自带毛玻璃模糊保留，透出的只是模糊色斑；设置页入口不传 tint 仍走主题玻璃

## 2026-09-08 — 图片背景升级为最高优先级 + 自定义背景设置优化

- 用户反馈「所有主题都有背景色导致图片背景看不到」：`AmbientBackground` 增加优先级——设置了自定义背景图后跳过全部 8 套皮肤的专属舞台装饰（液态玻璃光斑/深空星图/极简纸纹/M3 柔光球/落日/林间/终端 CRT/封面取色渐变），图片即背景，全皮肤生效；未设图时各皮肤舞台照旧
- **默认不透明度 0.35 → 0.85**（旧值在图片升级为背景后几乎不可见）；一次性迁移（`bg_opacity_migrated_v2`）把已设图且透明度 <0.6 的存量用户提到 0.85，显式调高过的保持原值
- **设置体验优化**：弹窗内新增 110px 实时预览框（同壳底色 + 当前透明度/模糊度渲染，弹窗挡住真实背景时在此看效果）；不透明度/模糊度滑块改为拖动中只更新内存态、松手（`onChangeEnd` → `commitSliders`）才落盘，避免每次回调写 SharedPreferences；「自定义背景」设置入口去掉 albumTint/终端皮肤门控（图片背景现全皮肤可用）

## 2026-09-08 — 歌曲取色弹层去透明：完全实色

- 用户反馈「歌曲取色了就不要透明了」：歌曲上下文弹层（歌曲更多 / 添加到歌单）的封面取色底从 blur28+alpha0.90 改为完全实色（`AlbumFrostedPanel` 新增 `opaque` 参数，实色时去模糊层——反正也不可见）；播放页队列/歌词浮层保持已验收的 0.90 毛玻璃不动

## 2026-09-08 — 冷启动恢复迷你播放条 + 二级弹层封面取色

- **启动显示迷你条**：根因是 `playerActionsProvider` 直到首次交互才被激活，冷启动恢复（`_restore`：上次队列/当前歌/模式/速度）从不执行——组合根 MusicApp 改为 `ref.watch(playerActionsProvider)` 让播放器内核随 App 存活；恢复的歌曲保持暂停不自动播（对齐 1.x），点击封面才续播并跳回上次进度
- **定时停止/播放速度弹窗**：与设置页确认完全共用（`showSleepTimerPicker`/`showSpeedPicker` 同一实现）；为两选择器加可选 `tint`——从歌曲操作弹窗进入时透传当前歌曲封面主色（`albumAdaptiveTint`），与外层弹窗色系连贯；设置页入口不传 tint 保持主题玻璃
- 歌曲列表「更多」主弹窗此前已接封面取色（AlbumFrostedPanel，7405d4a），无需改动

## 2026-09-08 — 迷你播放条改悬浮叠加：页面内容铺满到屏幕底

- 用户反馈「迷你条不在时底部没背景、出现迷你条后条下露出背景带」：根因是壳层 Column 独占布局，条让出的位置（16px 下边距 + 手势条安全区）露出壳背景，与页面自身背景形成断层
- **目标形态经用户确认**：页面内容铺满到屏幕底、迷你条悬浮其上（内容从条底下滑过）——与上次被否的「贴底收口」不同，条的位置/圆角/边距完全不变，只消除背景断层
- 实现：`AppShell` Column → Stack 叠加（内容 Column 铺满 + Positioned 悬浮 MiniPlayer，SafeArea 仍在壳层包裹，几何不变）；条占位（`kMiniBarOverlaySpace`=80）仅在播放时经 MediaQuery 注入，壳三页（首页/资料库/设置）最外层滚动底部避让相加，保证最后一项不被悬浮条遮住；`Scaffold.bottomNavigationBar` 三处推入页（歌曲列表/专辑列表/歌曲详情）不受影响（布局机制未动）

## 2026-09-08 — 回退：迷你播放条贴底收口（真机验收不通过）

- 5175706 的贴底改动真机试用后由用户要求回退（3f549c6）：SafeArea 包裹 / 16px 下边距 / 三样式胶囊圆角 / 偏移 -20~40 全部恢复原状；后续若再调此区域，先与用户对齐目标形态

## 2026-09-08 — 设置文案：「控制栏」改「迷你播放条」

- 用户反馈「控制栏样式 / 控制栏高度偏移」易误读为状态栏/导航栏调节，实际两者均调节底部迷你播放条（MiniPlayer）；设置页两入口标题与对应选择弹窗标题统一改名，实现注释同步

## 2026-09-08 — 修复：连点切歌误报「播放失败，请检查服务器连接」

- **根因一（toast 泄漏）**：`play()` catch 分支的无损直连失败提示缺少代数守卫（同函数另两处提示都有 `gen == _playGeneration` 检查）——连点时旧加载流程被新一轮播放接管而报错，旧代数本该静默作废却照样弹 toast
- **根因二（音源覆写竞态）**：`_setStreamSource`（向播放器写音源）发生在代数检查之前——旧请求晚完成时会把旧歌音源覆写到播放器上，打断新歌加载；无损回退重试也会为旧代数再跑一次与新请求竞争
- **修复**：`resolveStream` 返回后、写音源前先验代数；catch 入口旧代数直接静默返回（不再发起回退）；本地播放 `_playLocal` 写音源前同样补验

## 2026-09-08 — 主题：删高对比无障碍，换封面取色皮肤（albumTint）

- **AppSkin.highContrast 移除，新增 `albumTint('封面取色')`**：全局跟随当前播放歌曲封面主色取色，与播放页同源——组合根 main.dart `select` 只监听 currentSong 的 albumId，复用播放页同一个 `albumDominantColorProvider`（64px 缩样 vibrant/muted/dominant）；旧皮肤存档 `highContrast` 自动回退默认液态玻璃
- **SkinTokens 动态色板**：`albumTint(dominant)` 工厂按播放页同源公式推导（背景 = 主色 lerp 黑 0.42，弹层面 = lerp 0.55）；封面过亮（luminance>0.5）先压暗 0.45 保证白字对比；`albumTintFallback` 中性深灰兜底取色中/失败（本地歌曲/无封面），`forSkin` 加 `albumDominant` 可选参数
- **舞台与背景**：AmbientBackground 新增封面取色舞台（顶部提亮渐变复刻播放页上浅下深）；该皮肤不叠加用户自定义背景图（封面色为唯一背景源，与终端一致），设置页自定义背景入口同步隐藏
- 表面语言：GlassSurface 非玻璃面 highContrast case → albumTint（surface 底 + hairline 描边）；FEATURES.md §4.14 同步（此前停在 5 皮肤时代的枚举/数值表/舞台表一并更新到 8 皮肤现状）

## 2026-09-08 — 全库审计 P2-F：大文件 part 化拆分

- **full_screen_player.dart 2451 → 366 行主骨架**：按 Tab/区域拆四个 part——recommend（相似/热门/简介，250 行）、now_playing（黑胶/CD/方图/唱臂/虚化背景，536 行）、lyrics（歌词 Tab + 行瓷贴，1026 行）、bottom（歌曲信息/进度/控制行，286 行）；纯物理拆分（part 同库，私有成员可见性不变），视觉零改动
- **settings_screen.dart 2093 → 648 行主屏+共享瓷贴**：13 个 `_show*Sheet` 按域拆四个 part——storage（缓存/音质/转码/网络）、appearance（玻璃/封面/皮肤预览）、audio（音效/耳机）、player（主题色/背景/迷你条/结束文案）
- **music_library_screen（1034）/detail_screen（1063）评估后暂缓**：仅约前两者一半体量，且 detail 内 SongRow 是四页共用组件（外部 import detail_screen），拆动收益低、影响面反而大；留待 P3 再议
- 拆分遵循 FEATURES.md §15.1 的 player_controller part 先例；导入路径不变，外部调用点零修改

## 2026-09-08 — 全库审计 P2-E：解析测试补充 + Json.intOfOrNull 缺陷修复

- **新增 test/p2_parsing_test.dart（11 例）**：parseLrcText（多时间戳行/厘秒毫秒口径/元数据标签/空输入）、Json 工具（intOfOrNull/firstStr 语义）、Song.fromJson 各后端键形态（Subsonic 原生与 transcoded 回退、MediaBrowser contentType/albumArtistName/filePath、采样率 kHz↔Hz 归一、trackNumber 双键）
- **修复 `Json.intOfOrNull`**：原实现 `(j[key] as num?)` 对字符串值抛 TypeError 而非返回 null，与「仅接受 num」语义不符；改 `is num` 判定
- 范围评估：adapter 私有映射（_toSong 等）需网络层假件才能驱动，已由 parseSong 钩子+fromJson 键形态测试覆盖主路径；library_sync 公共面太薄（ songs/albums 两入口需整 Provider+adapter 假件），本批不做
- 测试 25 → 36

## 2026-09-08 — 全库审计 P2-D：颜色 token 清扫（常规页面）

- **五文件白阶归零**：home_screen（分区标题/专辑卡/最近歌曲行的 `Colors.white*` 与 `0xFF666666`/`0xFFB0B0B0`）、song_info（全页 8 处，`_row` 补传 context）、search_screen（输入框/分区标题/艺人专辑行/错误文案）、app_shell（底栏未激活图标）、library_entries（歌手行/字母索引条/电台列表）——统一映射 white→textPrimaryOf、white54/60→textDimOf、white38/45→textFaintOf
- **保留的白**：流派瓷贴文字压在彩色块上（色块前景语义）；播放页四文件与 glass.dart/theme 层按既定豁免不动
- **fontSize 令牌未动**：目前无字号令牌体系（仅 TextTheme 静态样式），新增令牌属设计决策，需单独定方案后另行批次；审计所列 219 处维持现状

## 2026-09-08 — 全库审计 P2-C：主 isolate 同步 IO 治理

- **AudioCache LRU 清理去同步 stat**（cache_manager.dart）：sizeBytes/enforceLimit 的 `lengthSync` 改 `await length()`；enforceLimit 排序所需的 mtime 在遍历时异步收集为 `(file, size, mtime)` 三元组，不再排序前逐个 `lastModifiedSync`
- **findDownloadedSong 目录兜底扫描改异步流**：`listSync` 改 `await for (dir.list())`，回填索引的 `lengthSync` 同步消除
- **downloadSongFile 提交链路异步化**：目录创建/校验/删除/rename 全部走 async API，大文件 `renameSync` 不再阻塞主 isolate
- 范围外确认：local_library 的同步扫描已在 `Isolate.run` 内（此前批次完成），单次 `existsSync`（封面/播放源回退）开销可忽略不动

## 2026-09-08 — 全库审计 P2-B：重复 UI 收拢

- **错误重试块统一 `errorRetryBox`**（async_states.dart）：私有 `_error` 改为公共组件的薄封装；手写「加载失败，点击重试」五处替换——home_screen（删除 `_ErrorRetry` 类，专辑行/分区两调用点）、detail_screen 分页失败块、music_library 歌单区与分页专辑格、library_entries 歌手/流派入口；library_entries 385/478 的「失败或不支持」组合态保留不动
- **搜索入口条抽共享 `SearchEntryBar`**（shared/widgets/search_entry.dart）：home_screen 与 music_library 两份 `_SearchBar` 合一，onTap 由调用方传入（shared 不反向依赖 features/search）；home_screen 版原硬编码 Colors.white* 系一并令牌化
- 歌曲行收拢评估：SongRow 已被 detail/home/search/full_screen_player 四页共用，队列行因拖拽重排语义不同，无需再动

## 2026-09-08 — 全库审计 P2-A：死代码清理

- **`NavidromeClient.clearSession` 删除**：登出走 removeServer 重建 adapter，全库零调用
- **`parseLyrics`（lyrics.dart 单轨便捷封装）删除**：播放页用 `_parseLyrics` 自有封装，顶层函数零引用；`parseLyricsData`/`alignTranslations` 在用保留
- 审计另列的 `glassAsyncBody`/`SubsonicAuth.empty` 经 grep 确认已不存在

## 2026-09-08 — 全库审计 P1-D：JSON 工具收拢到 models.dart

- **`_Json` 提升为公开 `Json`**（models.dart）：str/strOf/intOf/doubleOf/boolOf/strOrNull/doubleOrNull/intOrNull 全量收拢；新增 `intOfOrNull`（单键仅 num）与 `firstStr`（候选键 trim 取首个非空）
- **五个适配器的本地 JSON 静态方法改为委托 Json**：subsonic/subsonic_protocol/mediabrowser/plex/audio_station 的 `_s/_i/_iOrNull/_n/_firstStr/_firstNum/_doubleOrNull` 等副本统一单源，调用点短名不变
- **`_toSong/_toAlbum` 与 `fromJson` 合并评估后不做**：Subsonic 的 starred 是时间戳字符串（Navidrome 是 bool）、suffix/codec 有 transcoded 回退键、另有 replayGain/kHz 采样率归一——语义真实分歧，P1-A 的 `parseSong` 钩子已隔离差异，强行合并风险大于省下约 30 行

## 2026-09-08 — 全库审计 P1-C：重登拦截器合并 + 能力位清理 + 错误日志

- **401 静默重登拦截器抽公共 `ReauthInterceptor`**（reauth_interceptor.dart）：MediaBrowser 系（header 重写）与 Plex（query token 重写）共用同一 QueuedInterceptor 实现，差异收敛为两个闭包；两份私有拦截器类删除
- **Jellyfin/Emby 认证请求上提基类**：`MediaBrowserAdapter.authenticateByName(client:, md5Password:)` 统一 `/Users/AuthenticateByName` 登录+静默重登请求，两个子类各自的 `_authenticate` 副本删除
- **AdapterCapabilities 死字段清理**：`likedSongs`/`lyrics` 全库零读取，删除（连带消除「Plex 声明 lyrics:true 但 fetchLyrics 恒 null」的自相矛盾）；`similarSongs` 复核后确认播放页「相似歌曲」在用，保留
- **navidrome_client 5 处裸 `catch (_)` 补日志**：相似歌曲/歌手简介/歌曲总数/Subsonic 动作/加歌单失败不再静默，统一走 `adapterSwallowLog`

## 2026-09-08 — 全库审计 P1-B：serverAdapterProvider 下沉 core，解除反向依赖

- **新增 `core/api/adapter_provider.dart`**：`serverAdapterProvider`/`transcodeSupportProvider`/`activeServerIdProvider` 从 features/auth 下沉 core；core 通过 `activeServerSessionProvider`（组合根 main.dart 用 authControllerProvider 覆写注入）拿到会话快照，方向恢复为 features→core 单向
- **解除 4 处 core/shared→features 反向依赖**：`library_sync`/`scrobble_service`/`auto_download`/`shared/cover_art` 改引 core provider，activeServerId 一律走 `activeServerIdProvider`（未登录为空串语义）
- features 内约 15 处既有 import 不动：auth_controller 对新位置 re-export

## 2026-09-08 — 全库审计 P1-A：Subsonic 协议层抽共享基类

- **新增 `SubsonicProtocolAdapter`**（subsonic_protocol.dart）：`SubsonicAdapter`（纯 Subsonic）与 `NavidromeAdapter` 共用的媒体直链（stream/download/封面）、资料库扩展（歌手索引/流派/电台/流派歌曲/歌词）、版本号与转码探测（含 TranscodeProbeCache 持久化）全部上提；子类只需提供 `dio/auth/api/parseSong` 四个钩子
- **删除两份重复实现约 230 行**：两适配器各自的 resolveStream/resolveDownload/coverImage/fetchCoverBytes/supportsTranscode/资料库六扩展方法/fetchLyrics/libraryVersion 移除
- **Navidrome 顺带收益**：原先 `_subsonicGet` 静默吞错，共享层统一 try/catch + `adapterSwallowLog`，Navidrome 的 Subsonic 兼容层请求失败现在有日志可查
- **歌曲映射保留差异**：`parseSong` 钩子让 Subsonic 继续用扩展映射（采样率/replayGain），Navidrome 用 `Song.fromJson`，行为零变化

## 2026-09-08 — 全库审计 P0 修复（五项）

- **Subsonic 歌曲总数算错**：`fetchSongCount` 取 `list.length`（恒 ≤1）→ 改读 `albumList2.totalMatches`，负一屏服务器卡片对 Subsonic 系后端恢复正确总数
- **下载/封面绕过网络设置**：`downloadSongFile` 新增 `networkSettings` 参数并走 `NetworkRuntime.configureDio`（代理/自签证书/hosts 对下载生效），两个调用方（手动下载/自动下载）传入当前设置；Navidrome `fetchCoverBytes` 从裸 `Dio()` 改用 client dio
- **Dio 泄漏**：Navidrome `dispose()` 由空实现改为关闭 client dio；`signIn` 登录后关闭临时 client；`downloadSongFile` 下载完成即关闭 dio
- **Provider 缓存泄漏**：`albumSongsProvider/playlistSongsProvider/playlistCoverIdsProvider` 三个 family 改 autoDispose，长浏览会话不再按 id 无限累积
- **下载扩展名**：文件名按 `song.suffix` 真实容器命名（flac/m4a 等），无 suffix 回退 mp3；同时修掉 Subsonic/Navidrome `fetchCoverBytes` 忽略 size 参数的问题

## 2026-09-08 — 播放页弹层试毛玻璃（底色近实色不透底）

- **album_tint 新增 `AlbumFrostedPanel`**：BackdropFilter blur 28 垫底 + alpha 0.90 的封面取色底——毛玻璃质感但背后内容不可辨（只透模糊色斑），白字可读性不受影响；取色失败回退主题表面色
- **替换范围**（上一轮实色 Container 全部升级为毛玻璃面板）：队列弹窗、歌曲操作弹层、添加到歌单弹层、播放页歌手简介卡、LRC 菜单、音轨选择器、歌词偏移面板、音量条
- **迷你条「玻璃」样式恢复毛玻璃**：同款 blur 28 + alpha 0.90 取色底，与 solid/gradient 档重新拉开层次
- 内部浮起卡片（白 0.07）与圆角按钮（白 0.10）维持上一轮方案不动

## 2026-09-08 — 播放页去玻璃改不透明封面取色 + Token 过期静默重登

### 播放页周边去玻璃（用户钦定：不要玻璃不要透明）
- **album_tint 新增 `albumSolidTint`**：封面主色 lerp 黑 0.55 的不透明实色，替代玻璃/模糊材质；取色失败回退 AppTheme.surfaceOf
- **全面替换范围**：播放列表弹窗、歌曲/播放列表操作弹层、歌手简介卡、LRC 菜单、曲目选择器、歌词调整面板、音量面板、迷你播放条——GlassSurface/GlassCard 全部改普通 Container 实色底，内部浮起卡片统一白 0.07 叠加
- **刻意保留**：播放页底部控制区（页面背景属性）与黑胶封面框（视觉冻结 611b9fa）
- 迷你条三种样式（玻璃/实色/渐变）全部改为封面主色派生的不透明底，与播放页弹层同色系

### Token 过期静默重新登录（Jellyfin/Emby/Plex/群晖）
- **`SecretsUpdatable` mixin**（server_adapter.dart）：适配器声明静默重登能力，新凭证经 `onSecretsUpdated` 回调上报
- **QueuedInterceptor 401 拦截**：MediaBrowser 系（Jellyfin/Emby）与 Plex 在 401 时用本地保存的账号密码重新认证并重放原请求一次（extra 标记防循环）；AudioStation 原有 _relogin 补挂回调
- **密码入 secrets**：登录时统一把 password 并入 secrets 持久化（此前仅群晖存），旧会话需重新登录一次才具备静默重登能力
- **静默持久化**：AuthController.updateStoredSecrets 只写存储不改内存 state——避免 provider 重建 dispose 掉正在重放请求的 adapter；下次重建时读新凭证

## 2026-09-08 — 播放页周边功能块改封面取色（QA 反馈）
- **GlassCard 新增可选 `tint` 透传**：默认 null 仍回落 GlassTokens.tint(context)，全库业务零影响——此前卡片把 tint 写死成主题 token，造成"弹层本体随封面、内部功能块随主题"的割裂
- **更多弹层两张功能卡**（操作卡片一/二）与**播放页歌手简介卡**传入 `adaptiveTint`，与宿主弹层/播放页背景同色系
- **更多弹层圆形按钮底色**：AppTheme.surfaceOf（随主题变脸）→ 中性半透明白 0.10，叠在封面取色卡片上的浮起层不再随主题
- 播放列表弹窗代码上本就是 blurHeavy+adaptiveTint（设备设置确认 liquidGlass+标准档+非省电），"透明感"待真机截图定位

## 2026-09-08 — Liquid Glass V2：玻璃材质做减法（评审驱动）
- **砍三特效**（均为 liquidGlass 专属分支，其余 7 套皮肤不受影响）：删除 _MicroNoisePainter 微噪纹理（alpha 0.035 每卡叠加显脏）、_ChromaticEdgePainter 色差边缘（顶部蓝晕是 Dribbble/AI 玻璃标志性特效，上亮下弱由渐变描边承担）、饱和度增强 ColorFiltered 1.25/1.35/1.30（艳度最大来源，且每面强制 saveLayer，砍掉是性能净赚）
- **镜面高光收窄**：顶部斜向高光渐变 stops 0.45 → 0.25，只覆盖顶部约 25% 后消失，对齐 iOS 材质克制反光
- **环境光球减淡**：3 团（0.20/0.18/0.15）减为 2 团（0.10/0.075），保留玻璃模糊的"可折物"避免无自定义背景图页面玻璃隐形，去掉 Aurora 感
- **播放页随全局统一**（用户确认）：黑胶主体/歌词区/tint 取色不动——取色在 album_tint 层，与玻璃材质层无关
- 组件不拆分：GlassSurface/GlassCard/GlassPill API 保持，业务页面零改动

## 2026-09-08 — 主题阶段2：新增 3 套皮肤 + 全皮肤专属环境舞台
- **区别度诊断**：原 5 套里 liquidGlass/deepSpace 因有专属舞台（折射光斑 / 星图扫描线）一眼可辨，而 minimal/materialYou/highContrast 仅靠扁平底色 + 圆角档位区分、无任何装饰层，字体密度也一致——这是"看着像"的根因，而非皮肤数量少
- **保留高对比**：它是唯一功能性（无障碍）皮肤（纯黑 / 直角 / 去模糊去发光 / 对比度 ≥7:1），视觉朴素正是设计目的，删除即砍掉无障碍能力
- **新增 3 套皮肤**（AppSkin/SurfaceLanguage/SkinTokens 同步扩到 8 值）：落日熔金 sunset（暖橙玫瑰 + 低垂夕阳光球，radiusScale 1.1）、林间苔原 forest（暖绿纸质 + 冠层微光颗粒，radiusScale 0.6）、终端磷光 terminal（纯黑绿字 + CRT 扫描线，radiusScale 0 直角 + 绿色 glow）
- **全皮肤专属环境舞台**（AmbientBackground）：给原本扁平的 minimal 加纸纹颗粒、materialYou 加 M3 柔光球（跟随动态主色）；新皮肤各自 _Sunset/_Forest/_Crt 舞台 painter。新增 _GrainStagePainter（seeded Random 确定性颗粒，静态不闪烁）；终端与高对比一同跳过用户背景图绘制
- **GlassSurface** _buildNonGlassSurface switch 补 sunset/forest/terminal 分支（sunset/terminal shadow 带各自 glow 柔光投影，forest 纯纸质无投影）
- **textPrimary 取 token**：ThemeData textTheme 主文本色改用 t.textPrimary（原恒为纯白），终端磷光绿得以贯穿未显式指定样式的 Text；liquidGlass 的 t.textPrimary 本就纯白，播放页视觉不变
- **设置页门控**：自定义背景入口排除 terminal（纯黑审美下背景图无效）
- 已知限制：Terminal 的"真等宽字体轴"需内置字体资源（pubspec 当前无 fonts），本次以磷光绿配色 + CRT 扫描线 + 直角达成终端观感，等宽字体留作可选后续

## 2026-09-08 — 认证两页主题联动 + 输入框可见性（QA 反馈修复）
- **login_screen / server_select_screen 令牌化**：两页全部硬编码白（标题/标签/副标题/图标容器/Chevron）接入 textPrimary/Dim/Faint + SkinTokens.surface——当初令牌化清扫只覆盖登录后页面，这组认证页漏了
- **输入框可见性**：InputDecorationTheme 常态加 borderHairline 微亮描边 + focusedBorder（primary×0.5）+ hintStyle textFaint——原先无描边且 fillColor=surface，在极简暖皮下与卡片 tint 同色直接隐形；边框圆角 8×radiusScale 随皮肤
- 备注：输入框描边是全局主题变更，其余页面 TextField 同步受益

## 2026-09-08 — 主题阶段1：皮肤圆角档位 + 色温差异化
- **SkinTokens 新增 `radiusScale`**：玻璃面/弹层/导航基准圆角 × 皮肤缩放（GlassSurface 统一收口，胶囊 999 不缩放；copyWith/lerp 同步支持）。liquidGlass 恒 1.0（播放页冻结不变）、deepSpace 0.7（赛博几何）、minimal 0.55（纸感小圆角）、materialYou 1.3（M3 大圆角）、highContrast 0.0（无障碍直角，替代原先写死的 8px）
- **色温差异化**（不动 liquidGlass/highContrast）：minimal 冷灰改暖炭纸感（背景/面板/文本阶全部带微暖色温）；materialYou 改 M3 暗色紫调 tonal surface；deepSpace 蓝黑加深——五套皮肤色温+圆角两维同时拉开，肉眼可辨
- 非玻璃面（_buildNonGlassSurface）同样走 radiusScale，删除 minimal/highContrast 写死 8px 的特例分支

## 2026-09-08 — 外部评审落地（首批小修）
- **auto_download 换服中止**：下载循环每轮重读 activeServerId，切换服务器后旧流程立即中止，杜绝把旧服务器歌曲下到新服务器归属
- **LRC 导入覆盖确认**：导入前查 AppDb 已有歌词，存在时 glassDialog 确认「覆盖/取消」，不再静默覆盖
- **prefs 注入错误信息**：UnimplementedError → StateError，明确指出「未在 main() override」与修法
- **适配器静默异常 debug 日志**：新增 core/api/adapter_log.dart `adapterSwallowLog`（kDebugMode 零开销），5 个适配器共 50 处 `catch (_)` 补日志，不再无声吞掉网络/解析异常；评审中的 Isolate.run→compute 建议经核实不成立（compute 内部即 Isolate.run，无长驻池），维持现状

## 2026-09-08 — 播放时按需拉取歌词（快照/队列恢复丢歌词兜底）
- **根因**：`Song.toJson()` 沿袭 stripSong 剔除内嵌歌词，曲库快照（LibrarySync SQLite）与队列持久化（SharedPreferences）的 JSON 往返都会丢 `lyrics`——资料库歌曲列表点播后播放页无歌词
- **修法（用户钦定：每次播放重新拉）**：`ServerAdapter` 新增 `fetchLyrics(songId)` 默认 null（不支持即静默降级）；Navidrome/Subsonic 走 OpenSubsonic `getLyricsBySongId`，Jellyfin/Emby 走 `/Audio/{id}/lyrics`（ticks→ms 转 Navidrome 结构化格式，Emby 老版本无此接口回 null），Plex/Audio Station 暂不实现
- **回填时机**：`play()` 设置当前歌后异步补拉（复用播放代数守卫防连点竞态），已有歌词（含本地导入）不重复请求；拉到后 `copyWith(lyrics:)` 更新当前歌状态
- **歌词页联动**：_LyricsTab didUpdateWidget 同曲歌词变化时原地重新解析；本地导入歌词（SQLite）优先级更高，生效时不被服务端回填覆盖
- 已知边界：冷启动恢复的历史队列恢复后首播即触发补拉，逐曲渐进恢复；快照本身仍不含歌词（体积考量，不变更）

## 2026-09-08 — 播放页相关弹层全部随封面主色
- **取色下沉共享**：`albumDominantColorProvider` 从 full_screen_player 迁出到新文件 `album_tint.dart`，新增 `albumAdaptiveTint()` 统一公式（主色 lerp 黑 0.42 × alpha 0.55，与页面背景渐变顶端一致）
- **接入弹层**：歌曲操作弹窗（随目标歌曲封面）、添加到歌单（批量取第一首）、播放队列面板（随当前歌曲）、歌词页 4 个浮层（LRC 菜单/音轨选择/歌词偏移/音量条，随当前歌曲）——与底部控制栏同一色系；取色中/失败回退 GlassTokens.tint
- 队列当前行高亮胶囊（primary 0.14）与歌词跳播 chip 保持原样，仅面板级 tint 跟随封面

## 2026-09-08 — 播放页底部控制栏随封面主色
- **底部控制区 tint 跟随歌曲封面**：_BottomArea 的 GlassSurface 由固定皮肤 glassTint 改为封面主色（与页面背景渐变同一取色 albumDominantColorProvider，lerp 黑 0.42 × alpha 0.55 半透明叠在模糊背景上）——歌词区背景随歌曲变色，底部栏原先固定近黑两截断开，现在整页上下同色系连贯；封面取色中/失败回退默认玻璃 tint。属审计「内容驱动取色」合理保留类的用户钦定例外

## 2026-09-08 — 播放页整体回退至 P2 前（用户 QA 后要求还原）
- **full_screen_player.dart 整文件回退到 44ec5d3 版本**：撤销 P2 文本/组件令牌化与 P3 _VinylPalette 收拢在该页的全部改动，视觉效果恢复到用户熟悉的样子；唱针方向修复（e2cf3eb）与 P0 弹层 tint 修复保留
- 设备 QA 结论：用户认为该页 P2 前的视觉即最终形态；其余五页（settings/detail/music_library/servers/server_detail）令牌化维持不变

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
