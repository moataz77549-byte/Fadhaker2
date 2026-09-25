import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/config/supabase_config.dart';
import '../../core/models/app_models.dart';

class SmartRadioException implements Exception {
  const SmartRadioException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class SmartRadioProgram {
  const SmartRadioProgram({
    required this.key,
    required this.title,
    required this.sourceType,
    required this.sourceId,
    required this.sourceName,
    required this.streamUrl,
    required this.refreshAfterSeconds,
    required this.transitionPolicy,
    this.fallbackUrl,
    this.bitrateKbps = 0,
    this.validUntil,
    this.override = false,
    this.fallbackMode = false,
  });

  final String key;
  final String title;
  final String sourceType;
  final String sourceId;
  final String sourceName;
  final String streamUrl;
  final String? fallbackUrl;
  final int bitrateKbps;
  final int refreshAfterSeconds;
  final String transitionPolicy;
  final String? validUntil;
  final bool override;
  final bool fallbackMode;

  factory SmartRadioProgram.fromJson(Map<String, dynamic> json) {
    final streamUrl = json['streamUrl']?.toString().trim() ?? '';
    if (!streamUrl.startsWith('https://')) {
      throw const SmartRadioException(
        'invalid_source',
        'مصدر الإذاعة الذكية غير صالح.',
      );
    }
    return SmartRadioProgram(
      key: json['key']?.toString() ?? 'smart',
      title: json['title']?.toString() ?? 'إذاعة فذكر الذكية',
      sourceType: json['sourceType']?.toString() ?? 'LIVE_STATION',
      sourceId: json['sourceId']?.toString() ?? '',
      sourceName: json['sourceName']?.toString() ?? 'تلاوة قرآنية',
      streamUrl: streamUrl,
      fallbackUrl: _nullable(json['fallbackUrl']),
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt() ?? 0,
      refreshAfterSeconds:
          ((json['refreshAfterSeconds'] as num?)?.toInt() ?? 900)
              .clamp(60, 7200)
              .toInt(),
      transitionPolicy:
          json['transitionPolicy']?.toString() ?? 'SOFT_DEADLINE',
      validUntil: _nullable(json['validUntil']),
      override: json['override'] == true,
      fallbackMode: json['fallbackMode'] == true,
    );
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class SmartRadioNext {
  const SmartRadioNext({required this.title, required this.startsAt});
  final String title;
  final String startsAt;

  factory SmartRadioNext.fromJson(Map<String, dynamic> json) => SmartRadioNext(
        title: json['title']?.toString() ?? '',
        startsAt: json['startsAt']?.toString() ?? '',
      );
}

class SmartRadioResolution {
  const SmartRadioResolution({
    required this.channelName,
    required this.channelSlug,
    required this.program,
    required this.timezone,
    required this.generatedAt,
    this.description,
    this.next,
    this.cachedFallback = false,
  });

  final String channelName;
  final String channelSlug;
  final String? description;
  final SmartRadioProgram program;
  final SmartRadioNext? next;
  final String timezone;
  final DateTime generatedAt;
  final bool cachedFallback;

  factory SmartRadioResolution.fromJson(
    Map<String, dynamic> json, {
    bool cachedFallback = false,
  }) {
    final channel = Map<String, dynamic>.from(json['channel'] as Map? ?? {});
    final program = Map<String, dynamic>.from(json['program'] as Map? ?? {});
    final nextRaw = json['next'];
    return SmartRadioResolution(
      channelName: channel['name']?.toString() ?? 'إذاعة فذكر الذكية',
      channelSlug: channel['slug']?.toString() ?? 'fadhkur-smart',
      description: channel['description']?.toString(),
      program: SmartRadioProgram.fromJson(program),
      next: nextRaw is Map
          ? SmartRadioNext.fromJson(Map<String, dynamic>.from(nextRaw))
          : null,
      timezone: json['timezone']?.toString() ?? '',
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      cachedFallback: cachedFallback,
    );
  }

  String get nowLabel => '${program.title} • ${program.sourceName}';
}

class SmartRadioService {
  SmartRadioService({
    http.Client? client,
    Future<SharedPreferences> Function()? prefsProvider,
  })  : _client = client ?? http.Client(),
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefsProvider;

  static const _cacheKey = 'fadhkur.smart_radio.resolution.v1';
  static bool _tzInitialized = false;

  static void _ensureTimezones() {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    _tzInitialized = true;
  }

  Future<SmartRadioResolution> resolve(
    PrayerTimesModel prayers, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!SupabaseConfig.isConfigured) {
      return _cachedOrThrow(
        const SmartRadioException(
          'not_configured',
          'خدمة إذاعة فذكر الذكية غير مهيأة في هذا الإصدار.',
        ),
      );
    }
    if (prayers.timezone.trim().isEmpty ||
        prayers.fajr.isEmpty ||
        prayers.dhuhr.isEmpty ||
        prayers.asr.isEmpty ||
        prayers.maghrib.isEmpty ||
        prayers.isha.isEmpty) {
      return _cachedOrThrow(
        const SmartRadioException(
          'prayer_context_missing',
          'تعذّر تحديد سياق مواقيت الصلاة للإذاعة الذكية.',
        ),
      );
    }

    final localNow = _nowIn(prayers.timezone);
    if (localNow == null) {
      return _cachedOrThrow(
        const SmartRadioException(
          'invalid_timezone',
          'تعذّر تحديد المنطقة الزمنية للإذاعة الذكية.',
        ),
      );
    }
    final localDateTime = _localIso(localNow);
    final uri = Uri.parse(
      '${SupabaseConfig.url}/functions/v1/smart-radio-resolve',
    );
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'apikey': SupabaseConfig.publishableKey,
              // Keep the public resolver compatible with Supabase gateways
              // that expect an Authorization bearer even when verify_jwt is
              // disabled for this read-only endpoint.
              'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'channel': 'fadhkur-smart',
              'timezone': prayers.timezone,
              'localDateTime': localDateTime,
              'instantUtc': DateTime.now().toUtc().toIso8601String(),
              'prayerTimes': {
                'fajr': prayers.fajr,
                'dhuhr': prayers.dhuhr,
                'asr': prayers.asr,
                'maghrib': prayers.maghrib,
                'isha': prayers.isha,
              },
            }),
          )
          .timeout(timeout);

      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = decoded['error'];
        final code = error is Map
            ? error['code']?.toString() ?? 'resolver_error'
            : 'resolver_error';
        throw SmartRadioException(
          code,
          'تعذّر تحديث برنامج إذاعة فذكر الذكية.',
        );
      }

      final resolution = SmartRadioResolution.fromJson(decoded);
      await _saveCache(decoded);
      return resolution;
    } on SmartRadioException catch (error) {
      return _cachedOrThrow(error);
    } on TimeoutException {
      return _cachedOrThrow(
        const SmartRadioException(
          'timeout',
          'استغرق تحديث الإذاعة الذكية وقتًا أطول من المتوقع.',
        ),
      );
    } catch (_) {
      return _cachedOrThrow(
        const SmartRadioException(
          'network',
          'تعذّر الاتصال بخدمة الإذاعة الذكية.',
        ),
      );
    }
  }

  Future<SmartRadioResolution> _cachedOrThrow(
    SmartRadioException original,
  ) async {
    final cached = await loadCached();
    if (cached != null) return cached;
    throw original;
  }

  Future<void> _saveCache(Map<String, dynamic> json) async {
    final prefs = await _prefsProvider();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'resolution': json,
      }),
    );
  }

  Future<SmartRadioResolution?> loadCached() async {
    try {
      final prefs = await _prefsProvider();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cached_at']?.toString() ?? '');
      if (cachedAt == null ||
          DateTime.now().toUtc().difference(cachedAt) >
              const Duration(minutes: 15)) {
        return null;
      }
      final resolution =
          Map<String, dynamic>.from(decoded['resolution'] as Map);
      // Program decisions are short-lived: never keep yesterday's source
      // or a long-expired rights/health decision in offline playback.
      return SmartRadioResolution.fromJson(
        resolution,
        cachedFallback: true,
      );
    } catch (_) {
      return null;
    }
  }

  tz.TZDateTime? _nowIn(String timezone) {
    _ensureTimezones();
    try {
      return tz.TZDateTime.now(tz.getLocation(timezone));
    } catch (_) {
      // Fail closed instead of pairing UTC wall time with a non-UTC IANA
      // timezone. The caller will use the cached/builtin continuity fallback.
      return null;
    }
  }

  static String _localIso(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}T'
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}

final smartRadioService = SmartRadioService();
