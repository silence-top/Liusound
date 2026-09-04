import 'dart:convert';

/// 单行歌词（时间单位：秒）
class LyricLine {
  const LyricLine({required this.time, required this.text});

  final double time;
  final String text;
}

/// 歌词解析结果：主轨（原文）+ 可选译轨（双语歌词）
class LyricsData {
  const LyricsData({this.lines = const [], this.translations = const []});

  /// 主轨歌词行（按时间升序）
  final List<LyricLine> lines;

  /// 译轨歌词行（按时间升序；无译轨时为空）
  final List<LyricLine> translations;
}

/// 解析 Navidrome JSON 格式歌词（对标 1.x parseLyrics 并扩展双语）：
/// - 主轨取第一音轨（毫秒转秒、过滤空行、按时间排序）
/// - 译轨取第一条 lang 不同的音轨（双语歌词两轨时间戳一致）
/// 解析失败返回空数据。
LyricsData parseLyricsData(String? lyricsText) {
  final tracks = parseLyricsTracks(lyricsText);
  if (tracks.isEmpty) return const LyricsData();
  final (mainLang, mainLines) = tracks.first;
  List<LyricLine>? translation;
  for (final (lang, lines) in tracks) {
    if (lang != mainLang) {
      translation = lines;
      break;
    }
  }
  return LyricsData(lines: mainLines, translations: translation ?? const []);
}

/// 解析全部音轨（「切换歌词」弹窗用）：返回 (lang, lines) 列表。
/// 解析失败或无音轨返回空列表。
List<(String, List<LyricLine>)> parseLyricsTracks(String? lyricsText) {
  if (lyricsText == null || lyricsText.isEmpty) return const [];
  try {
    final dynamic decoded = jsonDecode(lyricsText);
    if (decoded is! List || decoded.isEmpty) return const [];

    // 逐轨解析（lang, lines）
    final tracks = <(String, List<LyricLine>)>[];
    for (final dynamic track in decoded) {
      if (track is! Map<String, dynamic>) continue;
      final dynamic lines = track['line'];
      if (lines is! List) continue;

      final parsed = <LyricLine>[];
      for (final dynamic line in lines) {
        if (line is! Map<String, dynamic>) continue;
        final String text = line['value']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final double timeSec =
            ((line['start'] as num?)?.toDouble() ?? 0) / 1000;
        parsed.add(LyricLine(time: timeSec, text: text));
      }
      if (parsed.isEmpty) continue;
      parsed.sort((a, b) => a.time.compareTo(b.time));
      tracks.add((track['lang']?.toString() ?? '', parsed));
    }
    return tracks;
  } catch (_) {
    return const [];
  }
}

/// 解析经典 LRC 文本（`[mm:ss.xx]歌词`，本地导入歌词用）：
/// 支持一行多时间戳、[ti:]/[ar:]/[by:] 等元数据标签（忽略）、
/// 毫秒 2 位或 3 位均可。无法解析任何时间行时返回空列表。
List<LyricLine> parseLrcText(String lrc) {
  final result = <LyricLine>[];
  final tag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final raw in const LineSplitter().convert(lrc)) {
    final matches = tag.allMatches(raw);
    if (matches.isEmpty) continue;
    final text = raw.substring(matches.last.end).trim();
    if (text.isEmpty) continue;
    for (final m in matches) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final fracRaw = m.group(3) ?? '0';
      // 2 位 = 厘秒，3 位 = 毫秒
      final frac = int.parse(fracRaw) / (fracRaw.length == 3 ? 1000 : 100);
      result.add(LyricLine(time: minutes * 60 + seconds + frac, text: text));
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

/// 单轨便捷封装：仅返回主轨歌词行
List<LyricLine> parseLyrics(String? lyricsText) =>
    parseLyricsData(lyricsText).lines;

/// 将译轨按时间戳对齐到主轨行（时间差 < 0.5s 视为同一行）。
/// 返回与 [lines] 等长的列表：每项为该行译文或 null（无匹配译文）。
List<String?> alignTranslations(
  List<LyricLine> lines,
  List<LyricLine> translations,
) {
  final result = List<String?>.filled(lines.length, null);
  if (translations.isEmpty) return result;
  var j = 0;
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].time;
    // 双指针推进到时间上最接近的译文行
    while (j < translations.length - 1 &&
        (translations[j].time - t).abs() >
            (translations[j + 1].time - t).abs()) {
      j++;
    }
    if ((translations[j].time - t).abs() < 0.5) {
      result[i] = translations[j].text;
    }
  }
  return result;
}

/// 合并 LRC 同时间轴双语行：相邻时间戳相同的两行 → 前行原文、后行译文。
/// 与原文完全相同的重复行会被跳过（部分 LRC 工具会整行重复）。
/// 返回 (合并后主轨行, 与主轨逐行对齐的译文列表，无译文为 null)。
(List<LyricLine>, List<String?>) mergeDuplicateTimestamps(
  List<LyricLine> lines,
) {
  final main = <LyricLine>[];
  final translations = <String?>[];
  var i = 0;
  while (i < lines.length) {
    main.add(lines[i]);
    var j = i + 1;
    while (j < lines.length &&
        lines[j].time == lines[i].time &&
        lines[j].text == lines[i].text) {
      j++;
    }
    if (j < lines.length && lines[j].time == lines[i].time) {
      translations.add(lines[j].text);
      i = j + 1;
    } else {
      translations.add(null);
      i = j;
    }
  }
  return (main, translations);
}

/// 二分查找：返回 time 所处歌词行索引（时间在首句之前返回 -1）
int findLyricIndex(List<LyricLine> list, double time) {
  var lo = 0;
  var hi = list.length - 1;
  var ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid].time <= time) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
