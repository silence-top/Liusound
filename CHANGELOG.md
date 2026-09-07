# Changelog — 流声 Liu Sound

产品版本号以 `pubspec.yaml` 的 `version` 为唯一事实来源。变更按主题分节，架构侧详情见 `FEATURES.md`（§13 Invariants / §14 Anti-Patterns / §15 P1 整改补充）。

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
