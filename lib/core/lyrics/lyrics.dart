import 'dart:convert';

/// 单行歌词（时间单位：秒）
class LyricLine {
  const LyricLine({required this.time, required this.text});

  final double time;
  final String text;
}

/// 解析 Navidrome JSON 格式歌词（对标 1.x PlayerContext.parseLyrics）：
/// 取第一音轨、毫秒转秒、过滤空行并按时间排序；解析失败返回空列表。
List<LyricLine> parseLyrics(String? lyricsText) {
  if (lyricsText == null || lyricsText.isEmpty) return const [];
  try {
    final dynamic decoded = jsonDecode(lyricsText);
    if (decoded is! List || decoded.isEmpty) return const [];
    final dynamic track = decoded.first;
    if (track is! Map<String, dynamic>) return const [];
    final dynamic lines = track['line'];
    if (lines is! List) return const [];

    final result = <LyricLine>[];
    for (final dynamic line in lines) {
      if (line is! Map<String, dynamic>) continue;
      final String text = line['value']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final double timeSec = ((line['start'] as num?)?.toDouble() ?? 0) / 1000;
      result.add(LyricLine(time: timeSec, text: text));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  } catch (_) {
    return const [];
  }
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
