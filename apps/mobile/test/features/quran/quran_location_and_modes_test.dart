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
}
