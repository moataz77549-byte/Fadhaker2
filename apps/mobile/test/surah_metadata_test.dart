import 'package:fadhkur_mobile/features/quran/data/surah_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('allSurahs', () {
    test('114 سورة مرتّبة من 1 إلى 114', () {
      expect(allSurahs.length, 114);
      for (var i = 0; i < 114; i++) {
        expect(allSurahs[i].number, i + 1);
      }
    });

    test('كل سورة باسم وعدد آيات ونوع نزول صالح', () {
      for (final surah in allSurahs) {
        expect(surah.name.trim(), isNotEmpty);
        expect(surah.displayName, 'سورة ${surah.name}');
        expect(surah.ayahs, greaterThan(0));
        expect(surah.revelationType, anyOf('مكية', 'مدنية'));
      }
    });

    test('مجموع الآيات 6236', () {
      final total = allSurahs.fold<int>(0, (sum, s) => sum + s.ayahs);
      expect(total, 6236);
    });

    test('سور معروفة في مواضعها', () {
      expect(allSurahs[0].name, 'الفاتحة');
      expect(allSurahs[1].ayahs, 286);
      expect(allSurahs[17].name, 'الكهف');
      expect(allSurahs[113].name, 'الناس');
    });
  });
}
