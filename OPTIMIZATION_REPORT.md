# music-app 代码优化报告

> 生成日期：2026-09-02
> 范围：全量源码解析与优化（`src/` 目录 + 配置文件）
> 验证：`npx tsc --noEmit` 通过，零类型错误

---

## 一、项目概述

基于 Navidrome 自建音乐服务器的跨平台音乐客户端，一套代码同时运行在 iOS / Android / Web 三端。

### 1.1 技术栈

| 分类 | 选型 | 版本 |
| --- | --- | --- |
| 框架 | Expo | 53.0.11 |
| 运行时 | React Native / React | 0.79.3 / 19.0.0 |
| 语言 | TypeScript | ~5.8.3（strict 模式） |
| 导航 | @react-navigation（native-stack） | ^7.x |
| 音频播放 | react-native-track-player-cjx（原生） / HTML Audio（Web） | 4.1.1 |
| 网络 | axios | ^1.9.0 |
| 本地存储 | @react-native-async-storage/async-storage | ^2.2.0 |
| UI 增强 | react-native-vector-icons、react-native-svg、@react-native-community/slider、react-native-linear-gradient | - |

### 1.2 目录结构与职责

```text
src/
├── components/
│   ├── FullScreenPlayer.tsx   # 全屏播放器（推荐/歌曲/歌词 三 Tab，音量/歌词偏移）
│   ├── MiniPlayer.tsx         # 底部迷你播放条（旋转封面 + 进度环 + 歌词副标题）
│   ├── PlaylistDetail.tsx     # 歌单详情（吸顶动画头 + 歌曲列表）
│   └── QueueModal.tsx         # 播放队列弹窗（拖拽关闭 + 播放模式切换）
├── contexts/
│   ├── AuthContext.tsx        # 认证状态（token/subsonicToken/salt/serverUrl 持久化）
│   └── PlayerContext.tsx      # 播放核心（队列/进度/歌词/播放模式，双端播放器适配）
├── navigation/
│   └── TabNavigator.tsx       # 底部 Tab（搜索/主页/设置）+ MiniPlayer 挂载
├── screens/
│   ├── HomeScreen.tsx         # 主页（最新专辑/每日推荐/最近播放/最常播放/随机专辑）
│   ├── SearchScreen.tsx       # 搜索页（占位）
│   ├── SettingsScreen.tsx     # 设置页（占位）
│   ├── LoginScreen.tsx        # 登录页（服务器地址 + 账号密码）
│   └── ServerSelectScreen.tsx # 服务器选择页
├── services/
│   ├── navidromeApi.ts        # REST API 封装（axios 拦截器 + Subsonic 接口）
│   └── config.ts              # 存储键与服务地址读写
├── types/                     # API 类型定义、导航参数类型
└── utils/
    └── subsonic.ts            # ★ 本次新增：Subsonic URL 构建共享工具
```

### 1.3 核心数据流

```text
AuthProvider（AsyncStorage 恢复会话）
    └─> PlayerProvider（TrackPlayer / HTML Audio 双端播放）
          └─> TabNavigator
                ├─ HomeScreen ──> navidromeApi（axios 拦截器自动附加凭证）
                └─ MiniPlayer ──> FullScreenPlayer / QueueModal / PlaylistDetail

Subsonic 直链（封面/流媒体）= serverUrl + /rest/* + 认证参数(u/t/s/f/v/c)
```

---

## 二、优化总览

| # | 类别 | 问题 | 涉及文件 | 状态 |
| --- | --- | --- | --- | --- |
| 1 | 架构 Bug | 双重 PlayerProvider 导致播放器双重初始化 | TabNavigator.tsx | ✅ 已修复 |
| 2 | 架构 Bug | 组件内定义 MiniPlayerWrapper 导致子树反复重挂载 | TabNavigator.tsx | ✅ 已修复 |
| 3 | 反模式 | render 期间调用 onClose() | FullScreenPlayer.tsx | ✅ 已修复 |
| 4 | 功能缺失 | 歌词偏移只保存不加载 | FullScreenPlayer.tsx | ✅ 已补全 |
| 5 | 性能 | 每次请求读 2 次 AsyncStorage | navidromeApi.ts | ✅ 内存缓存 |
| 6 | 性能 | 监听器每次渲染重注册 / stale closure | PlayerContext.tsx | ✅ useCallback 化 |
| 7 | 性能 | 歌词线性查找 + 无效 setState | PlayerContext.tsx | ✅ 二分查找 + 跳变检测 |
| 8 | 性能 | 暂停时仍以 100ms 高频轮询 | PlayerContext.tsx | ✅ 动态降频 500ms |
| 9 | 重复代码 | 封面/流 URL 拼接逻辑 4 处重复 | utils/subsonic.ts（新增） | ✅ 统一收敛 |
| 10 | 重复代码 | STORAGE_KEYS 双处定义 | config.ts + AuthContext | ✅ 统一收敛 |
| 11 | 重复读取 | HomeScreen 重复读 serverUrl | HomeScreen.tsx | ✅ 改用 Context |
| 12 | 死代码 | 未使用的导入/状态/动画值/样式 | 多个文件 | ✅ 已清理 |
| 13 | 隐藏 Bug | TrackPlayer 通知栏封面误用音频流地址 | PlayerContext.tsx | ✅ 改用封面端点 |
| 14 | 配置错误 | tsconfig 覆盖导致 tsc 完全无法运行 | tsconfig.json | ✅ 已修复 |

---

## 三、优化详情

### 3.1 双重 PlayerProvider（严重）

**问题**：`App.tsx` 中 `<AuthProvider><PlayerProvider>…` 已在最外层提供播放上下文，而 `TabNavigator` 内部又包了一层 `<PlayerProvider>`。两个 Provider 实例各自持有独立的 `isInitialized` ref 与状态：

- `TrackPlayer.setupPlayer()` 被调用两次（第二次异常被 catch 掩盖）；
- 播放队列、进度、歌词存在两份，内外层 UI 可能各自为政；
- 进度定时器、事件监听器翻倍，白白消耗 CPU 与电量。

**修复**：移除 TabNavigator 内层 Provider，统一使用 App.tsx 外层实例。

```tsx
// TabNavigator.tsx（修复后）
return (
  // PlayerProvider 已由 App.tsx 提供，此处不再重复嵌套
  <View style={styles.container}>
    …
    <MiniPlayerWrapper />
  </View>
);
```

### 3.2 内嵌组件定义（严重）

**问题**：`MiniPlayerWrapper` 定义在 `TabNavigator` 函数体内。每次 TabNavigator 渲染都会生成**新的组件类型**，React 按「类型不同 = 卸载重挂载」处理，导致 MiniPlayer 整个子树反复销毁重建：内部 `isPlayerVisible` 等状态丢失、封面图片重新加载、动画重置。

**修复**：提取到模块级，并用 `memo` 包裹。

### 3.3 render 期间调用 onClose（反模式）

**问题**：FullScreenPlayer 中：

```tsx
if (!currentSong) {
  onClose();   // ❌ 渲染阶段触发父组件 setState
  return null;
}
```

当前歌曲被从队列移除时，会在 FullScreenPlayer 渲染过程中直接调用父组件的 `setIsPlayerVisible(false)`，属于 "setState during render" 反模式，可能引发 React 告警或更新循环。

**修复**：移入 useEffect，渲染函数只负责返回 `null`。

```tsx
useEffect(() => {
  if (visible && !currentSong) onClose();
}, [visible, currentSong, onClose]);

if (!currentSong) return null;
```

### 3.4 歌词偏移持久化补全（功能缺失）

**问题**：FullScreenPlayer 有 `handleSaveLyricOffset`（保存 `lyricOffset_{songId}` 到 AsyncStorage），但**没有任何加载逻辑**——重新打开播放器后偏移静默丢失，与用户预期不符。

**修复**：新增切歌时加载 effect（含 cancelled 标志防竞态），并提取 `LYRIC_OFFSET_PREFIX` 常量与保存逻辑共用。

### 3.5 navidromeApi 请求零 IO 化（性能）

**问题**：请求拦截器内每次请求都 `await AsyncStorage.getItem(SERVER_URL)` + `getItem(TOKEN)`。列表页一次并发 5 个请求就是 10 次异步 IO；且 album/artist/song 的 URL 构建方法同样每次读存储。

**修复**：引入模块级 `authCache`（内存对象），启动时恢复一次，之后拦截器同步读取；对外暴露：

```ts
export const setAuthCache = (serverUrl: string, token: string) => { … };  // login 时同步
export const clearAuthCache = () => { … };                                // logout 时同步
```

`AuthContext.login/logout` 已接入同步调用，保证登录/登出后拦截器立即可用新凭证。URL 构建方法（`getAlbumArt`/`getSongStream` 等）同步化，无外部调用方，签名变更安全。

### 3.6 PlayerContext 监听器与闭包治理（性能 + 正确性）

| 问题 | 后果 | 修复 |
| --- | --- | --- |
| `playNext`/`playPrevious` 未 useCallback | 依赖它们的 `PlaybackQueueEnded`/audio 事件 effect 每次渲染都卸载重注册 | useCallback 化，仅在依赖变化时重建 |
| `removeFromQueue` 在 state updater 内引用外部 `queue` | 连续快速移除多首时读到过期队列 | 改为在 updater 内基于 `prevQueue` 计算相邻歌曲 |
| `useEffect [audioRef.current, playNext]` | ref 变化不触发重渲染，依赖写法无效 | Web 端 Audio 元素在挂载 effect 中一次性创建，事件绑定 effect 仅依赖稳定的 `playNext` |
| URL 构建函数随 auth 渲染重建 | 下游 memo 全部失效 | `authRef` 镜像 + 稳定引用 |
| 未使用的 `error` state、`useTrackPlayerEvents` 等导入 | 代码噪音 | 清理 |

### 3.7 歌词同步算法优化（性能 + 正确性）

原实现每 100ms 线性 `find` + `findIndex`（O(n)×2），并存在两个逻辑 bug：

1. **时间在第一句之前**（前奏阶段）：`find` 找不到当前行 → 走 else 分支**误显示最后一句歌词**；
2. **重复文本**：下一句通过 `findIndex(l => l.text === 当前.text && l.time === 当前.time)` 定位，遇到重复歌词文本时总是定位到第一处，`nextLyric` 错误。

修复后：

```ts
// 二分查找：O(log n)，时间在首句前返回 -1（正确显示空白等待首句）
const findLyricIndex = (list: Lyric[], time: number): number => { … };
// 下一句 = 当前索引 + 1，天然避开重复文本问题
// lastLyricPairRef 缓存：文本无变化时跳过 setCurrentLyric/setNextLyric
```

另：进度轮询频率按播放状态动态调整（播放 100ms / 暂停 500ms），暂停期间减少一半以上的原生 bridge 调用。

### 3.8 Subsonic URL 共享工具（重复代码消除）

新增 `src/utils/subsonic.ts`：

| 导出 | 作用 |
| --- | --- |
| `buildSubsonicParams(auth, extra)` | 生成 `u/t/s/f/v/c` 公共认证参数 |
| `buildCoverArtUrl(auth, id)` | 封面直链（含 `size=300&square=true`） |
| `buildStreamUrl(auth, songId)` | 流媒体直链 |
| `toQueryString(params)` | 参数序列化（自动 encodeURIComponent、忽略 undefined） |
| `SUBSONIC_CLIENT` / `SUBSONIC_API_VERSION` | 客户端标识与协议版本常量 |

原先在 HomeScreen / MiniPlayer / FullScreenPlayer / PlayerContext 四处手写的模板字符串拼接全部替换，参数编码从「裸拼」升级为「正确 URL 编码」。

### 3.9 其他修复

- **通知栏封面 Bug**：`TrackPlayer.add({ artwork: getSongStreamUrl(albumId) })` 把音频流地址当封面 → 原生媒体通知永远无法显示封面。已改为 `buildCoverArtUrl`。
- **tsconfig**：项目覆盖 `"moduleResolution": "node"` 与 `expo/tsconfig.base` 的 `customConditions` 冲突，`npx tsc --noEmit` 直接报 `TS5098`（此前的类型检查从未真正运行过）。已删除该覆盖行，类型检查恢复可用。
- **死代码清理**：`useTrackPlayerEvents`、`useProgress`、`AppKilledPlaybackBehavior`、`useNavigation`/`navigation`、`searchApi`、`activeTab`、`fadeAnim`、`scaleAnim`、`translateY`、`playModeText`、`volumeMask` 样式、`LinearGradient` 的 useMemo 内 require（移至模块级条件加载，避免 Web 端加载原生模块）。

---

## 四、验证结果

```text
$ npx tsc --noEmit
（无输出，退出码 0 —— 全部通过）
```

- 所有改动保持原有功能行为兼容：Web/原生双端播放、切歌、歌词、队列、搜索、登录登出链路接口签名未变（对外的 `usePlayer`/`useAuth` Context 接口完整保留）；
- 唯一的对外签名变化是 `navidromeApi` 中四个无调用方的 URL 构建方法由 `async` 转同步。

## 五、后续建议（按优先级）

1. **回归测试**：真机 + Web 各跑一遍「登录 → 选歌播放 → 切歌 → 拖进度 → 歌词偏移调整并重进 → 队列增删 → 登出重登」全链路；
2. **SettingsScreen / SearchScreen 均为占位页**，可按现有 `usePlayer`/`navidromeApi` 能力补齐（如清理歌词偏移缓存的 `clearAllLyricsOffsets` 已在 FullScreenPlayer 中导出待接入）；
3. **HomeScreen 的 `loadData` 缺依赖**（内部使用 `getCoverArtUrl` 相关闭包之外的固定参数，暂无实际影响），接入 ESLint（`react-hooks` 规则）后可系统化拦截此类隐患；
4. **认证信息明文存储于 AsyncStorage**，后续可迁移 `expo-secure-store` 保管 token/salt；
5. **播放队列不持久化**：App 重启后队列丢失，可考虑将 queue/playMode 持久化并在启动时恢复；
6. HomeScreen 硬编码的 `seed` 随机参数可提取为常量或动态生成，保证「随机专辑」每次刷新真正随机。

---

*本报告由代码优化会话自动整理生成，覆盖本次全部 14 项改动。*
