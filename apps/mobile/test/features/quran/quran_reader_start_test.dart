import 'package:fadhkur_mobile/features/quran/domain/quran_location.dart';
import 'package:fadhkur_mobile/features/quran/domain/quran_reader_start.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const saved = QuranLocation(
    pageNumber: 42,
    surahNumber: 2,
    ayahNumber: 255,
    verseKey: '2:255',
  );

  test('explicit surah and bookmark destinations override older progress', () {
    final surah = QuranReaderStart.resolve(
      requestedPage: 604,
      savedLocation: saved,
    );
    expect(surah.pageNumber, 604);
    expect(surah.verseKey, isNull);

    final bookmark = QuranReaderStart.resolve(
      requestedPage: 2,
      requestedVerseKey: '2:1',
      savedLocation: saved,
    );
    expect(bookmark.pageNumber, 2);
    expect(bookmark.verseKey, '2:1');
  });

  test('ordinary opening and later mode changes restore the saved verse', () {
    final start = QuranReaderStart.resolve(savedLocation: saved);
    expect(start.pageNumber, 42);
    expect(start.verseKey, '2:255');
    expect(QuranReaderStart.resolve(savedLocation: saved).verseKey, start.verseKey);
  });

  test('legacy page progress stays available and page input is bounded', () {
    expect(QuranReaderStart.resolve(savedPage: 302).pageNumber, 302);
    expect(QuranReaderStart.resolve(requestedPage: 999).pageNumber, 604);
    expect(QuranReaderStart.resolve(requestedPage: 0).pageNumber, 1);
  });
}
