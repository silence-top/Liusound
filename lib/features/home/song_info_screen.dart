import 'package:flutter/material.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../player/mini_player.dart';
import 'artist_detail_screen.dart';
import 'detail_screen.dart';

/// 歌曲详情页（对标设计图「歌曲信息」）：基础 / 扩展 / 回放增益 三组信息卡。
/// 由歌曲操作弹窗的「歌曲信息」入口进入；后端缺字段时显示 —。
class SongInfoScreen extends StatelessWidget {
  const SongInfoScreen({super.key, required this.song});

  final Song song;

  bool get _hasLyrics => parseLyricsData(song.lyrics).lines.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final rg = song.replayGain;
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 56,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('歌曲详情'),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(context, '基础', [
                    _row('标题', song.title),
                    _navRow(
                      context,
                      '专辑',
                      song.album.isEmpty ? '—' : song.album,
                      onTap: song.albumId.isEmpty
                          ? null
                          : () => _openAlbum(context),
                    ),
                    _row('专辑艺术家', song.albumArtist ?? song.artist),
                    _navRow(
                      context,
                      '歌手',
                      song.artist,
                      onTap: song.artistId.isEmpty
                          ? null
                          : () => _openArtist(context),
                    ),
                    _navRow(
                      context,
                      '歌词',
                      _hasLyrics ? '查看歌词' : '暂无歌词',
                      onTap: _hasLyrics ? () => _showLyrics(context) : null,
                    ),
                    _row('年代', _num(song.year)),
                    _row('碟号', _num(song.discNumber)),
                    _row('音轨号', _num(song.trackNumber)),
                  ]),
                  _section(context, '扩展', [
                    _row('文件路径', song.path ?? '—', wide: true),
                    _row(
                      '文件大小',
                      song.size > 0
                          ? '${(song.size / 1024 / 1024).toStringAsFixed(2)} MB'
                          : '—',
                    ),
                    _row('文件格式', song.suffix ?? '—'),
                    _row('时长', _fmtDuration(song.duration)),
                    _row(
                      '比特率',
                      song.bitRate != null ? '${song.bitRate} kbps' : '—',
                    ),
                    _row('播放次数', '${song.playCount}'),
                    _row('上次播放时间', _fmtIso(song.lastPlayed) ?? '—'),
                    _row('创建时间', _fmtIso(song.created) ?? '—'),
                  ]),
                  if (rg != null)
                    _section(context, '回放增益', [
                      _row('专辑回放增益', _db(rg.albumGain)),
                      _row('专辑峰值振幅', _plain(rg.albumPeak)),
                      _row('音轨回放增益', _db(rg.trackGain)),
                      _row('音轨峰值振幅', _plain(rg.trackPeak)),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAlbum(BuildContext context) {
    Navigator.of(context).push(
      fadeRoute<void>(
        AlbumDetailScreen(
          albumId: song.albumId,
          title: song.album,
          subtitle: song.artist,
        ),
      ),
    );
  }

  void _openArtist(BuildContext context) {
    Navigator.of(context).push(
      fadeRoute<void>(
        ArtistDetailScreen(artistId: song.artistId, artistName: song.artist),
      ),
    );
  }

  void _showLyrics(BuildContext context) {
    final text = parseLyricsData(song.lyrics).lines
        .map((l) => l.text)
        .join('\n');
    glassDialog<void>(
      context,
      title: '歌词',
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.7,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String label, List<Widget> rows) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 0, 10),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          GlassCard(
            radius: AppRadius.l,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l,
              vertical: AppSpacing.s,
            ),
            child: Column(children: rows),
          ),
        ],
      );

  Widget _row(String label, String value, {bool wide = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              maxLines: wide ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  /// 可点击行（带右箭头）；[onTap] 为 null 时退化为普通行（无箭头）
  Widget _navRow(
    BuildContext context,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    if (onTap == null) return _row(label, value);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 20, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

String _num(int? v) => v == null || v <= 0 ? '—' : '$v';

String _db(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} db';

String _plain(double? v) => v == null ? '—' : v.toStringAsFixed(1);

String _fmtDuration(double seconds) {
  final d = Duration(seconds: seconds.round());
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// ISO8601 / epoch 秒统一格式化为 yyyy-MM-dd HH:mm:ss；解析失败返回 null
String? _fmtIso(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  var dt = DateTime.tryParse(raw);
  if (dt == null) {
    final sec = int.tryParse(raw);
    if (sec != null) dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  }
  if (dt == null) return null;
  String p(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${p(dt.month)}-${p(dt.day)} '
      '${p(dt.hour)}:${p(dt.minute)}:${p(dt.second)}';
}
