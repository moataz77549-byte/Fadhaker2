import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/supabase_config.dart';
import '../../../core/models/app_models.dart';
import '../../listen/data/listen_metadata_store.dart';
import '../../listen/data/mp3quran_api.dart';
import '../../listen/data/audio_url_builder.dart';

enum ReciterCatalogFailure { configuration, network, permission, server, malformed }

class ReciterCatalogException implements Exception {
  const ReciterCatalogException(this.failure, {this.statusCode});
  final ReciterCatalogFailure failure;
  final int? statusCode;

  String get userMessage => switch (failure) {
        ReciterCatalogFailure.configuration =>
          'إعداد الاتصال بالخادم غير مكتمل في هذه النسخة. حدّث التطبيق.',
        ReciterCatalogFailure.network =>
          'تعذّر الاتصال بالإنترنت لتحميل القراء. حاول مجددًا عند عودة الاتصال.',
        ReciterCatalogFailure.permission =>
          'تعذّر الوصول إلى كتالوج القراء. حاول التحديث لاحقًا.',
        ReciterCatalogFailure.server =>
          'خدمة القراء غير متاحة مؤقتًا. حاول مجددًا.',
        ReciterCatalogFailure.malformed =>
          'وصلت بيانات قراء غير صالحة. حاول مجددًا لاحقًا.',
      };
}

class ReciterTrack {
  const ReciterTrack({
    required this.surahNumber,
    required this.audioUrl,
    required this.quality,
    this.moshafId = '',
    this.moshafName = '',
  });
  final int surahNumber;
  final String audioUrl;
  final String quality;
  final String moshafId;
  final String moshafName;
}

class ReciterCatalogService {
  ReciterCatalogService({
    http.Client? client,
    String? baseUrl,
    String? publishableKey,
    ListenMetadataStore? cache,
    Mp3QuranApi? mp3QuranApi,
    bool? useOfficialCatalog,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? SupabaseConfig.url,
        _publishableKey = publishableKey ?? SupabaseConfig.publishableKey,
        _cache = cache ?? listenMetadataStore,
        _mp3QuranApi = mp3QuranApi ?? Mp3QuranApi(),
        _officialOverride = useOfficialCatalog;

  final http.Client _client;
  final String _baseUrl;
  final String _publishableKey;
  final ListenMetadataStore _cache;
  final Mp3QuranApi _mp3QuranApi;
  final bool? _officialOverride;
  final Map<String, Map<String, dynamic>> _officialById = {};
  bool get _useOfficialCatalog => _officialOverride ?? (_baseUrl == SupabaseConfig.url);
  static const _catalogTtl = Duration(hours: 24);

  static const _select =
      'id,name_ar,default_riwayah,bio_arabic,metadata,is_featured';
  static const _trackSelect =
      'surah_id,audio_url,quality,bitrate_kbps,is_active';

  Future<List<ReciterModel>> load({bool forceRefresh = false}) async {
    final rows = await _cachedRows('reciters', 'all', {
      'select': _select,
      'is_active': 'eq.true',
      'deleted_at': 'is.null',
      'order': 'is_featured.desc,name_ar.asc',
    }, forceRefresh: forceRefresh);
    final curated = rows
        .map(_toReciter)
        .where((r) => r.id.isNotEmpty && r.nameAr.isNotEmpty)
        .toList(growable: false);
    if (!_useOfficialCatalog) return curated;
    try {
      final official = await _officialReciters(forceRefresh: forceRefresh);
      final canonical = {
        for (final reader in curated) _normalizeName(reader.nameAr): reader.id,
      };
      final result = <ReciterModel>[];
      final used = <String>{};
      _officialById.clear();
      for (final row in official) {
        final id = row['id']?.toString();
        final name = '${row['name'] ?? ''}'.trim();
        if (id == null || name.isEmpty) continue;
        final identity = _normalizeName(name);
        if (!used.add(identity)) continue;
        final canonicalId = canonical[identity] ?? 'mp3quran:$id';
        _officialById[canonicalId] = row;
        final moshafs = row['moshaf'] is List ? row['moshaf'] as List : const [];
        final available = <int>{};
        for (final moshaf in moshafs.whereType<Map>()) {
          available.addAll(AudioUrlBuilder.availableSurahs(moshaf['surah_list']?.toString()));
        }
        result.add(ReciterModel(
          id: canonicalId, nameAr: name,
          riwaya: moshafs.isNotEmpty && moshafs.first is Map
              ? '${(moshafs.first as Map)['name'] ?? 'التلاوات المتاحة'}'
              : 'التلاوات المتاحة',
          surahsCount: available.length,
          bio: '', provider: 'MP3Quran.net', audioQuality: 'MP3',
        ));
      }
      result.addAll(curated.where((reader) => !used.contains(_normalizeName(reader.nameAr))));
      return result;
    } catch (_) {
      return curated;
    }
  }

  String _normalizeName(String name) => name
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll(RegExp('ى'), 'ي')
      .replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<List<Map<String, dynamic>>> _officialReciters({required bool forceRefresh}) async {
    ({List<Map<String, dynamic>> rows, DateTime updatedAt})? cached;
    try { cached = await _cache.read('mp3quran', 'reciters'); } catch (_) {}
    if (!forceRefresh && cached != null &&
        DateTime.now().difference(cached.updatedAt) < _catalogTtl) return cached.rows;
    try {
      final rows = await _mp3QuranApi.reciters();
      try { await _cache.write('mp3quran', 'reciters', rows); } catch (_) {}
      return rows;
    } catch (_) {
      if (cached != null) return cached.rows;
      rethrow;
    }
  }

  Future<List<ReciterTrack>> loadTracks(String reciterId, {bool forceRefresh = false}) async {
    if (reciterId.isEmpty) return const [];
    final official = _officialById[reciterId];
    if (official != null) {
      final tracks = <ReciterTrack>[];
      final moshafs = official['moshaf'];
      if (moshafs is List) {
        for (final moshaf in moshafs.whereType<Map>()) {
          final available = AudioUrlBuilder.availableSurahs(moshaf['surah_list']?.toString());
          final server = '${moshaf['server'] ?? ''}';
          final moshafId = '${moshaf['id'] ?? ''}';
          final name = '${moshaf['name'] ?? 'مصحف صوتي'}';
          for (final surah in available.toList()..sort()) {
            final url = AudioUrlBuilder.forMp3Quran(server, surah, available);
            if (url == null) continue;
            tracks.add(ReciterTrack(surahNumber: surah, audioUrl: url.toString(),
                quality: name, moshafId: moshafId, moshafName: name));
          }
        }
      }
      return tracks;
    }
    final rows = await _cachedRows('reciter_tracks', reciterId, {
      'select': _trackSelect,
      'reciter_id': 'eq.$reciterId',
      'is_active': 'eq.true',
      'order': 'surah_id.asc',
    }, forceRefresh: forceRefresh);
    return rows.map((row) {
      return ReciterTrack(
        surahNumber: (row['surah_id'] as num?)?.toInt() ?? 0,
        audioUrl: '${row['audio_url'] ?? ''}',
        quality: '${row['quality'] ?? ''}',
      );
    }).where((t) => t.surahNumber > 0 && t.audioUrl.isNotEmpty).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _cachedRows(
      String dataset, String key, Map<String, String> params,
      {required bool forceRefresh}) async {
    ({List<Map<String, dynamic>> rows, DateTime updatedAt})? cached;
    try { cached = await _cache.read(dataset, key); } catch (_) {
      // SQLite is optional during widget tests and after storage failures.
    }
    if (!forceRefresh && cached != null &&
        DateTime.now().difference(cached.updatedAt) < _catalogTtl) {
      return cached.rows;
    }
    try {
      final rows = await _getRows(dataset, params);
      try { await _cache.write(dataset, key, rows); } catch (_) {}
      return rows;
    } on ReciterCatalogException catch (error) {
      // A missing build configuration or denied access must never be hidden
      // by old cached rows. Only network/server outages use the offline copy.
      if (cached != null && (error.failure == ReciterCatalogFailure.network ||
          error.failure == ReciterCatalogFailure.server)) return cached.rows;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _getRows(
      String table, Map<String, String> params) async {
    if (!_baseUrl.startsWith('https://') || _publishableKey.isEmpty) {
      throw const ReciterCatalogException(ReciterCatalogFailure.configuration);
    }
    final uri = Uri.parse('$_baseUrl/rest/v1/$table')
        .replace(queryParameters: params);
    late http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'apikey': _publishableKey,
        'Accept-Profile': 'app',
      }).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const ReciterCatalogException(ReciterCatalogFailure.network);
    } on SocketException {
      throw const ReciterCatalogException(ReciterCatalogFailure.network);
    } on http.ClientException {
      throw const ReciterCatalogException(ReciterCatalogFailure.network);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ReciterCatalogException(ReciterCatalogFailure.permission,
          statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReciterCatalogException(ReciterCatalogFailure.server,
          statusCode: response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const ReciterCatalogException(ReciterCatalogFailure.malformed);
      }
      return decoded.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } on FormatException {
      throw const ReciterCatalogException(ReciterCatalogFailure.malformed);
    } on TypeError {
      throw const ReciterCatalogException(ReciterCatalogFailure.malformed);
    }
  }

  ReciterModel _toReciter(Map<String, dynamic> row) {
    final metadata = row['metadata'] is Map
        ? Map<String, dynamic>.from(row['metadata'] as Map)
        : const <String, dynamic>{};
    final source = metadata['audioSource']?.toString() ?? 'كتالوج فذكر';
    return ReciterModel(
      id: '${row['id'] ?? ''}',
      nameAr: '${row['name_ar'] ?? ''}',
      riwaya: '${row['default_riwayah'] ?? row['rewaya'] ?? 'حفص عن عاصم'}',
      surahsCount: 114,
      bio: '${row['bio_arabic'] ?? row['description'] ?? ''}',
      provider: source,
      audioQuality: 'MP3 • كتالوج مركزي',
    );
  }

  void dispose() {
    _client.close();
    _mp3QuranApi.dispose();
  }
}

final reciterCatalogService = ReciterCatalogService();

final recitersProvider = FutureProvider<List<ReciterModel>>((ref) {
  return reciterCatalogService.load();
});

final reciterTracksProvider =
    FutureProvider.family<List<ReciterTrack>, String>((ref, reciterId) {
  return reciterCatalogService.loadTracks(reciterId);
});
