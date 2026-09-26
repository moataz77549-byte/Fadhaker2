import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  String _sourceVersion = 'live-api-v1';

  @override
  String get sourceVersion => _sourceVersion;

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
    try {
      return await _fetchVerifiedDump();
    } catch (_) {
      // The legacy API remains available if the official dump is unreachable.
      _sourceVersion = 'live-api-v1';
    }
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

  static const _manifestUrl = 'https://api.quranpedia.net/dumps/manifest.json';
  static const _dumpUrl = 'https://api.quranpedia.net/dumps/topics-index.json.gz';

  Future<({String version, String checksum, int bytes})> _manifest() async {
    final response = await _client.get(Uri.parse(_manifestUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('Quranpedia manifest unavailable');
    }
    final manifest = jsonDecode(utf8.decode(response.bodyBytes));
    if (manifest is! Map || manifest['files'] is! List) {
      throw const FormatException('Invalid Quranpedia manifest');
    }
    final matching = (manifest['files'] as List).whereType<Map>()
        .where((file) => file['name'] == 'topics-index.json.gz').toList();
    if (matching.length != 1) throw const FormatException('Topics dataset missing');
    final file = matching.single;
    final version = manifest['version']?.toString() ?? '';
    final checksum = file['sha256']?.toString() ?? '';
    final size = (file['bytes'] as num?)?.toInt() ?? 0;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(version) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
        size < 50 || size > 1024 * 1024) {
      throw const FormatException('Invalid topics dataset metadata');
    }
    return (version: version, checksum: checksum, bytes: size);
  }

  @override
  Future<String?> currentVersion() async {
    try {
      final manifest = await _manifest();
      return '${manifest.version}:${manifest.checksum.substring(0, 12)}';
    } catch (_) {
      return null;
    }
  }

  Future<List<QuranTopicRecord>> _fetchVerifiedDump() async {
    // If the manifest changes during a transfer, try once with its new hash.
    for (var attempt = 0; attempt < 2; attempt++) {
      final manifest = await _manifest();
      final response = await _client.get(Uri.parse(_dumpUrl))
          .timeout(const Duration(seconds: 35));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 || bytes.length > 1024 * 1024) {
        throw const FormatException('Topics download failed');
      }
      if (bytes.length != manifest.bytes ||
          sha256.convert(bytes).toString() != manifest.checksum) {
        if (attempt == 0) continue;
        throw const FormatException('Topics checksum mismatch');
      }
      final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)));
      if (decoded is! Map || decoded['data'] is! List) {
        throw const FormatException('Invalid topics dataset');
      }
      final records = _parseRecords(decoded['data']);
      if (records.isEmpty) throw const FormatException('Empty topics dataset');
      _sourceVersion = '${manifest.version}:${manifest.checksum.substring(0, 12)}';
      return records;
    }
    throw const FormatException('Topics dataset changed while downloading');
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
