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
    private var overlayNextText: TextView? = null
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
                    val args = call.arguments as? Map<*, *>
                    showOrUpdate(
                        args?.get("current") as? String ?: "",
                        args?.get("next") as? String ?: "",
                    )
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

    private fun showOrUpdate(current: String, next: String) {
        if (!Settings.canDrawOverlays(this)) return
        val view = overlayView
        if (view == null) {
            createOverlay(current, next)
        } else {
            overlayText?.text = current
            overlayNextText?.apply {
                text = next
                visibility = if (next.isEmpty()) View.GONE else View.VISIBLE
            }
        }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun createOverlay(current: String, next: String) {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val container = android.widget.FrameLayout(this)
        val row = android.widget.LinearLayout(this)
        row.orientation = android.widget.LinearLayout.HORIZONTAL
        row.gravity = android.view.Gravity.CENTER_VERTICAL
        row.setPadding(dp(16), dp(10), dp(8), dp(10))
        // 玻璃卡：深色半透底 + 1px 均匀微亮描边 + 大圆角（API 31+ 再叠加真实背景模糊）
        row.background = android.graphics.drawable.GradientDrawable().apply {
            setColor(Color.parseColor("#B30D1420"))
            cornerRadius = dp(24).toFloat()
            setStroke(dp(1), Color.parseColor("#2EFFFFFF"))
        }

        val lines = android.widget.LinearLayout(this)
        lines.orientation = android.widget.LinearLayout.VERTICAL
        // 当前行：加大加粗 + 文字投影，长句走马灯
        val lyricText = TextView(this).apply {
            this.text = current
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(dp(3).toFloat(), 0f, 0f, Color.parseColor("#99000000"))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1
            isSelected = true
        }
        // 下一行：小号弱化，无下一行时隐藏占位
        val nextText = TextView(this).apply {
            this.text = next
            setTextColor(Color.parseColor("#8CFFFFFF"))
            textSize = 12f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(0, dp(2), 0, 0)
            visibility = if (next.isEmpty()) View.GONE else View.VISIBLE
        }
        lines.addView(lyricText)
        lines.addView(nextText)

        val closeButton = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#B3FFFFFF"))
            textSize = 12f
            gravity = android.view.Gravity.CENTER
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(Color.parseColor("#1FFFFFFF"))
            }
            layoutParams = android.widget.LinearLayout.LayoutParams(dp(24), dp(24)).apply {
                marginStart = dp(12)
            }
        }
        row.addView(lines)
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
        // 真实毛玻璃：模糊小窗背后的内容（设备关闭模糊能力时静默降级为半透底）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.flags =
                params.flags or WindowManager.LayoutParams.FLAG_BLUR_BEHIND
            params.blurBehindRadius = dp(20)
        }
        params.gravity = Gravity.TOP or Gravity.START
        params.x = dp(16)
        params.y = dp(64)

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
        overlayNextText = nextText
    }

    private fun removeOverlay() {
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {}
        }
        overlayView = null
        overlayText = null
        overlayNextText = null
        windowManager = null
    }
}
