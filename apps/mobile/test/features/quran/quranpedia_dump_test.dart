import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fadhkur_mobile/features/quran/data/quranpedia_topic_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('verified topics dump maps verse keys and records its version', () async {
    final bytes = gzip.encode(utf8.encode(jsonEncode({
      'data': [
        {'id': 42, 'name': 'الصبر', 'parent_id': null, 'ayahs': '2:153,2:155'},
      ],
    })));
    final checksum = sha256.convert(bytes).toString();
    final provider = QuranpediaTopicProvider(client: MockClient((request) async {
      if (request.url.path.endsWith('/manifest.json')) {
        return http.Response(jsonEncode({
          'version': '2026-09-26',
          'files': [{'name': 'topics-index.json.gz', 'sha256': checksum, 'bytes': bytes.length}],
        }), 200);
      }
      if (request.url.path.endsWith('/topics-index.json.gz')) {
        return http.Response.bytes(bytes, 200);
      }
      return http.Response('Not found', 404);
    }));
    final records = await provider.fetchAllTopics();
    expect(records, hasLength(1));
    expect(records.first.topic.titleAr, 'الصبر');
    expect(records.first.verseKeys, ['2:153', '2:155']);
    expect(provider.sourceVersion, '2026-09-26:${checksum.substring(0, 12)}');
    provider.dispose();
  });
}
