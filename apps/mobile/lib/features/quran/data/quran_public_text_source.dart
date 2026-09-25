import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/mushaf_page.dart';
import '../domain/quran_navigation.dart';
import 'surah_metadata.dart';

/// مصدر عام مباشر لنص القرآن (دون مفاتيح أو أسرار) — يُستخدم كاحتياطي
/// عند تعذّر Supabase Edge Function.
///
/// مصدران عامّان مُتحقق منهما حيًّا (2026-09-23، بلا مفاتيح):
/// 1. خريطة الصفحات: `https://api.quran.com/api/v4/verses/by_page/{page}`
///    (تعيد verse_key وpage_number وjuz_number وhizb_number).
/// 2. نص الآيات (رسم عثماني — حفص):
///    `https://cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1/editions/ara-quranuthmanihaf/{chapter}.json`
///    (بنية موثّقة: `{"chapter":[{"chapter":N,"verse":M,"text":"..."}]}`).
///
/// التخزين على القرص فقط (لا يُحمَّل القرآن كله في الذاكرة): كل سورة
/// تُحفظ في ملف مستقل داخل مجلد الدعم وتُقرأ عند الحاجة فقط.
class QuranPublicTextSource {
  QuranPublicTextSource({http.Client? client, Future<Directory> Function()? supportDirProvider})
      : _client = client ?? http.Client(),
        _supportDirProvider = supportDirProvider ?? getApplicationSupportDirectory;

  final http.Client _client;
  final Future<Directory> Function() _supportDirProvider;

  static const _mappingBase = 'https://api.quran.com/api/v4/verses';
  static const _textBase =
      'https://cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1/editions/ara-quranuthmanihaf';
  static const _timeout = Duration(seconds: 20);

  /// نص صفحة كاملة (وضع النص — حفص) من المصدرين العامّين.
  Future<MushafPage> pageText(int page) async {
    final validated = QuranNavigation.validateTextPage(page);
    final mapping = await _getJson(Uri.parse(
        '$_mappingBase/by_page/$validated?words=false&per_page=all'));
    final rawVerses = (mapping['verses'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (rawVerses.isEmpty) {
      throw StateError('لم تصل بيانات الصفحة $validated من المصدر العام');
    }

    // نجمع أرقام السور المطلوبة ثم نجلب نص كل سورة (كاش قرص أولًا).
    final chapters = <int>{};
    final keys = <String>[];
    for (final v in rawVerses) {
      final key = (v['verse_key'] as String? ?? '').trim();
      if (key.isEmpty) continue;
      keys.add(key);
      final parsed = _splitKey(key);
      if (parsed != null) chapters.add(parsed.chapter);
    }
    if (keys.isEmpty) {
      throw StateError('خريطة الصفحة $validated فارغة من المصدر العام');
    }
    final texts = <int, Map<int, String>>{};
    for (final chapter in chapters) {
      texts[chapter] = await chapterTexts(chapter);
    }

    final ayahs = <MushafAyah>[];
    for (final key in keys) {
      final parsed = _splitKey(key);
      if (parsed == null) continue;
      final text = texts[parsed.chapter]?[parsed.verse];
      if (text == null || text.isEmpty) continue;
      ayahs.add(MushafAyah(
        key: key,
        chapterId: parsed.chapter,
        number: parsed.verse,
        text: text,
        tajweedText: text,
      ));
    }
    if (ayahs.isEmpty) {
      throw StateError('تعذّر بناء نص الصفحة $validated من المصدر العام');
    }
    final first = rawVerses.first;
    return MushafPage(
      number: validated,
      juz: (first['juz_number'] as num?)?.toInt() ?? ((validated - 1) ~/ 20) + 1,
      hizb: (first['hizb_number'] as num?)?.toInt() ?? ((validated - 1) ~/ 10) + 1,
      surahName: _surahDisplayName(ayahs.first.chapterId),
      ayahs: ayahs,
      riwayaId: 'hafs',
    );
  }

  /// رقم الصفحة التي تقع فيها آية معيّنة — من المصدر العام.
  Future<int> lookupPage({required int chapter, required int verse}) async {
    QuranNavigation.parseAyahKey('$chapter:$verse');
    final json = await _getJson(
        Uri.parse('$_mappingBase/by_key/$chapter:$verse?fields=page_number'));
    final verseJson = json['verse'] as Map<String, dynamic>?;
    final page = (verseJson?['page_number'] as num?)?.toInt();
    if (page == null) {
      throw StateError('تعذّر تحديد صفحة الآية $chapter:$verse من المصدر العام');
    }
    return QuranNavigation.validateTextPage(page);
  }

  /// نصوص سورة كاملة: رقم الآية → النص (رسم عثماني — حفص).
  /// من كاش القرص أولًا، ثم الشبكة مع الحفظ.
  Future<Map<int, String>> chapterTexts(int chapter) async {
    if (chapter < 1 || chapter > 114) {
      throw RangeError.range(chapter, 1, 114, 'chapter');
    }
    final file = await _chapterFile(chapter);
    if (await file.exists()) {
      try {
        return _parseChapterJson(jsonDecode(await file.readAsString()));
      } catch (_) {
        // ملف فاسد — نعيد الجلب أدناه.
      }
    }
    final json = await _getJson(Uri.parse('$_textBase/$chapter.json'));
    final parsed = _parseChapterJson(json);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // فشل التخزين لا يمنع الاستخدام الفوري.
    }
    return parsed;
  }

  Map<int, String> _parseChapterJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('بنية نص السورة غير متوقعة');
    }
    final list = json['chapter'];
    if (list is! List || list.isEmpty) {
      throw const FormatException('بنية نص السورة غير متوقعة');
    }
    final out = <int, String>{};
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final verse = (item['verse'] as num?)?.toInt();
      final text = item['text'] as String?;
      if (verse != null && text != null && text.isNotEmpty) {
        out[verse] = text;
      }
    }
    if (out.isEmpty) throw const FormatException('نص السورة فارغ');
    return out;
  }

  Future<File> _chapterFile(int chapter) async {
    final dir = await _supportDirProvider();
    return File('${dir.path}/quran_text/ara-quranuthmanihaf/$chapter.json');
  }

  static String _surahDisplayName(int chapter) {
    if (chapter >= 1 && chapter <= allSurahs.length) {
      return allSurahs[chapter - 1].displayName;
    }
    return 'المصحف الشريف';
  }

  static ({int chapter, int verse})? _splitKey(String key) {
    final parts = key.split(':');
    if (parts.length != 2) return null;
    final chapter = int.tryParse(parts[0]);
    final verse = int.tryParse(parts[1]);
    if (chapter == null || verse == null) return null;
    return (chapter: chapter, verse: verse);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response =
        await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('المصدر العام أعاد ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('استجابة المصدر العام غير متوقعة');
    }
    return decoded;
  }

  void dispose() => _client.close();
}
