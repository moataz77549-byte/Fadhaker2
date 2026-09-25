import 'dart:convert';
import 'dart:io';

import 'package:fadhkur_mobile/features/quran/data/quran_api_repository.dart';
import 'package:fadhkur_mobile/features/quran/data/quran_public_text_source.dart';
import 'package:fadhkur_mobile/features/quran/domain/riwaya.dart';
import 'package:fadhkur_mobile/features/quran/domain/tafsir_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// ملاحظة: كل النصوص هنا عناصر نائبة اصطناعية للاختبار فقط
/// (T1…T7) وليست آيات قرآنية حقيقية — ممنوع أي نصوص حقيقية هنا.

http.Response _jsonResponse(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _functionsBase = 'https://example.supabase.co/functions/v1/quran-yutla-api';

/// عميل وهمي يوجّه حسب المضيف: الـ Backend يفشل دائمًا،
/// والمصدران العامّان يعيدان حمولات مُثبتة البنية.
MockClient _publicOnlyClient() => MockClient((request) async {
      final url = request.url;
      if (url.host == 'example.supabase.co') {
        return _jsonResponse('down', 500);
      }
      if (url.host == 'api.quran.com') {
        if (url.path.contains('/by_page/')) {
          return _jsonResponse(
            jsonEncode({
              'verses': List.generate(
                7,
                (i) => {
                  'verse_key': '1:${i + 1}',
                  'page_number': 1,
                  'juz_number': 1,
                  'hizb_number': 1,
                },
              ),
            }),
            200,
          );
        }
        if (url.path.contains('/by_key/')) {
          return _jsonResponse(
            jsonEncode({
              'verse': {
                'verse_key': '2:255',
                'page_number': 42,
                'juz_number': 3,
              }
            }),
            200,
          );
        }
      }
      if (url.host == 'cdn.jsdelivr.net') {
        return _jsonResponse(
          jsonEncode({
            'chapter': List.generate(
              7,
              (i) => {'chapter': 1, 'verse': i + 1, 'text': 'T${i + 1}'},
            ),
          }),
          200,
        );
      }
      return _jsonResponse('not found', 404);
    });

void main() {
  group('QuranApiRepository public fallback', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('quran_text_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    QuranApiRepository _repo() => QuranApiRepository(
          client: _publicOnlyClient(),
          functionsBaseUrl: _functionsBase,
          publicSource: QuranPublicTextSource(
            client: _publicOnlyClient(),
            supportDirProvider: () async => tempDir,
          ),
        );

    test('getPageText يسقط للمصدر العام عند فشل الـ Backend', () async {
      final repo = _repo();
      final page = await repo.getPageText(riwaya: RiwayaRegistry.hafs, page: 1);

      expect(page.number, 1);
      expect(page.ayahs, hasLength(7));
      expect(page.ayahs.first.key, '1:1');
      expect(page.ayahs.first.text, 'T1');
      expect(page.surahName, contains('الفاتحة'));
      expect(page.riwayaId, 'hafs');
      repo.dispose();
    });

    test('lookupPage يسقط للمصدر العام عند فشل الـ Backend', () async {
      final repo = _repo();
      final page = await repo.lookupPage(chapter: 2, verse: 255);
      expect(page, 42);
      repo.dispose();
    });

    test('getTafsir يرمي رسالة صادقة (لا شاشة ميتة ولا نص مُختلَق)', () async {
      final repo = _repo();
      await expectLater(
        repo.getTafsir(source: TafsirSourceRegistry.muyassar, ayahKey: '1:1'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('تحقق من الاتصال'),
        )),
      );
      repo.dispose();
    });

    test('tafsirCatalog يعود للقائمة المضمّنة عند فشل الـ Backend', () async {
      final repo = _repo();
      final catalog = await repo.tafsirCatalog();
      expect(catalog.map((s) => s.resourceId),
          containsAll([16, 14, 91, 90]));
      repo.dispose();
    });

    test('نص السورة يُخزَّن على القرص ولا يُعاد جلبه', () async {
      var hits = 0;
      final source = QuranPublicTextSource(
        client: MockClient((request) async {
          if (request.url.host == 'cdn.jsdelivr.net') {
            hits++;
            return _jsonResponse(
              jsonEncode({
                'chapter': [
                  {'chapter': 1, 'verse': 1, 'text': 'T1'}
                ],
              }),
              200,
            );
          }
          return _jsonResponse('nf', 404);
        }),
        supportDirProvider: () async => tempDir,
      );
      await source.chapterTexts(1);
      await source.chapterTexts(1);
      expect(hits, 1);
      source.dispose();
    });
  });
}
