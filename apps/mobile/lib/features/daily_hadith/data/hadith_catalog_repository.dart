import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

class CatalogHadith {
  const CatalogHadith({required this.id, required this.title,
    required this.text, required this.reference, required this.sourceUrl,
    this.grade, this.attribution, this.explanation, this.benefits});
  final String id, title, text, reference, sourceUrl;
  final String? grade, attribution, explanation, benefits;

  factory CatalogHadith.fromJson(Map<String, dynamic> row) => CatalogHadith(
    id: '${row['id']}', title: '${row['title'] ?? ''}',
    text: '${row['hadith_text'] ?? ''}',
    reference: '${row['reference'] ?? ''}',
    sourceUrl: '${row['source_url'] ?? ''}',
    grade: row['grade']?.toString(),
    attribution: row['attribution']?.toString(),
    explanation: row['explanation']?.toString(),
    benefits: row['benefits']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'hadith_text': text, 'reference': reference,
    'source_url': sourceUrl, 'grade': grade, 'attribution': attribution,
    'explanation': explanation, 'benefits': benefits,
  };
}

class HadithCatalogRepository {
  HadithCatalogRepository({SupabaseClient? client,
    Future<SharedPreferences> Function()? prefsProvider})
      : _client = client, _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;
  final SupabaseClient? _client;
  final Future<SharedPreferences> Function() _prefsProvider;
  static const pageSize = 20;
  static const _cacheKey = 'hadith.catalog.v1';

  Future<List<CatalogHadith>> page({String query = '', int offset = 0}) async {
    if (offset < 0 || offset > 3000) return const [];
    final prefs = await _prefsProvider();
    try {
      if (_client == null && !SupabaseConfig.isConfigured) throw StateError('configuration');
      final rows = await (_client ?? Supabase.instance.client).schema('app').rpc(
        'search_hadiths', params: {
          'p_query': query.trim(), 'p_limit': pageSize, 'p_offset': offset,
        });
      final list = (rows as List).whereType<Map>()
          .map((r) => CatalogHadith.fromJson(Map<String, dynamic>.from(r)))
          .where((h) => h.text.isNotEmpty && h.reference.isNotEmpty &&
              h.sourceUrl.startsWith('https://hadeethenc.com/'))
          .toList(growable: false);
      if (query.trim().isEmpty && offset == 0) {
        await prefs.setString(_cacheKey, jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'items': list.map((h) => h.toJson()).toList(),
        }));
      }
      return list;
    } catch (_) {
      if (query.trim().isNotEmpty || offset != 0) rethrow;
      final raw = prefs.getString(_cacheKey);
      if (raw == null) rethrow;
      try {
        final cache = jsonDecode(raw) as Map<String, dynamic>;
        if (DateTime.now().millisecondsSinceEpoch - (cache['savedAt'] as int) >
            const Duration(days: 7).inMilliseconds) rethrow;
        return (cache['items'] as List)
            .map((r) => CatalogHadith.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList(growable: false);
      } catch (_) { rethrow; }
    }
  }
}
