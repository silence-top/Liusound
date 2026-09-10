import 'package:lpinyin/lpinyin.dart';

import '../api/server_adapter.dart';
import '../models/models.dart';

export '../api/server_adapter.dart' show SongSort;

/// 歌曲列表排序偏好；全局记忆于本地（null = 各列表的原始顺序）
class SongSortPref {
  const SongSortPref({required this.field, required this.ascending});

  final SongSort field;
  final bool ascending;

  SongSortPref copyWith({SongSort? field, bool? ascending}) => SongSortPref(
    field: field ?? this.field,
    ascending: ascending ?? this.ascending,
  );
}

/// 排序弹层可选字段（random 不进菜单：随机不是可持久排序）
const kSortableSongFields = [
  SongSort.recentlyAdded,
  SongSort.title,
  SongSort.artist,
  SongSort.album,
  SongSort.duration,
  SongSort.rating,
  SongSort.mostPlayed,
  SongSort.recentlyPlayed,
];

String songSortLabel(SongSort field) => switch (field) {
  SongSort.recentlyAdded => '加入时间',
  SongSort.title => '标题',
  SongSort.artist => '歌手',
  SongSort.album => '专辑',
  SongSort.duration => '时长',
  SongSort.rating => '评分',
  SongSort.mostPlayed => '播放次数',
  SongSort.recentlyPlayed => '最近播放',
  _ => '默认',
};

/// 全量快照排序。歌曲列表（曲库/歌单/喜欢/流派/本地）的取数都是完整列表，
/// 在完整列表上排序与服务端排序结果完全等价；中文按拼音序（与艺人索引一致）。
/// 非主键的次级键恒为标题拼音升序，保证任意方向下排序稳定可预期。
List<Song> sortSongs(List<Song> songs, SongSortPref? pref) {
  if (pref == null || songs.length < 2) return songs;
  final field = pref.field;
  // 主键预计算：比较器在 O(n log n) 次比较里直接查表，不在比较内算拼音
  final textKeys =
      field == SongSort.title ||
          field == SongSort.artist ||
          field == SongSort.album
      ? {for (final s in songs) s: _pinyinKey(_textField(s, field))}
      : const <Song, String>{};
  final titleKeys = {for (final s in songs) s: _pinyinKey(s.title)};

  int compare(Song a, Song b) {
    int cmp;
    switch (field) {
      case SongSort.title:
      case SongSort.artist:
      case SongSort.album:
        cmp = textKeys[a]!.compareTo(textKeys[b]!);
      case SongSort.duration:
        cmp = a.duration.compareTo(b.duration);
      case SongSort.rating:
        cmp = a.rating.compareTo(b.rating);
      case SongSort.mostPlayed:
        cmp = a.playCount.compareTo(b.playCount);
      case SongSort.recentlyAdded:
        cmp = _timeCmp(a.created, b.created);
      case SongSort.recentlyPlayed:
        cmp = _timeCmp(a.lastPlayed, b.lastPlayed);
      case _:
        return 0;
    }
    if (cmp != 0) return pref.ascending ? cmp : -cmp;
    return titleKeys[a]!.compareTo(titleKeys[b]!);
  }

  return [...songs]..sort(compare);
}

String _textField(Song s, SongSort field) => switch (field) {
  SongSort.artist => s.artist,
  SongSort.album => s.album,
  _ => s.title,
};

/// ISO8601 字符串同源可直接比较；无时间视为空串（恒排最后）
int _timeCmp(String? a, String? b) => (a ?? '').compareTo(b ?? '');

/// 文本键：中文转拼音（与艺人列表索引同一策略），忽略大小写
String _pinyinKey(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return '';
  return PinyinHelper.getPinyin(t, separator: ' ').toLowerCase();
}
