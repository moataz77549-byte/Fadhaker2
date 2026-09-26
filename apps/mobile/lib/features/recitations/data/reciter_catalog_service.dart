import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/supabase_config.dart';
import '../../../core/models/app_models.dart';
import '../../listen/data/listen_metadata_store.dart';

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
  });
  final int surahNumber;
  final String audioUrl;
  final String quality;
}

class ReciterCatalogService {
  ReciterCatalogService({
    http.Client? client,
    String? baseUrl,
    String? publishableKey,
    ListenMetadataStore? cache,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? SupabaseConfig.url,
        _publishableKey = publishableKey ?? SupabaseConfig.publishableKey,
        _cache = cache ?? listenMetadataStore;

  final http.Client _client;
  final String _baseUrl;
  final String _publishableKey;
  final ListenMetadataStore _cache;
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
    return rows
        .map(_toReciter)
        .where((r) => r.id.isNotEmpty && r.nameAr.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<ReciterTrack>> loadTracks(String reciterId, {bool forceRefresh = false}) async {
    if (reciterId.isEmpty) return const [];
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

  void dispose() => _client.close();
}

final reciterCatalogService = ReciterCatalogService();

final recitersProvider = FutureProvider<List<ReciterModel>>((ref) {
  return reciterCatalogService.load();
});

final reciterTracksProvider =
    FutureProvider.family<List<ReciterTrack>, String>((ref, reciterId) {
  return reciterCatalogService.loadTracks(reciterId);
});
