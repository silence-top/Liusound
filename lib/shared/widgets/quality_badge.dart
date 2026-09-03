import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import 'glass.dart';

/// 音质分级（决定胶囊配色与文案形态）
enum _Grade {
  /// 24bit / ≥96kHz 的无损：金色琥珀高光
  hiRes(Color(0x33C89B3C), Color(0xFFFFD479), Color(0xFFFFEBC2)),

  /// 16bit 无损：主题天蓝微亮（沿用既有格式标签配色）
  lossless(AppTheme.formatBg, AppTheme.formatBorder, AppTheme.formatText),

  /// AAC / MP3 等有损转码：中灰半透明低调展示
  lossy(Color(0x1FFFFFFF), Color(0x40FFFFFF), Color(0xFFBDBDBD));

  const _Grade(this.bg, this.border, this.text);

  final Color bg;
  final Color border;
  final Color text;
}

/// 音质/码率徽标：高透玻璃胶囊 + 音质色彩分级。
///
/// 六种后端的元数据能力不一（Subsonic 系不返回位深，Audio Station 可能连
/// 采样率都没有），因此这里全程按「有什么显示什么」降级：
/// 缺位深/采样率就不写 bit 信息，缺格式就只显示码率，全缺则不渲染——
/// 绝不把 MP3 标成 flac，也不编造后端没给的参数。
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.song, this.trailingGap = 0});

  final Song song;

  /// 徽标右侧间距；仅在徽标真的渲染出来时生效（元数据全缺时不留空隙）
  final double trailingGap;

  static const _losslessFormats = {
    'flac',
    'alac',
    'wav',
    'wave',
    'aiff',
    'aif',
    'ape',
    'wv',
    'tak',
    'tta',
    'dsf',
    'dff',
  };

  /// 格式名：优先容器后缀，其次解码器名；兼容 audio/flac 这类 MIME 写法
  static String? formatOf(Song song) {
    final raw = (song.suffix ?? song.codec)?.toLowerCase().trim();
    if (raw == null || raw.isEmpty) return null;
    final slash = raw.lastIndexOf('/');
    final name = slash >= 0 ? raw.substring(slash + 1) : raw;
    return name.isEmpty ? null : name;
  }

  /// 码率 kbps：后端给了就用，没给按 文件大小÷时长 估算（对齐 1.x 算法）
  static int? kbpsOf(Song song) {
    final reported = song.bitRate;
    if (reported != null && reported > 0) return reported;
    if (song.size > 0 && song.duration > 0) {
      return ((song.size * 8) / song.duration / 1000).round();
    }
    return null;
  }

  static bool isLossless(Song song) {
    final format = formatOf(song);
    return format != null && _losslessFormats.contains(format);
  }

  /// Hi-Res 判定必须同时满足「无损容器」，否则 24bit 的 AAC 也会被误判成金色
  static bool isHiRes(Song song) =>
      isLossless(song) &&
      ((song.bitDepth ?? 0) >= 24 || (song.sampleRate ?? 0) >= 96000);

  /// 音质等级文案；格式与码率全缺时返回 null（信息弹窗据此隐藏该行）
  static String? gradeLabel(Song song) {
    if (formatOf(song) == null && kbpsOf(song) == null) return null;
    if (isHiRes(song)) return 'Hi-Res 高解析';
    return isLossless(song) ? '无损' : '有损';
  }

  String? get _format => formatOf(song);

  int? get _kbps => kbpsOf(song);

  bool get _isHiRes => isHiRes(song);

  @override
  Widget build(BuildContext context) {
    final format = _format;
    final kbps = _kbps;
    if (format == null && kbps == null) return const SizedBox.shrink();

    final grade = _isHiRes
        ? _Grade.hiRes
        : isLossless(song)
        ? _Grade.lossless
        : _Grade.lossy;

    final badge = GlassSurface(
      radius: GlassTokens.radiusPill,
      blur: 0,
      tint: grade.bg,
      gradientBorder: false,
      borderColor: grade.border,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        _label(format, kbps),
        style: TextStyle(
          color: grade.text,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    return trailingGap > 0
        ? Padding(
            padding: EdgeInsets.only(right: trailingGap),
            child: badge,
          )
        : badge;
  }

  /// flac 24bit/96kHz ｜ flac 1030K ｜ mp3 320K ｜ 320K（格式未知）
  String _label(String? format, int? kbps) {
    if (_isHiRes) {
      final depth = song.bitDepth;
      final hz = song.sampleRate;
      final khz = hz == null || hz <= 0
          ? null
          : (hz % 1000 == 0 ? '${hz ~/ 1000}' : (hz / 1000).toStringAsFixed(1));
      final parts = [
        if (depth != null && depth > 0) '${depth}bit',
        if (khz != null) '${khz}kHz',
      ];
      // 理论上进不来（_isHiRes 要求二者之一），兜底避免输出 "flac " 这种尾巴
      if (parts.isEmpty) return format ?? '${kbps}K';
      return '${format ?? '?'} ${parts.join('/')}';
    }
    final name = format ?? '';
    if (kbps == null) return name;
    return name.isEmpty ? '${kbps}K' : '$name ${kbps}K';
  }
}
