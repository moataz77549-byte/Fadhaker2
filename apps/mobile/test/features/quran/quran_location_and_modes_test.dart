import 'package:fadhkur_mobile/features/quran/data/quran_reading_state_repository.dart';
import 'package:fadhkur_mobile/features/quran/domain/quran_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('QuranLocation JSON round-trip keeps page and verse key', () {
    const location = QuranLocation(
      pageNumber: 42,
      surahNumber: 2,
      ayahNumber: 255,
      verseKey: '2:255',
      wordOffset: 3,
    );
    final restored = QuranLocation.fromJson(location.toJson());
    expect(restored, location);
    expect(restored.surahNumber, 2);
    expect(restored.ayahNumber, 255);
  });

  test('old image/text preference migrates to four-mode selector', () async {
    SharedPreferences.setMockInitialValues({'quran.reading_mode': 'image'});
    final repo = QuranReadingStateRepository();
    expect(await repo.readingMode(), QuranReadingMode.madani);

    SharedPreferences.setMockInitialValues({'quran.reading_mode': 'text'});
    final repo2 = QuranReadingStateRepository();
    expect(await repo2.readingMode(), QuranReadingMode.text);
  });

  test('last QuranLocation also updates rollback-compatible lastPage', () async {
    final repo = QuranReadingStateRepository();
    const location = QuranLocation(
      pageNumber: 42,
      surahNumber: 2,
      ayahNumber: 255,
      verseKey: '2:255',
    );
    await repo.saveLastLocation('hafs', location);
    expect(await repo.lastLocation('hafs'), location);
    expect(await repo.lastPage('hafs'), 42);
  });

  test('all four modes persist independently of QuranLocation', () async {
    final repo = QuranReadingStateRepository();
    for (final mode in QuranReadingMode.values) {
      await repo.saveReadingMode(mode);
      expect(await repo.readingMode(), mode);
    }
  });

  test('topic colors and tajweed legend preferences persist', () async {
    final repo = QuranReadingStateRepository();
    expect(await repo.showTopicColors(), isTrue);
    expect(await repo.showTajweedLegend(), isTrue);
    await repo.saveShowTopicColors(false);
    await repo.saveShowTajweedLegend(false);
    expect(await QuranReadingStateRepository().showTopicColors(), isFalse);
    expect(await QuranReadingStateRepository().showTajweedLegend(), isFalse);
  });

  test('Madani → Tajweed → Thematic → Text → Madani keeps one QuranLocation',
      () async {
    final repo = QuranReadingStateRepository();
    const location = QuranLocation(
      pageNumber: 42,
      surahNumber: 2,
      ayahNumber: 255,
      verseKey: '2:255',
    );
    await repo.saveLastLocation('hafs', location);

    for (final mode in const [
      QuranReadingMode.madani,
      QuranReadingMode.tajweed,
      QuranReadingMode.thematic,
      QuranReadingMode.text,
      QuranReadingMode.madani,
    ]) {
      await repo.saveReadingMode(mode);
      expect(await repo.lastLocation('hafs'), location);
    }
  });

  test('Quran page boundaries remain valid for 1, 2, middle and 604', () {
    for (final page in const [1, 2, 302, 604]) {
      final location = QuranLocation(
        pageNumber: page,
        surahNumber: page == 604 ? 114 : 1,
        ayahNumber: 1,
        verseKey: page == 604 ? '114:1' : '1:1',
      );
      expect(QuranLocation.fromJson(location.toJson()).pageNumber, page);
    }
  });

}
