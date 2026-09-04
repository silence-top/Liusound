package com.silencetop.liusound

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer

/// Android 音效链：Equalizer + BassBoost + Virtualizer，
/// 挂载到 just_audio 的音频会话（androidAudioSessionId）。
/// 波段数由设备决定（通常 5 段），波段信息回传 Dart 供 UI 动态渲染。
class AudioEffects {
    private var eq: Equalizer? = null
    private var bass: BassBoost? = null
    private var virt: Virtualizer? = null

    /// 挂载会话并返回设备波段信息；失败抛出由 Dart 捕获
    fun init(sessionId: Int): Map<String, Any> {
        release()
        val e = Equalizer(0, sessionId)
        eq = e
        e.enabled = true
        val range = e.bandLevelRange
        val minMb = range[0].toInt()
        val maxMb = range[1].toInt()
        val bands = (0 until e.numberOfBands).map { i ->
            mapOf(
                "centerHz" to (e.getCenterFreq(i.toShort()) / 1000.0),
                "minMb" to minMb,
                "maxMb" to maxMb,
            )
        }
        bass = try {
            BassBoost(0, sessionId)
        } catch (_: Exception) {
            null
        }
        virt = try {
            Virtualizer(0, sessionId)
        } catch (_: Exception) {
            null
        }
        return mapOf("bands" to bands)
    }

    fun setEq(enabled: Boolean) {
        try {
            eq?.enabled = enabled
        } catch (_: Exception) {}
    }

    fun setBandLevel(index: Int, mb: Int) {
        try {
            eq?.setBandLevel(index.toShort(), mb.toShort())
        } catch (_: Exception) {}
    }

    fun setBass(strength: Int) {
        try {
            val b = bass ?: return
            b.enabled = strength > 0
            b.setStrength(strength.toShort())
        } catch (_: Exception) {}
    }

    fun setVirtualizer(strength: Int) {
        try {
            val v = virt ?: return
            v.enabled = strength > 0
            v.setStrength(strength.toShort())
        } catch (_: Exception) {}
    }

    fun release() {
        try { eq?.release() } catch (_: Exception) {}
        try { bass?.release() } catch (_: Exception) {}
        try { virt?.release() } catch (_: Exception) {}
        eq = null
        bass = null
        virt = null
    }
}
