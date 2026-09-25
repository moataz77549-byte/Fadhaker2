import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/supabase_config.dart';
import '../domain/mushaf_edition.dart';
import '../domain/quran_font.dart';
import '../domain/riwaya.dart';
import '../domain/tafsir_source.dart';

/// إعدادات القرآن القابلة للتغيير من الـ Backend.
///
/// تُجلب من `GET {functions}/quran-yutla-api/quran/config` وتُخزَّن محليًا،
/// وتشمل: سجل الروايات، إصدارات المصحف المصوّر، خيارات الخطوط، مصادر التفاسير.
/// لا تحتوي أي أسرار — الأسرار تبقى في Edge Function Secrets فقط.
///
/// عند تعذّر الـ Backend والكاش معًا يُستخدم [QuranRuntimeConfig.fallback]
/// المبني من السجلات المضمّنة الموثّقة — التطبيق يعمل من الصندوق دون باك-إند.
class QuranRuntimeConfig {
  const QuranRuntimeConfig({
    required this.riwayat,
    required this.editions,
    required this.fonts,
    required this.tafsirs,
    required this.fetchedAt,
  });

  final List<Riwaya> riwayat;

  /// إصدارات المصحف المصوّر (عادي/تجويد ملوّن) — تُدمج قيم الـ Backend
  /// فوق المضمّنة بنفس سياسة الروايات والخطوط.
  final List<MushafEdition> editions;
  final List<QuranFontOption> fonts;
  final List<TafsirSource> tafsirs;
  final DateTime fetchedAt;

  factory QuranRuntimeConfig.fromJson(Map<String, dynamic> json) {
    final riwayat = RiwayaRegistry.merge(
      RiwayaRegistry.parseList(json['riwayat']),
    );
    final editions = MushafEditionRegistry.merge(
      MushafEdition.parseList(json['editions']),
    );
    final fonts = QuranFontRegistry.merge(
      QuranFontRegistry.parseList(json['fonts']),
    );
    final tafsirs = TafsirSourceRegistry.merge(
      TafsirSourceRegistry.parseList(json['tafsirs']),
    );
    return QuranRuntimeConfig(
      riwayat: riwayat,
      editions: editions,
      fonts: fonts,
      tafsirs: tafsirs,
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'riwayat': riwayat.map((r) => r.toJson()).toList(),
        'editions': editions.map((e) => e.toJson()).toList(),
        'fonts': fonts.map((f) => f.toJson()).toList(),
        'tafsirs': tafsirs.map((t) => t.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  /// إعدادات احتياطية مضمّنة — تُستخدم عند غياب الـ Backend والكاش معًا.
  ///
  /// مبنية بالكامل من السجلات المضمّنة الموثّقة:
  /// - الروايات الأربع (حفص بنص وصور موثّقين، الباقي تعريف فقط)،
  /// - نسختا المصحف المدني (عادي + تجويد ملوّن — روابط QuranHub المحققة)،
  /// - الخطوط الأربعة (اثنان بروابط تحميل محققة)،
  /// - فهرس التفاسير الأربعة (المحتوى يُجلب من الـ Backend عند توفره).
  /// لا تُحفظ في الكاش حتى لا تحجب جلبًا حقيقيًا لاحقًا.
  factory QuranRuntimeConfig.fallback() => QuranRuntimeConfig(
        riwayat: RiwayaRegistry.builtin,
        editions: MushafEditionRegistry.builtin,
        fonts: QuranFontRegistry.builtin,
        tafsirs: TafsirSourceRegistry.builtin,
        fetchedAt: DateTime.now(),
      );

  /// هل هذه الإعدادات من الـ fallback المضمّن (لا من الـ Backend/الكاش)؟
  bool get isFallback => identical(riwayat, RiwayaRegistry.builtin);
}

class QuranConfigRepository {
  QuranConfigRepository({http.Client? client, String? functionsBaseUrl, Future<SharedPreferences> Function()? prefsProvider})
      : _client = client ?? http.Client(),
        _functionsBase = functionsBaseUrl ?? '${SupabaseConfig.url}/functions/v1/quran-yutla-api',
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final http.Client _client;
  final String _functionsBase;
  final Future<SharedPreferences> Function() _prefsProvider;

  static const _cacheKey = 'quran.runtime_config_json';
  static const _cacheTtl = Duration(hours: 24);

  Map<String, String> get _headers => {
        if (SupabaseConfig.publishableKey.isNotEmpty) 'apikey': SupabaseConfig.publishableKey,
        'Content-Type': 'application/json',
      };

  /// يجلب الإعدادات من الـ Backend مع تخزين مؤقت 24 ساعة.
  ///
  /// ترتيب السقوط: الكاش الصالح → الـ Backend → الكاش المنتهي →
  /// [QuranRuntimeConfig.fallback] المضمّن. لا يُرمى خطأ أبدًا عند
  /// أول تشغيل — شاشة المصحف تعمل من الصندوق دون باك-إند.
  Future<QuranRuntimeConfig> load({bool forceRefresh = false}) async {
    final prefs = await _prefsProvider();
    if (!forceRefresh) {
      final cached = _readCache(prefs);
      if (cached != null) return cached;
    }
    try {
      final response = await _client
          .get(Uri.parse('$_functionsBase/quran/config'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('تعذّر جلب إعدادات القرآن (${response.statusCode})');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final config = QuranRuntimeConfig.fromJson(json);
      await prefs.setString(_cacheKey, jsonEncode(config.toJson()));
      return config;
    } catch (_) {
      final cached = _readCache(prefs, ignoreTtl: true);
      if (cached != null) return cached;
      // Offline-first: لا بيانات وهمية ولا شاشة ميتة — الإعدادات المضمّنة.
      return QuranRuntimeConfig.fallback();
    }
  }

  QuranRuntimeConfig? _readCache(SharedPreferences prefs, {bool ignoreTtl = false}) {
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final config = QuranRuntimeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!ignoreTtl && DateTime.now().difference(config.fetchedAt) > _cacheTtl) return null;
      return config;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
