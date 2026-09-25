import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'forty_nawawi.dart';

/// مستودع حديث اليوم — تناوب يومي عبر الأربعين النووية.
///
/// يُختار حديث اليوم بالمعادلة `dayOfYear % 40` فيعمل offline بالكامل
/// دون أي شبكة أو تخزين. يعيد نفس الحديث طوال اليوم ويتبدّل منتصف الليل
/// حسب توقيت الجهاز.
class DailyHadithRepository {
  const DailyHadithRepository();

  /// حديث تاريخ معيّن (اليوم افتراضيًا).
  NawawiHadith hadithForDate(DateTime date) {
    final dayOfYear = _dayOfYear(date);
    final index = dayOfYear % fortyNawawi.length;
    return fortyNawawi[index];
  }

  /// حديث اليوم حسب توقيت الجهاز.
  NawawiHadith today() => hadithForDate(DateTime.now());

  /// رقم اليوم في السنة (1..366).
  static int _dayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return date.difference(startOfYear).inDays + 1;
  }
}

final dailyHadithRepositoryProvider = Provider<DailyHadithRepository>((ref) {
  return const DailyHadithRepository();
});

/// حديث اليوم — يُعاد حسابه تلقائيًا كل يوم.
final dailyHadithProvider = Provider<NawawiHadith>((ref) {
  return ref.watch(dailyHadithRepositoryProvider).today();
});
