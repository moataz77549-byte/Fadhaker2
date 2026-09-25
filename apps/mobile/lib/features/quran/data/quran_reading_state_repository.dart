import 'package:shared_preferences/shared_preferences.dart';

/// حالة القراءة وإعدادات المصحف — تُحفظ محليًا على الجهاز فقط.
enum QuranReadingMode { image, text }

class QuranReadingStateRepository {
  QuranReadingStateRepository({Future<SharedPreferences> Function()? prefsProvider})
      : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsProvider;

  static const _kRiwaya = 'quran.riwaya_id';
  static const _kMushafEdition = 'quran.mushaf_edition_id';
  static const _kFont = 'quran.font_id';
  static const _kFontSize = 'quran.font_size';
  static const _kMode = 'quran.reading_mode';
  static const _kTafsir = 'quran.tafsir_source_id';

  static String _lastPageKey(String riwayaId) => 'quran.last_page.$riwayaId';

  Future<String> riwayaId() async => (await _prefsProvider()).getString(_kRiwaya) ?? 'hafs';
  Future<void> saveRiwayaId(String id) async => (await _prefsProvider()).setString(_kRiwaya, id);

  /// إصدار المصحف المصوّر المختار (hafs-madani | hafs-madani-tajweed).
  Future<String> mushafEditionId() async =>
      (await _prefsProvider()).getString(_kMushafEdition) ?? 'hafs-madani';
  Future<void> saveMushafEditionId(String id) async =>
      (await _prefsProvider()).setString(_kMushafEdition, id);

  Future<String> fontId() async => (await _prefsProvider()).getString(_kFont) ?? 'uthmanic-hafs';
  Future<void> saveFontId(String id) async => (await _prefsProvider()).setString(_kFont, id);

  Future<double> fontSize() async => (await _prefsProvider()).getDouble(_kFontSize) ?? 22.0;
  Future<void> saveFontSize(double size) async =>
      (await _prefsProvider()).setDouble(_kFontSize, size.clamp(16.0, 40.0));

  Future<QuranReadingMode> readingMode() async {
    final raw = (await _prefsProvider()).getString(_kMode);
    return raw == 'text' ? QuranReadingMode.text : QuranReadingMode.image;
  }

  Future<void> saveReadingMode(QuranReadingMode mode) async =>
      (await _prefsProvider()).setString(_kMode, mode == QuranReadingMode.text ? 'text' : 'image');

  Future<int> tafsirSourceId() async => (await _prefsProvider()).getInt(_kTafsir) ?? 16;
  Future<void> saveTafsirSourceId(int id) async => (await _prefsProvider()).setInt(_kTafsir, id);

  /// آخر صفحة لكل رواية على حدة (تخطيط الصفحات يختلف بين الروايات).
  Future<int?> lastPage(String riwayaId) async {
    final page = (await _prefsProvider()).getInt(_lastPageKey(riwayaId));
    return (page == null || page < 1) ? null : page;
  }

  Future<void> saveLastPage(String riwayaId, int page) async =>
      (await _prefsProvider()).setInt(_lastPageKey(riwayaId), page);
}
