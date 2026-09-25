import 'dart:convert';

import 'package:fadhkur_mobile/features/quran/data/quran_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// يبني استجابة HTTP بترميز UTF-8 صريح (مثل الخادم الحقيقي).
http.Response _jsonResponse(String body, int status) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _functionsBase = 'https://example.supabase.co/functions/v1/quran-yutla-api';

void main() {
  group('QuranConfigRepository offline-first', () {
    test('عند فشل الـ Backend والكاش يُرجع الـ fallback المضمّن', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((_) async => _jsonResponse('error', 500));
      final repo = QuranConfigRepository(
        client: client,
        functionsBaseUrl: _functionsBase,
      );

      final config = await repo.load();

      expect(config.isFallback, isTrue);
      // نسختا المصحف المدني المضمّنتان بروابط QuranHub المحققة.
      expect(config.editions.map((e) => e.id),
          containsAll(['hafs-madani', 'hafs-madani-tajweed']));
      expect(config.editions.every((e) => e.supportsPages), isTrue);
      // الروايات الأربع والخطوط الأربعة وفهرس التفاسير.
      expect(config.riwayat.map((r) => r.id),
          containsAll(['hafs', 'warsh', 'qalun', 'duri']));
      expect(config.fonts.map((f) => f.id),
          containsAll(['uthmanic-hafs', 'kfgqpc-hafs', 'qcf', 'uthmanic-vector']));
      expect(config.tafsirs, hasLength(4));
      // حفص جاهزة للعرض المصوّر فورًا.
      final hafs = config.riwayat.firstWhere((r) => r.id == 'hafs');
      expect(hafs.textAvailable, isTrue);
      repo.dispose();
    });

    test('الكاش الصالح يُقدَّم على الـ fallback', () async {
      SharedPreferences.setMockInitialValues({});
      final okPayload = jsonEncode({
        'riwayat': [
          {
            'id': 'hafs',
            'nameAr': 'حفص',
            'totalPages': 604,
            'textAvailable': true,
          }
        ],
        'editions': [],
        'fonts': [],
        'tafsirs': [],
        'fetchedAt': DateTime.now().toIso8601String(),
      });
      final okClient = MockClient((_) async => _jsonResponse(okPayload, 200));
      final repo = QuranConfigRepository(
        client: okClient,
        functionsBaseUrl: _functionsBase,
      );
      final first = await repo.load();
      expect(first.isFallback, isFalse);

      // الآن الـ Backend ميت — يجب أن يعود الكاش لا الـ fallback.
      final deadClient = MockClient((_) async => _jsonResponse('error', 500));
      final repo2 = QuranConfigRepository(
        client: deadClient,
        functionsBaseUrl: _functionsBase,
      );
      final second = await repo2.load();
      expect(second.isFallback, isFalse);
      expect(second.riwayat.first.id, 'hafs');
      repo.dispose();
      repo2.dispose();
    });

    test('load لا ترمي أبدًا عند أول تشغيل دون شبكة', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((_) async => throw http.ClientException('no network'));
      final repo = QuranConfigRepository(
        client: client,
        functionsBaseUrl: _functionsBase,
      );
      // لو رُمي هنا لفشل الاختبار — شاشة المصحف يجب ألا تموت.
      final config = await repo.load();
      expect(config.editions, isNotEmpty);
      repo.dispose();
    });
  });
}
