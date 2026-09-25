import 'package:fadhkur_mobile/features/daily_hadith/data/forty_nawawi.dart';
import 'package:fadhkur_mobile/features/daily_hadith/data/daily_hadith_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyHadithRepository', () {
    final repository = DailyHadithRepository();

    test('الأربعون النووية: 40 حديثًا بنصوص ورواة', () {
      expect(fortyNawawi.length, 40);
      for (final hadith in fortyNawawi) {
        expect(hadith.text.trim(), isNotEmpty);
        expect(hadith.narrator.trim(), isNotEmpty);
        expect(hadith.grade.trim(), isNotEmpty);
      }
    });

    test('حديث اليوم ثابت خلال نفس اليوم', () {
      final day = DateTime(2026, 9, 23);
      final a = repository.hadithForDate(day);
      final b = repository.hadithForDate(day);
      expect(a.title, b.title);
      expect(a.text, b.text);
    });

    test('الدورة تدور على الأربعين حديثًا ولا تخرج عنها', () {
      final seen = <String>{};
      for (var i = 0; i < 80; i++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: i));
        final hadith = repository.hadithForDate(day);
        expect(fortyNawawi, contains(hadith));
        seen.add(hadith.title);
      }
      // 80 يومًا تغطي دورتين كاملتين.
      expect(seen.length, 40);
    });

    test('يومان متتاليان يعطيان حديثين مختلفين', () {
      final first = repository.hadithForDate(DateTime(2026, 1, 1));
      final second = repository.hadithForDate(DateTime(2026, 1, 2));
      expect(second.title, isNot(first.title));
    });
  });
}
