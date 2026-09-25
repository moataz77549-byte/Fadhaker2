import 'package:fadhkur_mobile/core/utils/hijri_date.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات التاريخ الهجري التقريبي (خوارزمية الكويت).
///
/// الخوارزمية فلكية تقريبية — قد تختلف يومًا أو يومين عن التقويم
/// الرسمي المبني على رؤية الهلال، لذا تُقبل التواريخ المرجعية
/// بهامش ±2 يوم.
void main() {
  group('HijriDate.fromGregorian', () {
    test('أسماء الشهور 12 اسمًا صحيحًا', () {
      expect(HijriDate.monthNames.length, 12);
      expect(HijriDate.monthNames.first, 'محرم');
      expect(HijriDate.monthNames[8], 'رمضان');
      expect(HijriDate.monthNames.last, 'ذو الحجة');
    });

    test('تواريخ مرجعية بهامش ±2 يوم (تقويم أم القرى/الرؤية)', () {
      // 1 محرم 1447هـ = 26 يونيو 2025م (إعلان رسمي).
      // الخوارزمية تقريبية: قد تعطي 29/30 ذو الحجة 1446 بدل 1 محرم —
      // التسامح يُقاس بالأيام لا بتطابق السنة/الشهر عند حدود الشهور.
      final muharram1447 = HijriDate.fromGregorian(DateTime(2025, 6, 26));
      final nearMuharram1447 = (muharram1447.year == 1446 &&
              muharram1447.month == 12 &&
              muharram1447.day >= 28) ||
          (muharram1447.year == 1447 &&
              muharram1447.month == 1 &&
              muharram1447.day <= 3);
      expect(
        nearMuharram1447,
        isTrue,
        reason: 'حصلنا على ${muharram1447.day}/${muharram1447.month}/${muharram1447.year}',
      );

      // 1 رمضان 1446هـ = 1 مارس 2025م (إعلان رسمي).
      final ramadan1446 = HijriDate.fromGregorian(DateTime(2025, 3, 1));
      expect(ramadan1446.year, 1446);
      expect(ramadan1446.month, 9);
      expect((ramadan1446.day - 1).abs(), lessThanOrEqualTo(2));
    });

    test('صيغة العرض العربية مع ملاحظة التقريب', () {
      const date = HijriDate(day: 12, month: 4, year: 1448);
      expect(date.monthName, 'ربيع الآخر');
      expect(date.format(), '12 ربيع الآخر 1448هـ');
      expect(date.formatApproximate(), '12 ربيع الآخر 1448هـ (تقريبي)');
    });

    test('today() يعيد تاريخًا صالحًا', () {
      final today = HijriDate.today();
      expect(today.day, inInclusiveRange(1, 30));
      expect(today.month, inInclusiveRange(1, 12));
      expect(today.year, greaterThan(1440));
    });
  });
}
