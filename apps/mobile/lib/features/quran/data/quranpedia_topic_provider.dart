import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/supabase_config.dart';
import '../domain/quran_topic.dart';
import 'quran_topic_provider.dart';

class QuranpediaTopicProvider implements QuranTopicProvider {
  QuranpediaTopicProvider({http.Client? client, String? functionsBaseUrl})
      : _client = client ?? http.Client(),
        _functionsBase = functionsBaseUrl ??
            '${SupabaseConfig.url}/functions/v1/quran-yutla-api';

  final http.Client _client;
  final String _functionsBase;

  @override
  String get sourceName => 'Quranpedia — الموسوعة القرآنية';

  @override
  String get sourceVersion => 'live-api-v1';

  @override
  String get attribution => 'الموضوعات: Quranpedia.net';

  @override
  String get licenseReference => 'https://quranpedia.net/api-docs#usage-policy';

  Map<String, String> get _headers => {
        if (SupabaseConfig.publishableKey.isNotEmpty)
          'apikey': SupabaseConfig.publishableKey,
        'Accept': 'application/json',
      };

  @override
  Future<List<QuranTopicRecord>> fetchAllTopics() async {
    final response = await _client
        .get(Uri.parse('$_functionsBase/quran/topics'), headers: _headers)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('تعذّر مزامنة موضوعات القرآن');
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map<String, dynamic>
        ? decoded['topics']
        : decoded;
    return _parseRecords(raw);
  }

  @override
  Future<bool> hasUpdatesSince(DateTime since) async {
    final date = since.toUtc().toIso8601String().split('T').first;
    final uri = Uri.parse('$_functionsBase/quran/topics/changes')
        .replace(queryParameters: {'since': date});
    final response =
        await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return true;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return true;
    return decoded['changed'] == true;
  }

  @override
  Future<List<QuranTopicRecord>> searchTopics(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final uri = Uri.parse('$_functionsBase/quran/topics/search')
        .replace(queryParameters: {'q': normalized});
    final response =
        await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map<String, dynamic> ? decoded['topics'] : decoded;
    return _parseRecords(raw);
  }

  List<QuranTopicRecord> _parseRecords(dynamic raw) {
    if (raw is! List) return const [];
    final result = <QuranTopicRecord>[];
    for (final item in raw.whereType<Map>()) {
      final json = Map<String, dynamic>.from(item);
      final id = (json['id'] as num?)?.toInt();
      final name = (json['name'] ?? '').toString().trim();
      if (id == null || name.isEmpty) continue;
      final ayahsRaw = (json['ayahs'] ?? '').toString();
      final verseKeys = ayahsRaw
          .split(',')
          .map((e) => e.trim())
          .where((e) => RegExp(r'^\d{1,3}:\d{1,3}$').hasMatch(e))
          .toList(growable: false);
      result.add(
        QuranTopicRecord(
          topic: QuranTopic(
            id: id,
            titleAr: name,
            parentTopicId: (json['parent_id'] as num?)?.toInt(),
            source: 'quranpedia',
            sourceReference: 'https://quranpedia.net/topics/$id',
          ),
          verseKeys: verseKeys,
        ),
      );
    }
    return result;
  }

  void dispose() => _client.close();
}
