import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/quran_location.dart';

enum QuranReadingMode { madani, tajweed, thematic, text }

class QuranReadingStateRepository {
  QuranReadingStateRepository({
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsProvider;

  static const _kRiwaya = 'quran.riwaya_id';
  static const _kMushafEdition = 'quran.mushaf_edition_id';
  static const _kFont = 'quran.font_id';
  static const _kFontSize = 'quran.font_size';
  static const _kMode = 'quran.reading_mode';
  static const _kTafsir = 'quran.tafsir_source_id';
  static const _kShowTopicColors = 'quran.show_topic_colors';
  static const _kShowTajweedLegend = 'quran.show_tajweed_legend';
  static const _kPreferredReciter = 'quran.preferred_reciter';

  static String _lastPageKey(String riwayaId) => 'quran.last_page.$riwayaId';
  static String _lastLocationKey(String riwayaId) =>
      'quran.last_location.v2.$riwayaId';

  Future<String> riwayaId() async =>
      (await _prefsProvider()).getString(_kRiwaya) ?? 'hafs';

  Future<void> saveRiwayaId(String id) async =>
      (await _prefsProvider()).setString(_kRiwaya, id);

  Future<String> mushafEditionId() async =>
      (await _prefsProvider()).getString(_kMushafEdition) ?? 'hafs-madani';

  Future<void> saveMushafEditionId(String id) async =>
      (await _prefsProvider()).setString(_kMushafEdition, id);

  Future<String> fontId() async =>
      (await _prefsProvider()).getString(_kFont) ?? 'uthmanic-hafs';

  Future<void> saveFontId(String id) async =>
      (await _prefsProvider()).setString(_kFont, id);

  Future<double> fontSize() async =>
      (await _prefsProvider()).getDouble(_kFontSize) ?? 22.0;

  Future<void> saveFontSize(double size) async =>
      (await _prefsProvider()).setDouble(_kFontSize, size.clamp(16.0, 40.0));

  Future<QuranReadingMode> readingMode() async {
    final raw = (await _prefsProvider()).getString(_kMode);
    return switch (raw) {
      'tajweed' => QuranReadingMode.tajweed,
      'thematic' => QuranReadingMode.thematic,
      'text' => QuranReadingMode.text,
      // Migration from the previous two-mode selector.
      'image' || 'madani' || null => QuranReadingMode.madani,
      _ => QuranReadingMode.madani,
    };
  }

  Future<void> saveReadingMode(QuranReadingMode mode) async =>
      (await _prefsProvider()).setString(_kMode, mode.name);

  Future<int> tafsirSourceId() async =>
      (await _prefsProvider()).getInt(_kTafsir) ?? 16;

  Future<void> saveTafsirSourceId(int id) async =>
      (await _prefsProvider()).setInt(_kTafsir, id);

  Future<bool> showTopicColors() async =>
      (await _prefsProvider()).getBool(_kShowTopicColors) ?? true;

  Future<void> saveShowTopicColors(bool value) async =>
      (await _prefsProvider()).setBool(_kShowTopicColors, value);

  Future<bool> showTajweedLegend() async =>
      (await _prefsProvider()).getBool(_kShowTajweedLegend) ?? true;

  Future<void> saveShowTajweedLegend(bool value) async =>
      (await _prefsProvider()).setBool(_kShowTajweedLegend, value);

  Future<String?> preferredReciter() async =>
      (await _prefsProvider()).getString(_kPreferredReciter);

  Future<void> savePreferredReciter(String value) async =>
      (await _prefsProvider()).setString(_kPreferredReciter, value);

  Future<QuranLocation?> lastLocation(String riwayaId) async {
    final raw = (await _prefsProvider()).getString(_lastLocationKey(riwayaId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return QuranLocation.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastLocation(
    String riwayaId,
    QuranLocation location,
  ) async {
    final prefs = await _prefsProvider();
    await prefs.setString(
      _lastLocationKey(riwayaId),
      jsonEncode(location.toJson()),
    );
    // Keep the old page key updated for backwards compatibility and rollback.
    await prefs.setInt(_lastPageKey(riwayaId), location.pageNumber);
  }

  Future<int?> lastPage(String riwayaId) async {
    final location = await lastLocation(riwayaId);
    if (location != null) return location.pageNumber;
    final page = (await _prefsProvider()).getInt(_lastPageKey(riwayaId));
    return (page == null || page < 1) ? null : page;
  }

  Future<void> saveLastPage(String riwayaId, int page) async =>
      (await _prefsProvider()).setInt(_lastPageKey(riwayaId), page);
}
