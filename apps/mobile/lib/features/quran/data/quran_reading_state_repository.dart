import 'package:shared_preferences/shared_preferences.dart';

/// حالة القراءة وإعدادات المصحف — تُحفظ محليًا على الجهاز فقط.
enum QuranReadingMode { image, tajweed, thematic, text }

/// Stable verse identity across page layouts and display modes.
class QuranLocation {
  const QuranLocation({required this.page, this.verseKey});
  final int page;
  final String? verseKey;
}

class QuranReadingStateRepository {
  QuranReadingStateRepository({Future<SharedPreferences> Function()? prefsProvider})
      : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsProvider;

  static const _kRiwaya = 'quran.riwaya_id';
  static const _kMushafEdition = 'quran.mushaf_edition_id';
  static const _kFont = 'quran.font_id';
  static const _kFontSize = 'quran.font_size';
  static const _kMode = 'quran.reading_mode';
  static const _kVerseKey = 'quran.last_verse_key';
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
    return QuranReadingMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => QuranReadingMode.image,
    );
  }

  Future<void> saveReadingMode(QuranReadingMode mode) async =>
      (await _prefsProvider()).setString(_kMode, mode.name);

  Future<QuranLocation?> lastLocation(String riwayaId) async {
    final prefs = await _prefsProvider();
    final page = prefs.getInt(_lastPageKey(riwayaId));
    if (page == null || page < 1 || page > 604) return null;
    final key = prefs.getString('$_kVerseKey.$riwayaId');
    return QuranLocation(page: page, verseKey: key);
  }

  Future<void> saveLocation(String riwayaId, QuranLocation location) async {
    final prefs = await _prefsProvider();
    await prefs.setInt(_lastPageKey(riwayaId), location.page);
    if (location.verseKey != null) {
      await prefs.setString('$_kVerseKey.$riwayaId', location.verseKey!);
    }
  }

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
