import 'dart:convert';

import 'package:fadhkur_mobile/features/quran/data/quranpedia_topic_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses Quranpedia topic hierarchy and verse keys from Edge proxy',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/quran/topics'));
      return http.Response(
        jsonEncode({
          'topics': [
            {
              'id': 2860,
              'name': 'أسماء الله الحسنى',
              'parent_id': null,
              'ayahs': '7:180,17:110,20:8,59:24',
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = QuranpediaTopicProvider(
      client: client,
      functionsBaseUrl: 'https://example.test/functions/v1/quran-yutla-api',
    );
    final records = await provider.fetchAllTopics();
    expect(records.single.topic.id, 2860);
    expect(records.single.topic.titleAr, 'أسماء الله الحسنى');
    expect(records.single.verseKeys, ['7:180', '17:110', '20:8', '59:24']);
    provider.dispose();
  });

  test('delta endpoint controls whether full topic sync is needed', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/quran/topics/changes'));
      expect(request.url.queryParameters['since'], '2026-09-01');
      return http.Response(
        jsonEncode({'changed': false, 'count': 0}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final provider = QuranpediaTopicProvider(
      client: client,
      functionsBaseUrl: 'https://example.test/functions/v1/quran-yutla-api',
    );
    expect(
      await provider.hasUpdatesSince(DateTime.utc(2026, 9, 1)),
      isFalse,
    );
    provider.dispose();
  });
}
