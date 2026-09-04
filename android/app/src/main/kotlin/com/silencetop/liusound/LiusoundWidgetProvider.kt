package com.silencetop.liusound

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver

/// 4x2 播放控制小部件：封面 + 标题/歌手 + 上一首/播放暂停/下一首。
/// 数据由 Dart 侧经 home_widget 写入（HomeWidgetPreferences）；
/// 按钮经 MediaButtonReceiver 注入媒体会话（线控/通知栏同链路）。
/// 注意：播放/暂停用标准 KEYCODE_MEDIA_PLAY/PAUSE——audio_service 的
/// BYPASS 键码（KEYCODE_MUTE）在部分厂商 ROM（如 MIUI）会被媒体键白名单
/// 过滤导致「能暂停不能播放」；标准键码走 AppAudioHandler.click 聚合，
/// 与线控单击映射一致（默认即播放/暂停）。
class LiusoundWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, buildViews(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, LiusoundWidgetProvider::class.java),
            )
            for (id in ids) manager.updateAppWidget(id, buildViews(context))
        }
    }

    private fun buildViews(context: Context): RemoteViews {
        // home_widget 0.7 无 per-key getData，直接读其偏好文件（HomeWidgetPreferences）
        val prefs =
            context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val playing = prefs.getBoolean("widget_playing", false)
        return RemoteViews(context.packageName, R.layout.liusound_widget).apply {
            setTextViewText(R.id.widget_title, prefs.getString("widget_title", null) ?: "流声")
            setTextViewText(R.id.widget_artist, prefs.getString("widget_artist", null) ?: "")
            setImageViewBitmap(R.id.widget_cover, coverBitmap(context, prefs.getString("widget_cover_path", null)))
            setOnClickPendingIntent(R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            setOnClickPendingIntent(R.id.widget_play, mediaButton(context, if (playing) KeyEvent.KEYCODE_MEDIA_PAUSE else KeyEvent.KEYCODE_MEDIA_PLAY))
            setOnClickPendingIntent(R.id.widget_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))
        }
    }

    private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, MediaButtonReceiver::class.java)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            keyCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // 封面：优先 Dart 侧写好的文件；缺失时回退 Flutter 资源里的默认占位图
    private fun coverBitmap(context: Context, path: String?): Bitmap? {
        if (path != null) BitmapFactory.decodeFile(path)?.let { return it }
        return try {
            context.assets.open("flutter_assets/assets/app/default-album.png").use {
                BitmapFactory.decodeStream(it)
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.silencetop.liusound.WIDGET_REFRESH"
    }
}
