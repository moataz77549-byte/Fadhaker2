import 'dart:convert';
import 'dart:io';

import 'package:fadhkur_mobile/features/quran/data/quran_api_repository.dart';
import 'package:fadhkur_mobile/features/quran/data/quran_config_repository.dart';
import 'package:fadhkur_mobile/features/quran/data/quran_public_text_source.dart';
import 'package:fadhkur_mobile/features/quran/data/quran_reading_state_repository.dart';
import 'package:fadhkur_mobile/features/quran/domain/riwaya.dart';
import 'package:fadhkur_mobile/features/quran/domain/tafsir_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ملاحظة: كل الحمولات هنا هياكل اصطناعية للاختبار فقط،
/// وليست محتوى قرآنيًا حقيقيًا — ممنوع أي نصوص آيات/تفاسير حقيقية هنا.

/// يبني استجابة HTTP بترميز UTF-8 صريح (مثل الخادم الحقيقي)،
/// لأن http.Response الافتراضي يرمّز Body باللاتينية-1 ويرفض الحروف العربية.
http.Response _jsonResponse(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _functionsBase = 'https://example.supabase.co/functions/v1/quran-yutla-api';

Map<String, dynamic> _pagePayload() => {
      'page': 293,
      'riwaya': 'hafs',
      'surahName': 'سورة الكهف',
      'verses': [
        {
          'verse_key': '18:1',
          'text_uthmani': 'نص-اختباري-1',
          'text_uthmani_tajweed': 'نص-اختباري-1',
          'juz_number': 15,
          'hizb_number': 29,
        },
        {
          'verse_key': '18:2',
          'text_uthmani': 'نص-اختباري-2',
          'text_uthmani_tajweed': 'نص-اختباري-2',
          'juz_number': 15,
          'hizb_number': 29,
        },
      ],
    };

void main() {
  group('QuranApiRepository', () {
    test('يبني رابط الصفحة صحيحًا ويحلّل الآيات', () async {
      http.BaseRequest? captured;
      final client = MockClient((request) async {
        captured = request;
        return _jsonResponse(jsonEncode(_pagePayload()), 200);
      });
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);

      final page = await repo.getPageText(riwaya: RiwayaRegistry.hafs, page: 293);

      expect(captured?.url.path, contains('/quran/page'));
      expect(captured?.url.queryParameters['riwaya'], 'hafs');
      expect(captured?.url.queryParameters['page'], '293');
      expect(page.number, 293);
      expect(page.surahName, 'سورة الكهف');
      expect(page.riwayaId, 'hafs');
      expect(page.ayahs.map((a) => a.key), ['18:1', '18:2']);
      repo.dispose();
    });

    test('لا يرسل أي ترويسة سرّية من التطبيق', () async {
      Map<String, String>? headers;
      final client = MockClient((request) async {
        headers = request.headers;
        return _jsonResponse(jsonEncode(_pagePayload()), 200);
      });
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      await repo.getPageText(riwaya: RiwayaRegistry.hafs, page: 1);
      expect(headers, isNotNull);
      expect(headers!.keys.map((k) => k.toLowerCase()), isNot(contains('x-auth-token')));
      expect(headers!.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      repo.dispose();
    });

    test('يرفض الصفحة خارج النطاق دون طلب شبكة', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      expect(() => repo.getPageText(riwaya: RiwayaRegistry.hafs, page: 605), throwsRangeError);
      expect(called, isFalse);
      repo.dispose();
    });

    test('يرفض رواية نصّها غير متوفّر', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      expect(
        () => repo.getPageText(riwaya: RiwayaRegistry.warsh, page: 1),
        throwsStateError,
      );
      repo.dispose();
    });

    test('عند فشل الـ Backend يسقط للمصدر العام (offline-first)', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'example.supabase.co') {
          return _jsonResponse('{"error":{"message":"رسالة"}}', 500);
        }
        if (request.url.path.contains('/by_page/')) {
          return _jsonResponse(
            jsonEncode({
              'verses': [
                {
                  'verse_key': '1:1',
                  'page_number': 1,
                  'juz_number': 1,
                  'hizb_number': 1,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'cdn.jsdelivr.net') {
          return _jsonResponse(
            jsonEncode({
              'chapter': [
                {'chapter': 1, 'verse': 1, 'text': 'نص-احتياطي'}
              ],
            }),
            200,
          );
        }
        return _jsonResponse('nf', 404);
      });
      final repo = QuranApiRepository(
        client: client,
        functionsBaseUrl: _functionsBase,
        publicSource: QuranPublicTextSource(
          client: client,
          supportDirProvider: () async =>
              Directory.systemTemp.createTempSync('quran_pub_'),
        ),
      );
      // لا شاشة ميتة: المصدر العام ينقذ الموقف حتى مع 500/503 من الخادم.
      final page = await repo.getPageText(riwaya: RiwayaRegistry.hafs, page: 1);
      expect(page.ayahs.single.key, '1:1');
      repo.dispose();
    });

    test('يجلب التفسير ويجرّد HTML', () async {
      http.BaseRequest? captured;
      final client = MockClient((request) async {
        captured = request;
        return _jsonResponse(
          jsonEncode({
            'tafsir': {
              'resource_id': 16,
              'resource_name': 'Tafsir Muyassar',
              'text': '<p>نص <b>اختباري</b></p><p>فقرة ثانية</p>',
            }
          }),
          200,
        );
      });
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      final entry = await repo.getTafsir(source: TafsirSourceRegistry.muyassar, ayahKey: '1:1');
      expect(captured?.url.path, contains('/quran/tafsir/16/ayah/1/1'));
      expect(entry.resourceId, 16);
      expect(entry.plainText, contains('نص اختباري'));
      expect(entry.plainText, isNot(contains('<p>')));
      repo.dispose();
    });

    test('يرفض مفتاح آية خاطئًا قبل الطلب', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      expect(
        () => repo.getTafsir(source: TafsirSourceRegistry.muyassar, ayahKey: 'x'),
        throwsFormatException,
      );
      repo.dispose();
    });

    test('فهرس التفاسير: يحلّل القائمة ويرفض الفارغة', () async {
      final client = MockClient((_) async => _jsonResponse(
            jsonEncode({
              'tafsirs': [
                {'resourceId': 16, 'nameAr': 'التفسير الميسر', 'slug': 'ar-tafsir-muyassar'},
              ]
            }),
            200,
          ));
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      final catalog = await repo.tafsirCatalog();
      expect(catalog.single.resourceId, 16);

      final empty = MockClient((_) async => http.Response(jsonEncode({'tafsirs': []}), 200));
      final repo2 = QuranApiRepository(client: empty, functionsBaseUrl: _functionsBase);
      // offline-first: القائمة الفارغة من الخادم تسقط للقائمة المضمّنة لا الرمي.
      final builtin = await repo2.tafsirCatalog();
      expect(builtin, isNotEmpty);
      expect(builtin, TafsirSourceRegistry.builtin);
      repo.dispose();
      repo2.dispose();
    });

    test('lookupPage يعيد رقم الصفحة ويتحقق منه', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['chapter'], '18');
        expect(request.url.queryParameters['verse'], '1');
        return http.Response(jsonEncode({'chapter': 18, 'verse': 1, 'page': 293}), 200);
      });
      final repo = QuranApiRepository(client: client, functionsBaseUrl: _functionsBase);
      expect(await repo.lookupPage(chapter: 18, verse: 1), 293);
      repo.dispose();
    });
  });

  group('QuranConfigRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Map<String, dynamic> configPayload() => {
          'riwayat': [
            {
              'id': 'warsh',
              'nameAr': 'ورش عن نافع',
              'narratorAr': '',
              'totalPages': 573,
              'pageImageTemplate': 'https://cdn.example.com/w/{page}.webp',
              'qfMushafId': null,
              'textAvailable': false,
              'notesAr': '',
            }
          ],
          'fonts': [],
          'tafsirs': [],
          'fetchedAt': DateTime.now().toIso8601String(),
        };

    test('يجلب الإعدادات ويدمجها فوق المضمّن ويخزّنها', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, contains('/quran/config'));
        return _jsonResponse(jsonEncode(configPayload()), 200);
      });
      final repo = QuranConfigRepository(client: client, functionsBaseUrl: _functionsBase);

      final config = await repo.load();
      // دُمجت قيمة الـ Backend فوق المضمّن
      final warsh = config.riwayat.firstWhere((r) => r.id == 'warsh');
      expect(warsh.totalPages, 573);
      expect(warsh.supportsImagePages, isTrue);
      // حفص بقي من المضمّن
      expect(config.riwayat.firstWhere((r) => r.id == 'hafs').totalPages, 604);
      // الخطوط والتفاسير الافتراضية
      expect(config.fonts.length, 4);
      expect(config.tafsirs.map((t) => t.resourceId), [16, 14, 91, 90]);

      // التحميل الثاني من التخزين المؤقت دون طلب جديد
      await repo.load();
      expect(calls, 1);
      repo.dispose();
    });

    test('عند فشل الشبكة يستخدم المخزّن، ثم الـ fallback المضمّن (لا رمي)', () async {
      final good = MockClient((_) async => _jsonResponse(jsonEncode(configPayload()), 200));
      final repo = QuranConfigRepository(client: good, functionsBaseUrl: _functionsBase);
      await repo.load();
      repo.dispose();

      final bad = MockClient((_) async => http.Response('error', 500));
      final repo2 = QuranConfigRepository(client: bad, functionsBaseUrl: _functionsBase);
      final fromCache = await repo2.load();
      expect(fromCache.riwayat.firstWhere((r) => r.id == 'warsh').totalPages, 573);
      repo2.dispose();

      SharedPreferences.setMockInitialValues({});
      final repo3 = QuranConfigRepository(client: bad, functionsBaseUrl: _functionsBase);
      final fallback = await repo3.load();
      expect(fallback.isFallback, isTrue);
      repo3.dispose();
    });
  });

  group('QuranReadingStateRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('حفظ واسترجاع الإعدادات', () async {
      final repo = QuranReadingStateRepository();
      expect(await repo.riwayaId(), 'hafs');
      await repo.saveRiwayaId('warsh');
      expect(await repo.riwayaId(), 'warsh');

      expect(await repo.fontSize(), 22.0);
      await repo.saveFontSize(100.0);
      expect(await repo.fontSize(), 40.0); // حد أعلى

      await repo.saveReadingMode(QuranReadingMode.text);
      expect(await repo.readingMode(), QuranReadingMode.text);
    });

    test('آخر صفحة تُحفظ لكل رواية على حدة', () async {
      final repo = QuranReadingStateRepository();
      expect(await repo.lastPage('hafs'), isNull);
      await repo.saveLastPage('hafs', 293);
      await repo.saveLastPage('warsh', 100);
      expect(await repo.lastPage('hafs'), 293);
      expect(await repo.lastPage('warsh'), 100);
    });

    test('موقع الآية يبقى عبر تبديل أوضاع المصحف وترحيل الصفحة القديمة', () async {
      final repo = QuranReadingStateRepository();
      await repo.saveLastPage('hafs', 42);
      expect((await repo.lastLocation('hafs'))?.page, 42);
      expect((await repo.lastLocation('hafs'))?.verseKey, isNull);
      await repo.saveLocation('hafs', const QuranLocation(page: 42, verseKey: '2:255'));
      for (final mode in QuranReadingMode.values) {
        await repo.saveReadingMode(mode);
        expect(await repo.readingMode(), mode);
        expect((await repo.lastLocation('hafs'))?.page, 42);
        expect((await repo.lastLocation('hafs'))?.verseKey, '2:255');
      }
      expect(await repo.lastLocation('warsh'), isNull);
    });

    test('مصدر التفسير الافتراضي هو الميسر (16)', () async {
      final repo = QuranReadingStateRepository();
      expect(await repo.tafsirSourceId(), 16);
      await repo.saveTafsirSourceId(91);
      expect(await repo.tafsirSourceId(), 91);
    });
  });
}
