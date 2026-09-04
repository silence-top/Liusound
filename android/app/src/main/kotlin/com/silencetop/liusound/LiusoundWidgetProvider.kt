package com.silencetop.liusound

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver

/// 4x2 播放控制小部件：标题/歌手 + 上一首/播放暂停/下一首。
/// 数据由 Dart 侧经 home_widget 写入（HomeWidgetPreferences）；
/// 按钮经 MediaButtonReceiver 注入媒体会话（线控/通知栏同链路），
/// 播放/暂停用 audio_service 的 BYPASS 键码直通，不经线控单击映射。
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
            setImageViewResource(
                R.id.widget_play,
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
            )
            setOnClickPendingIntent(R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            setOnClickPendingIntent(R.id.widget_play, mediaButton(context, if (playing) KEYCODE_BYPASS_PAUSE else KEYCODE_BYPASS_PLAY))
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

    companion object {
        const val ACTION_REFRESH = "com.silencetop.liusound.WIDGET_REFRESH"

        // 对齐 audio_service AudioService.java 的 BYPASS 键码（直通 onPlay/onPause）
        const val KEYCODE_BYPASS_PLAY = KeyEvent.KEYCODE_MUTE
        const val KEYCODE_BYPASS_PAUSE = KeyEvent.KEYCODE_MEDIA_RECORD
    }
}
