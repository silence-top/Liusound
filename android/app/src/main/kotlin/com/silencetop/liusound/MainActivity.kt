package com.silencetop.liusound

import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// 悬浮歌词（Android）：SYSTEM_ALERT_WINDOW 小窗显示当前歌词行，
/// 支持拖动 + 点击关闭按钮隐藏；iOS 无对应能力，Dart 侧入口已隐藏
class MainActivity : AudioServiceActivity() {
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayText: TextView? = null
    private var floatingLyricsChannel: MethodChannel? = null
    private val effects = AudioEffects()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        floatingLyricsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.silencetop.liusound/floating_lyrics",
        )
        floatingLyricsChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(Settings.canDrawOverlays(this))
                "requestPermission" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName"),
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "update" -> {
                    showOrUpdate(call.arguments as? String ?: "")
                    result.success(null)
                }
                "hide" -> {
                    removeOverlay()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // EQ/低音/空间音效：挂载到 just_audio 的 Android 音频会话
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.silencetop.liusound/audio_effects",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "init" -> result.success(effects.init(call.arguments as Int))
                    "setEq" -> {
                        val args = call.arguments as Map<*, *>
                        effects.setEq(args["enabled"] as Boolean)
                        result.success(null)
                    }
                    "setBandLevel" -> {
                        val args = call.arguments as Map<*, *>
                        effects.setBandLevel(args["index"] as Int, args["level"] as Int)
                        result.success(null)
                    }
                    "setBass" -> {
                        effects.setBass(call.arguments as Int)
                        result.success(null)
                    }
                    "setVirtualizer" -> {
                        effects.setVirtualizer(call.arguments as Int)
                        result.success(null)
                    }
                    "release" -> {
                        effects.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("EFFECT_ERROR", e.message, null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        floatingLyricsChannel?.invokeMethod(
            "permissionChanged",
            Settings.canDrawOverlays(this),
        )
    }

    private fun showOrUpdate(text: String) {
        if (!Settings.canDrawOverlays(this)) return
        val view = overlayView
        if (view == null) {
            createOverlay(text)
        } else {
            overlayText?.text = text
        }
    }

    private fun createOverlay(text: String) {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val container = android.widget.FrameLayout(this)
        val row = android.widget.LinearLayout(this)
        row.orientation = android.widget.LinearLayout.HORIZONTAL
        row.setPadding(20, 10, 12, 10)
        row.background = android.graphics.drawable.GradientDrawable().apply {
            setColor(Color.parseColor("#CC101820"))
            cornerRadius = 36f
            setStroke(1, Color.parseColor("#33FFFFFF"))
        }
        val lyricText = TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(4f, 0f, 0f, Color.parseColor("#99000000"))
            maxLines = 1
        }
        val closeButton = TextView(this).apply {
            setTextColor(Color.parseColor("#B0FFFFFF"))
            textSize = 14f
            this.text = " ✕"
        }
        row.addView(lyricText)
        row.addView(closeButton)
        container.addView(row)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = 40
        params.y = 200

        // 拖动：跟随手指位移；点按关闭按钮移除小窗并停更（下次 update 重建）
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - downX).toInt()
                    params.y = startY + (event.rawY - downY).toInt()
                    wm.updateViewLayout(container, params)
                    true
                }
                else -> false
            }
        }
        closeButton.setOnClickListener {
            removeOverlay()
            floatingLyricsChannel?.invokeMethod("closed", null)
        }

        wm.addView(container, params)
        windowManager = wm
        overlayView = container
        overlayText = lyricText
    }

    private fun removeOverlay() {
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {}
        }
        overlayView = null
        overlayText = null
        windowManager = null
    }
}
