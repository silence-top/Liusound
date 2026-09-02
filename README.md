# music-app

基于 [Navidrome](https://www.navidrome.org/) 自建音乐服务器的跨平台音乐客户端，一套代码同时运行在 **iOS / Android / Web** 三端，支持流媒体播放、逐行歌词同步、播放队列管理与多数据维度浏览。

> 相关文档：[代码优化报告](./OPTIMIZATION_REPORT.md)（2026-09 全量代码优化记录）

## 功能特性

- **多服务器登录**：选择音乐服务（Navidrome）→ 输入服务器地址 + 账号密码登录，会话持久化，冷启动自动恢复
- **首页多维浏览**：最新专辑 / 每日推荐 / 最近播放 / 最常播放 / 随机专辑，下拉刷新
- **播放内核双端适配**：原生端使用 `react-native-track-player-cjx`（后台播放、系统通知栏控制），Web 端使用 HTML5 Audio
- **逐行歌词同步**：解析 Navidrome JSON 歌词，二分查找定位当前行，支持点击歌词跳转、拖动进度预览歌词、逐歌持久化歌词偏移微调
- **播放队列**：添加/移除/清空歌曲、拖拽关闭弹窗、三种播放模式（顺序 / 随机 / 单曲循环），队列与播放进度持久化（冷启动恢复，不自动播放）
- **全局搜索**：300ms 防抖搜索，歌曲 / 专辑 / 艺人分区展示，点击歌曲即入队播放
- **迷你播放条**：旋转封面 + SVG 进度环 + 实时歌词副标题，点击进入全屏播放器
- **三端一致 UI**：深色主题、底部 Tab 导航（搜索 / 主页 / 设置）

## 技术栈

| 分类 | 选型 | 说明 |
| --- | --- | --- |
| 框架 | Expo 53 + React Native 0.79 | 已生成 `android/` 原生工程，newArch 关闭 |
| 语言 | TypeScript ~5.8（strict） | 全量类型覆盖 |
| 导航 | @react-navigation/native-stack | 认证分流 + 底部自绘 Tab |
| 播放 | react-native-track-player-cjx 4.1 | 原生音频；Web 端回退 HTML5 Audio |
| 网络 | axios + 拦截器 | 自动附加 JWT 与内存化凭证缓存 |
| 存储 | expo-secure-store + AsyncStorage | 敏感凭证加密存储（Keychain/Keystore），播放状态 / 歌词偏移走 AsyncStorage |
| UI | react-native-svg / vector-icons / slider / linear-gradient | 进度环、图标、音量条、歌词渐隐遮罩 |

## 快速开始

### 环境要求

- Node.js（建议 LTS 版本）+ npm
- Android：Android Studio / SDK（已含 `android/` 原生工程）
- iOS：Xcode（macOS）
- 一台可访问的 Navidrome 服务器

### 安装与运行

```bash
# 安装依赖
npm install

# 开发模式（Metro）
npm start

# 各端运行
npm run android     # 编译并安装到 Android 设备/模拟器
npm run ios         # 需要 macOS + Xcode
npm run web         # 浏览器调试（Metro Web）

# 类型检查与代码检查
npx tsc --noEmit
npm run lint
```

### 构建发布

- **Android**：通过 `android/` 目录使用 Gradle 构建，或使用 EAS Build（`eas.json` 已配置，projectId 见 `app.json`）
- **Web**：`npx expo export --platform web`

## 架构设计

### 分层结构

```text
UI 层        screens/ + components/      界面渲染与交互
状态层       contexts/                   AuthContext（会话）、PlayerContext（播放核心）
服务层       services/                   navidromeApi（REST）、config（存储键）
工具层       utils/subsonic.ts           Subsonic URL/参数构建共享工具
类型层       types/                      API DTO、导航参数、模块声明
```

### 核心数据流

```text
AuthProvider ──恢复会话──> isAuthenticated ? TabNavigator : ServerSelect→Login
     │
     └─ login()/logout() 时同步 navidromeApi 的内存凭证缓存（authCache）

PlayerProvider（唯一实例，挂载于 App 根部）
     ├─ 原生端：TrackPlayer.setupPlayer() + 播放状态/队列结束事件监听
     ├─ Web 端：HTMLAudioElement（挂载时创建）+ play/pause/ended 事件
     └─ 100ms 进度轮询（暂停时降频 500ms）→ currentTime/progress/歌词行
     └─ 播放状态 500ms 防抖持久化 → 冷启动恢复队列/播放模式/进度

组件 ──HTTP──> navidromeApi（axios 拦截器自动附加 Authorization，零 AsyncStorage IO）
     └─ 直链（封面/流媒体/歌词）──> utils/subsonic.ts 构建带认证参数的 URL
```

### 认证方案

登录成功后 Navidrome 返回三要素，敏感字段经统一存储层 `storageService` 加密持久化：

| 字段 | 用途 |
| --- | --- |
| `token` | REST API 的 `Authorization: Bearer` / `x-nd-authorization` 头 |
| `subsonicToken` + `subsonicSalt` | Subsonic 兼容接口（`/rest/*`）的 `t`/`s` 参数认证 |

**安全性**：token / subsonicToken / subsonicSalt 通过 `expo-secure-store` 加密存储（iOS Keychain / Android Keystore），首次读取时自动迁移历史明文数据，SecureStore 不可用时自动降级 AsyncStorage（见 `services/config.ts`）。

### 歌词同步方案

1. 优先使用歌曲数据内嵌的 `lyrics` 字段，否则请求 `/rest/getLyrics`；
2. 解析 JSON 歌词（多语言取第一轨），毫秒→秒、过滤空行、按时间排序；
3. `findLyricIndex` 二分查找当前行（前奏期返回 -1 正确显示空白）；
4. 下一句 = 当前索引 +1，天然规避重复文本歧义；
5. 文本无变化时跳过 setState；支持整体偏移（±0.05s 步进，按歌曲持久化）。

### 双端差异处理

| 能力 | 原生端 | Web 端 |
| --- | --- | --- |
| 播放引擎 | TrackPlayer（reset → add → play） | `new Audio()` + src 切换 |
| 进度获取 | `getPosition()/getDuration()`（bridge） | `audio.currentTime/duration` |
| 音量 | `TrackPlayer.setVolume` | 直接设置 `audio.volume`（支持鼠标拖拽） |
| 渐变遮罩 | `react-native-linear-gradient`（模块级条件 require） | CSS `backgroundImage: linear-gradient` |
| 后台播放 | `UIBackgroundModes: audio` + 前台服务权限 | 浏览器行为 |

## 目录结构

```text
src/
├── components/
│   ├── FullScreenPlayer.tsx   # 全屏播放器：推荐/歌曲/歌词三 Tab、音量条、歌词偏移面板
│   ├── MiniPlayer.tsx         # 迷你播放条：旋转封面、SVG 进度环、歌词副标题
│   ├── PlaylistDetail.tsx     # 歌单详情：滚动吸顶头、全部播放、列表内搜索
│   └── QueueModal.tsx         # 队列弹窗：拖拽关闭、播放模式切换
├── contexts/
│   ├── AuthContext.tsx        # useAuth：会话状态 + login/logout（同步 authCache）
│   └── PlayerContext.tsx      # usePlayer：队列/进度/歌词/播放模式
├── navigation/
│   └── TabNavigator.tsx       # 底部 Tab + MiniPlayerWrapper（模块级 memo 组件）
├── screens/
│   ├── HomeScreen.tsx         # 首页五个数据分区 + 每日推荐详情
│   ├── SearchScreen.tsx       # 搜索页：300ms 防抖 + 歌曲/专辑/艺人分区结果
│   ├── SettingsScreen.tsx     # 设置页（占位）
│   ├── LoginScreen.tsx        # 登录表单 + URL 规范化
│   └── ServerSelectScreen.tsx # 服务器选择（当前内置 Navidrome）
├── services/
│   ├── navidromeApi.ts        # axios 实例、authCache、auth/album/artist/song/playlist/search API
│   └── config.ts              # STORAGE_KEYS 统一存储键 + storageService（SecureStore/AsyncStorage 分流）+ serverUrl 读写
├── types/
│   ├── api.ts                 # Song/Album/Artist/Playlist 等 DTO
│   ├── navigation.ts          # RootStackParamList 导航类型
│   └── svg.d.ts / global.d.ts # 模块声明
└── utils/
    └── subsonic.ts            # buildCoverArtUrl / buildStreamUrl / buildSubsonicParams
```

## API 集成说明

### Navidrome REST（JWT 认证）

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| POST | `/auth/login` | 登录，返回 token / subsonicToken / subsonicSalt |
| GET | `/api/album`、`/api/song` | 列表查询（`_start/_end/_sort/_order` 分页排序，支持 `random`） |

### Subsonic 兼容接口（token+salt 认证，客户端标识 `NavidromeUI`，版本 `1.8.0`）

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/rest/stream?id=` | 音频流播放 |
| GET | `/rest/getCoverArt?id=` | 封面图（size=300） |
| GET | `/rest/getLyrics?id=` | 歌词（JSON 格式） |
| GET | `/rest/getSimilarSongs?id=&count=` | 相似歌曲推荐 |

## 已知限制与 Roadmap

已完成（2026-09）：

- ✅ **认证信息加密存储** —— 已迁移 `expo-secure-store`，含历史明文自动迁移与降级兜底
- ✅ **搜索功能** —— 已实现 300ms 防抖搜索（歌曲 / 专辑 / 艺人分区，点击即播）
- ✅ **播放队列持久化** —— 已实现队列 / 播放模式 / 进度持久化，冷启动恢复且不自动播放
- ✅ **随机专辑 seed 动态化** —— 每次刷新重新生成，内容真正随机
- ✅ **接入 ESLint 9** —— flat config + `eslint-config-expo` + `react-hooks` 规则集，当前 0 告警

待办：

1. **设置页仍为占位** —— 可补充服务器切换、缓存清理、歌词偏移全局默认等入口
2. **签名 / 打包配置为 debug keystore** —— 发布前需配置正式签名
3. **队列持久化上限 100 首** —— 超大队列可考虑调大上限或迁移 SQLite

## License

Private · 仅供学习与个人使用
