import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

class QuranTranslationEdition {
  const QuranTranslationEdition({required this.key, required this.title,
    required this.language, required this.version});
  final String key;
  final String title;
  final String language;
  final String version;
}

class QuranVerseTranslation {
  const QuranVerseTranslation({required this.text, required this.footnotes,
    required this.version, required this.sourceUrl});
  final String text;
  final String footnotes;
  final String version;
  final String sourceUrl;
}

class QuranTranslationRepository {
  QuranTranslationRepository({SupabaseClient? client,
    Future<SharedPreferences> Function()? prefsProvider})
      : _client = client, _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final SupabaseClient? _client;
  final Future<SharedPreferences> Function() _prefsProvider;
  static const _selectedKey = 'quran.translation.selected.v1';
  static const _catalogKey = 'quran.translation.catalog.v1';
  static const _cacheAge = Duration(days: 7);

  SupabaseClient get _db {
    if (_client != null) return _client;
    if (!SupabaseConfig.isConfigured) throw StateError('translation_configuration');
    return Supabase.instance.client;
  }

  Future<String?> selectedKey() async => (await _prefsProvider()).getString(_selectedKey);
  Future<void> select(String key) async => (await _prefsProvider()).setString(_selectedKey, key);

  Future<List<QuranTranslationEdition>> editions() async {
    final prefs = await _prefsProvider();
    try {
      // One representative verse per edition; this does not load 6236 rows.
      final rows = await _db.schema('app').from('quran_translations')
          .select('translation_key,title,language_code,source_version')
          .eq('surah_number', 1).eq('ayah_number', 1)
          .eq('is_active', true).limit(100);
      final list = rows.map((row) => QuranTranslationEdition(
        key: '${row['translation_key']}', title: '${row['title']}',
        language: '${row['language_code']}', version: '${row['source_version']}',
      )).toList(growable: false);
      await prefs.setString(_catalogKey, jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': list.map((e) => {'key': e.key, 'title': e.title,
          'language': e.language, 'version': e.version}).toList(),
      }));
      return list;
    } catch (_) {
      final raw = prefs.getString(_catalogKey);
      if (raw == null) rethrow;
      try {
        final cache = jsonDecode(raw) as Map<String, dynamic>;
        if (DateTime.now().millisecondsSinceEpoch - (cache['savedAt'] as int) >
            _cacheAge.inMilliseconds) rethrow;
        return (cache['items'] as List).map((item) {
          final row = item as Map<String, dynamic>;
          return QuranTranslationEdition(key: row['key'] as String,
              title: row['title'] as String, language: row['language'] as String,
              version: row['version'] as String);
        }).toList(growable: false);
      } catch (_) { rethrow; }
    }
  }

  Future<QuranVerseTranslation?> verse(String verseKey, String editionKey) async {
    if (!RegExp(r'^\d{1,3}:\d{1,3}$').hasMatch(verseKey) ||
        !RegExp(r'^[a-z0-9_]{3,80}$').hasMatch(editionKey)) return null;
    final prefs = await _prefsProvider();
    final cacheKey = 'quran.translation.v1.$editionKey.$verseKey';
    try {
      final rows = await _db.schema('app').from('quran_translations')
          .select('translation_text,footnotes,source_version,source_url')
          .eq('verse_key', verseKey).eq('translation_key', editionKey)
          .eq('is_active', true).limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final item = QuranVerseTranslation(text: '${row['translation_text']}',
        footnotes: '${row['footnotes'] ?? ''}',
        version: '${row['source_version']}', sourceUrl: '${row['source_url']}');
      await prefs.setString(cacheKey, jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'text': item.text, 'footnotes': item.footnotes,
        'version': item.version, 'sourceUrl': item.sourceUrl,
      }));
      return item;
    } catch (_) {
      final raw = prefs.getString(cacheKey);
      if (raw == null) rethrow;
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (DateTime.now().millisecondsSinceEpoch - (data['savedAt'] as int) >
            _cacheAge.inMilliseconds) rethrow;
        return QuranVerseTranslation(text: data['text'] as String,
          footnotes: data['footnotes'] as String, version: data['version'] as String,
          sourceUrl: data['sourceUrl'] as String);
      } catch (_) { rethrow; }
    }
  }
}
