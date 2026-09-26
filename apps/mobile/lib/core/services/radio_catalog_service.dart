import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/supabase_config.dart';
import '../../features/radio/radio_station.dart';
import '../../features/listen/data/mp3quran_api.dart';

/// كتالوج محطات الإذاعة — Offline-first.
///
/// - تُجلب المحطات **الإنتاجية** المفعّلة من Supabase (جدول app.stations:
///   `is_active` و`is_playable` وسياسة RLS للمصدر) مرتبةً حسب sort_order.
/// - تُدمج بعدها [builtinRadioStations] المضمّنة والموثّقة (بلا تكرار
///   حسب رابط البث) — فتظهر محطات الإدارة أولًا ثم الافتراضية.
/// - عند تعذّر الشبكة: الكاش المحلي، ثم المضمّنة وحدها — القائمة
///   لا تعود فارغة أبدًا في أول تشغيل.
/// - أي تغيير في قاعدة البيانات ينعكس دون تحديث إجباري.
///
/// ملاحظة: just_audio (المعتمدة أصلًا) تدعم MP3 وAAC وبثوث Icecast/Shoutcast
/// عبر HTTP مباشرة، فيُمرَّر stream_url كما هو للمشغّل.
class RadioCatalogService {
  RadioCatalogService({
    http.Client? client,
    Future<SharedPreferences> Function()? prefsProvider,
    String? baseUrl,
    String? publishableKey,
    Mp3QuranApi? mp3QuranApi,
  })  : _client = client ?? http.Client(),
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _baseUrl = baseUrl ?? SupabaseConfig.url,
        _publishableKey = publishableKey ?? SupabaseConfig.publishableKey,
        _mp3QuranApi = mp3QuranApi ?? Mp3QuranApi();

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefsProvider;
  final String _baseUrl;
  final String _publishableKey;
  final Mp3QuranApi _mp3QuranApi;

  static const _cacheKey = 'fadhkur.radio_catalog.v2';
  static const _table = 'stations';
  static const _cacheSavedAtKey = 'fadhkur.radio_catalog.saved_at.v2';
  static const _cacheTtl = Duration(days: 7);

  static const _select =
      'id,name_ar,name_en,stream_url,fallback_stream_url,logo_url,'
      'stream_type,station_source,is_active,is_featured,sort_order,metadata,'
      'external_key,source_url,'
      'categories(slug)';

  Future<List<RadioStation>> load({Duration timeout = const Duration(seconds: 8)}) async {
    try {
      final remote = await _fetchRemote(timeout: timeout);
      // نتيجة فارغة من قاعدة البيانات صحيحة وليست خطأ؛ نحفظها خامًا حتى لا
      // يبقى التطبيق يعرض محطة قديمة من الكاش، ثم ندمج مع المضمّنة للعرض.
      await _saveCache(remote);
      return _mergeWithBuiltin(remote);
    } catch (_) {
      // السقوط إلى الكاش المحلي ثم المحطات المضمّنة عند فشل الشبكة/الطلب.
    }
    return _mergeWithBuiltin(await _loadCache());
  }

  /// تحديث قسري من الشبكة متجاوزًا الكاش (للسحب للتحديث).
  /// يرمي عند فشل الشبكة — الواجهة تعرض خطأً صادقًا مع زر إعادة.
  Future<List<RadioStation>> refresh({Duration timeout = const Duration(seconds: 10)}) async {
    final remote = await _fetchRemote(timeout: timeout);
    await _saveCache(remote);
    return _mergeWithBuiltin(remote);
  }

  /// Resolve a station again after playback failure. A removed station is
  /// not resurrected from stale cache; callers may try its approved fallback.
  Future<RadioStation?> refreshStation(String id) async {
    List<RadioStation> remote;
    try {
      remote = await _fetchRemote(timeout: const Duration(seconds: 8));
      await _saveCache(remote);
    } catch (_) {
      // The official MP3Quran API may still work when Supabase is unavailable.
      remote = await _loadCache();
    }
    for (final station in _mergeWithBuiltin(remote)) {
      if (station.id != id) continue;
      if (station.sourceUrl != '${Mp3QuranApi.baseUrl}/radios?language=ar' ||
          station.externalKey == null) return station;
      try {
        final radios = await _mp3QuranApi.radios();
        for (final row in radios) {
          if ('${row['id']}' != station.externalKey) continue;
          final url = Uri.tryParse('${row['url'] ?? ''}'.trim());
          if (url == null || url.scheme != 'https') return station;
          return RadioStation(
            id: station.id, nameAr: station.nameAr, streamUrl: url.toString(),
            fallbackUrl: station.fallbackUrl, bitrateKbps: station.bitrateKbps,
            isFeatured: station.isFeatured, nameEn: station.nameEn,
            logoUrl: station.logoUrl, streamType: station.streamType,
            kind: station.kind, sortOrder: station.sortOrder,
            externalKey: station.externalKey, sourceUrl: station.sourceUrl,
          );
        }
      } catch (_) { /* Supabase URL remains the bounded retry candidate. */ }
      return station;
    }
    return null;
  }

  /// محطات الإدارة الإنتاجية أولًا، ثم المضمّنة بلا تكرار (حسب رابط البث).
  static List<RadioStation> _mergeWithBuiltin(List<RadioStation> remote) {
    final seen = <String>{};
    final merged = <RadioStation>[];
    for (final s in [...remote, ...builtinRadioStations]) {
      final key = s.streamUrl.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      merged.add(s);
    }
    return merged;
  }

  Future<List<RadioStation>> _fetchRemote({required Duration timeout}) async {
    if (!_baseUrl.startsWith('https://') || _publishableKey.isEmpty) {
      throw StateError('Supabase is not configured');
    }
    final params = {
      'select': _select,
      'is_active': 'eq.true',
      // RLS decides which stations/providers have approved public access.
      'is_playable': 'eq.true',
      'deleted_at': 'is.null',
      'order': 'sort_order.asc,name_ar.asc',
    };
    final uri = Uri.parse('$_baseUrl/rest/v1/$_table')
        .replace(queryParameters: params);
    final response = await _client.get(uri, headers: {
      'apikey': _publishableKey,
      // الجداول في سكيمة app (مكشوفة في PostgREST عبر config.toml).
      'Accept-Profile': 'app',
    }).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Radio catalog request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('Invalid radio catalog');
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(RadioStation.fromSupabase)
        .where((s) => s.streamUrl.isNotEmpty)
        .toList();
  }

  Future<void> _saveCache(List<RadioStation> stations) async {
    final prefs = await _prefsProvider();
    await prefs.setString(
      _cacheKey,
      jsonEncode(stations.map((s) => s.toJson()).toList()),
    );
    await prefs.setInt(_cacheSavedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<List<RadioStation>> _loadCache() async {
    final prefs = await _prefsProvider();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return const [];
    final savedAt = prefs.getInt(_cacheSavedAtKey);
    // Older installations have no timestamp. Keep one-time offline access,
    // while fresh responses always carry a bounded age.
    if (savedAt != null &&
        DateTime.now().millisecondsSinceEpoch - savedAt > _cacheTtl.inMilliseconds) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(RadioStation.fromJson)
          .where((s) => s.streamUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _client.close();
    _mp3QuranApi.dispose();
  }
}

final radioCatalogService = RadioCatalogService();
