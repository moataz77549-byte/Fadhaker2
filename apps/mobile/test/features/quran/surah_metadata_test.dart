import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/features/quran/data/surah_metadata.dart';

void main() {
  group('canonical Surah metadata', () {
    test('contains all 114 surahs in canonical order', () {
      expect(allSurahs.length, 114);
      expect(
        allSurahs.map((surah) => surah.number).toList(),
        List<int>.generate(114, (index) => index + 1),
      );
      expect(allSurahs.first.displayName, 'سورة الفاتحة');
      expect(allSurahs.last.displayName, 'سورة الناس');
    });

    test('has one valid Mushaf start page per surah', () {
      expect(surahStartPages.length, 114);
      expect(surahStartPages.first, 1);
      expect(surahStartPages.last, 604);
      expect(
        surahStartPages.every((page) => page >= 1 && page <= 604),
        isTrue,
      );
      for (var i = 1; i < surahStartPages.length; i++) {
        expect(surahStartPages[i], greaterThanOrEqualTo(surahStartPages[i - 1]));
      }
    });

    test('startPageForSurah is bounded and maps known surahs', () {
      expect(startPageForSurah(1), 1);
      expect(startPageForSurah(2), 2);
      expect(startPageForSurah(18), 293);
      expect(startPageForSurah(114), 604);
      expect(startPageForSurah(0), 1);
      expect(startPageForSurah(115), 1);
    });
  });
}
