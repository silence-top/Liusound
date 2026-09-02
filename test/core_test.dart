import 'package:flutter_test/flutter_test.dart';

import 'package:liusound/core/lyrics/lyrics.dart';
import 'package:liusound/core/subsonic/subsonic.dart';
import 'package:liusound/features/auth/auth_controller.dart';

void main() {
  group('parseLyricsData（歌词解析）', () {
    test('单轨：毫秒转秒、过滤空行、按时间排序', () {
      const json = '[{"lang":"en","synced":true,"line":['
          '{"start":2000,"value":"line b"},'
          '{"start":1000,"value":"line a"},'
          '{"start":3000,"value":"  "},'
          '{"start":4000,"value":"line c"}]}]';
      final data = parseLyricsData(json);
      expect(data.lines.map((l) => l.text).toList(),
          ['line a', 'line b', 'line c']);
      expect(data.lines.first.time, 1.0);
      expect(data.translations, isEmpty);
    });

    test('双语：lang 不同的第二轨作为译轨', () {
      const json = '['
          '{"lang":"en","line":['
          '{"start":1000,"value":"hello"},'
          '{"start":2000,"value":"world"}]},'
          '{"lang":"zh","line":['
          '{"start":1000,"value":"你好"},'
          '{"start":2000,"value":"世界"}]}]';
      final data = parseLyricsData(json);
      expect(data.lines.map((l) => l.text), ['hello', 'world']);
      expect(data.translations.map((l) => l.text), ['你好', '世界']);
    });

    test('两轨 lang 相同不视为双语', () {
      const json = '['
          '{"lang":"en","line":[{"start":1000,"value":"a"}]},'
          '{"lang":"en","line":[{"start":1000,"value":"b"}]}]';
      final data = parseLyricsData(json);
      expect(data.lines.map((l) => l.text), ['a']);
      expect(data.translations, isEmpty);
    });

    test('坏 JSON / 空串 / 非法结构返回空数据', () {
      expect(parseLyricsData('not json').lines, isEmpty);
      expect(parseLyricsData('').lines, isEmpty);
      expect(parseLyricsData('[]').lines, isEmpty);
      expect(parseLyricsData('[{"lang":"en"}]').lines, isEmpty);
    });
  });

  group('alignTranslations（译文对齐）', () {
    test('按时间戳对齐，超过 0.5s 阈值不匹配', () {
      const lines = [
        LyricLine(time: 1.0, text: 'a'),
        LyricLine(time: 2.0, text: 'b'),
        LyricLine(time: 3.0, text: 'c'),
      ];
      const trans = [
        LyricLine(time: 1.0, text: '甲'),
        LyricLine(time: 2.05, text: '乙'),
        LyricLine(time: 9.0, text: '丙'),
      ];
      expect(alignTranslations(lines, trans), ['甲', '乙', null]);
    });

    test('空译轨返回全 null', () {
      final aligned = alignTranslations(
          const [LyricLine(time: 1, text: 'a')], const []);
      expect(aligned, [null]);
    });
  });

  group('findLyricIndex（二分定位）', () {
    test('前奏返回 -1，其余命中正确行', () {
      const list = [
        LyricLine(time: 1.0, text: 'a'),
        LyricLine(time: 2.0, text: 'b'),
        LyricLine(time: 3.0, text: 'c'),
      ];
      expect(findLyricIndex(list, 0.5), -1);
      expect(findLyricIndex(list, 1.0), 0);
      expect(findLyricIndex(list, 2.5), 1);
      expect(findLyricIndex(list, 99), 2);
    });
  });

  group('normalizeServerUrl（地址规范化）', () {
    test('补 scheme、去尾斜杠与空白', () {
      expect(
          normalizeServerUrl('192.168.1.10:4533'), 'http://192.168.1.10:4533');
      expect(normalizeServerUrl('https://music.example.com/'),
          'https://music.example.com');
      expect(normalizeServerUrl('  http://a.com//  '), 'http://a.com');
      expect(normalizeServerUrl(''), '');
    });
  });

  group('Subsonic（直链构建）', () {
    test('streamUrl 含认证参数与歌曲 id', () {
      const auth = SubsonicAuth(
        serverUrl: 'http://nav.local',
        username: 'u',
        subsonicToken: 't',
        subsonicSalt: 's',
      );
      final url = Subsonic.streamUrl(auth, 'song1');
      expect(url.startsWith('http://nav.local/rest/stream?'), isTrue);
      for (final part in ['u=u', 't=t', 's=s', 'f=json', 'v=1.8.0',
        'c=NavidromeUI', 'id=song1']) {
        expect(url.contains(part), isTrue, reason: '缺少参数 $part');
      }
    });
  });
}
