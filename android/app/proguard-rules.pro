# R8 keep 规则（Flutter 3.35+ 默认对 release 启用 shrinking）
#
# 修复 Android 15 冷启动闪退：home_widget 传递引入 androidx.work，
# 冷启动时 androidx.startup.InitializationProvider 初始化 WorkManager，
# 其内部 Room 数据库（WorkDatabase 及 R8 生成/混淆的 _Impl 实现类）被
# shrinking 裁剪混淆后运行时反射实例化失败，Application 绑定期即崩
# （崩溃先于任何 Activity 创建，表现为点图标立即退）。
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
