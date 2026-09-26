import 'dart:convert';

import 'package:fadhkur_mobile/features/quran/data/quran_api_repository.dart';
import 'package:fadhkur_mobile/features/quran/domain/quran_search_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('keeps Quran text matches distinct from navigation matches', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/quran/search'));
      expect(request.url.queryParameters['q'], 'الصبر');
      return http.Response(
        jsonEncode({
          'result': {
            'navigation': [
              {'result_type': 'surah', 'key': 103, 'name': 'العصر'}
            ],
            'verses': [
              {
                'result_type': 'ayah',
                'key': '2:153',
                'name': 'نتيجة اختبارية'
              }
            ],
          }
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final repo = QuranApiRepository(
      client: client,
      functionsBaseUrl: 'https://example.test/functions/v1/quran-yutla-api',
    );
    final results = await repo.searchQuran('الصبر');
    expect(results, hasLength(2));
    expect(results.any((r) => r.type == QuranSearchResultType.verseText), isTrue);
    expect(results.firstWhere((r) => r.verseKey == '103:1'), isNotNull);
    repo.dispose();
  });
}
