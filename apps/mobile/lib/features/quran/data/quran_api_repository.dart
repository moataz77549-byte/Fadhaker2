import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/supabase_config.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_navigation.dart';
import '../domain/riwaya.dart';
import '../domain/tafsir_source.dart';
import 'quran_public_text_source.dart';

/// بوابة Flutter إلى محتوى القرآن عبر Supabase Edge Function.
///
/// القاعدة الأمنية: لا أسرار في Flutter أبدًا. هذا المستودع ينادي
/// الـ Edge Function فقط، وهي التي تملك OAuth2 Client Credentials
/// الخاصة بـ Quran Foundation في أسرارها.
/// لا يُرسل أي ترويسة سرّية من هنا (يُتحقق من ذلك في الاختبارات).
///
/// Offline-first: عند تعذّر الـ Edge Function يُستخدم
/// [QuranPublicTextSource] (مصدران عامّان بلا مفاتيح: خريطة الصفحات
/// من api.quran.com ونص حفص العثماني من fawazahmed0 عبر jsDelivr)
/// مع تخزين السور على القرص. التفسير وحده يبقى معتمدًا على الـ Backend
/// (لا مصدر عام موثّق) مع رسالة صادقة بدل الشاشة الميتة.
class QuranApiRepository {
  QuranApiRepository(
      {http.Client? client, String? functionsBaseUrl, QuranPublicTextSource? publicSource})
      : _client = client ?? http.Client(),
        _functionsBase = functionsBaseUrl ?? '${SupabaseConfig.url}/functions/v1/quran-yutla-api',
        _publicSource = publicSource;

  final http.Client _client;
  final String _functionsBase;
  final QuranPublicTextSource? _publicSource;
  QuranPublicTextSource? _publicCache;

  QuranPublicTextSource get _public => _publicCache ??= _publicSource ?? QuranPublicTextSource();

  Map<String, String> get _headers => {
        if (SupabaseConfig.publishableKey.isNotEmpty) 'apikey': SupabaseConfig.publishableKey,
        'Accept': 'application/json',
      };

  /// نص صفحة من المصحف (وضع النص) لرواية معيّنة.
  ///
  /// الـ Edge Function أولًا؛ عند فشلها يُستخدم المصدر العام المباشر
  /// (حفص فقط — الروايات الأخرى بلا مصدر نص عام موثّق).
  Future<MushafPage> getPageText({required Riwaya riwaya, required int page}) async {
    if (!riwaya.textAvailable) {
      throw StateError('نص الرواية «${riwaya.nameAr}» غير متوفّر بعد');
    }
    QuranNavigation.validateTextPage(page);
    try {
      final uri = Uri.parse('$_functionsBase/quran/page').replace(
        queryParameters: {'riwaya': riwaya.id, 'page': '$page'},
      );
      final json = await _getJson(uri);
      final verses = json['verses'] as List<dynamic>? ?? const [];
      if (verses.isEmpty) throw StateError('لم تصل بيانات الصفحة $page');
      final surahName = json['surahName'] as String? ?? 'المصحف الشريف';
      return MushafPage.fromApi(page, json, surahName, riwayaId: riwaya.id);
    } catch (_) {
      if (riwaya.id != 'hafs') rethrow;
      return _public.pageText(page);
    }
  }

  /// تفسير آية واحدة من مصدر معيّن (المصدر يُحدَّد بمعرّف Quran Foundation).
  ///
  /// التفسير backend-only: لا يوجد مصدر عام موثّق لنصوص التفاسير،
  /// فعند تعذّر الـ Edge Function تُرمى رسالة صادقة تعرضها الواجهة
  /// مع زر إعادة المحاولة (ممنوع أي نص تفسير مُختلَق).
  Future<TafsirEntry> getTafsir({required TafsirSource source, required String ayahKey}) async {
    final parsed = QuranNavigation.parseAyahKey(ayahKey);
    try {
      final uri = Uri.parse(
        '$_functionsBase/quran/tafsir/${source.resourceId}/ayah/${parsed.chapter}/${parsed.verse}',
      );
      final json = await _getJson(uri);
      final entry = TafsirEntry.fromQuranFoundation(
        resourceId: source.resourceId,
        ayahKey: ayahKey,
        sourceNameAr: source.nameAr,
        json: json,
      );
      if (entry.htmlText.isEmpty) {
        // الخادم أجاب لكن بلا محتوى — حالة صادقة تُعرض كما هي.
        throw _EmptyTafsirException();
      }
      return entry;
    } on _EmptyTafsirException {
      throw StateError('لا يوجد تفسير لهذه الآية في «${source.nameAr}»');
    } catch (_) {
      throw StateError(
          'تعذّر جلب التفسير من الخادم — تحقق من الاتصال وحاول مجددًا');
    }
  }

  /// فهرس التفاسير المتاحة: الـ Backend أولًا، ثم القائمة المضمّنة
  /// الموثّقة (معرّفات Quran Foundation الحقيقية) عند تعذّره.
  Future<List<TafsirSource>> tafsirCatalog() async {
    try {
      final json = await _getJson(Uri.parse('$_functionsBase/quran/tafsirs'));
      final list = TafsirSourceRegistry.parseList(json['tafsirs']);
      if (list.isEmpty) throw StateError('تعذّر جلب فهرس التفاسير');
      return list;
    } catch (_) {
      return TafsirSourceRegistry.builtin;
    }
  }

  /// رقم الصفحة التي تقع فيها آية معيّنة (للانتقال للسورة/الآية).
  /// الـ Edge Function أولًا؛ عند فشلها المصدر العام المباشر.
  Future<int> lookupPage({required int chapter, required int verse}) async {
    QuranNavigation.parseAyahKey('$chapter:$verse');
    try {
      final uri = Uri.parse('$_functionsBase/quran/lookup').replace(
        queryParameters: {'chapter': '$chapter', 'verse': '$verse'},
      );
      final json = await _getJson(uri);
      final page = (json['page'] as num?)?.toInt();
      if (page == null) throw StateError('تعذّر تحديد صفحة الآية $chapter:$verse');
      return QuranNavigation.validateTextPage(page);
    } catch (_) {
      return _public.lookupPage(chapter: chapter, verse: verse);
    }
  }

  /// Interpretive topic index. Quran text remains exclusively in the page API.
  Future<Map<String, dynamic>> topicCatalog() =>
      _getJson(Uri.parse('$_functionsBase/quran/topics'));

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode == 503) {
      throw StateError('خدمة القرآن غير مهيأة على الخادم بعد');
    }
    if (response.statusCode != 200) {
      final message = _errorMessage(response.body);
      throw StateError(message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String _errorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? 'تعذّر جلب البيانات';
    } catch (_) {
      return 'تعذّر جلب البيانات';
    }
  }

  void dispose() {
    _client.close();
    if (_publicSource == null) _publicCache?.dispose();
  }
}

/// علَم داخلي لتمييز «الخادم أجاب بلا محتوى» عن فشل الشبكة.
class _EmptyTafsirException implements Exception {
  const _EmptyTafsirException();
}
