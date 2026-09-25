/// التاريخ الهجري التقريبي — يعمل offline بالكامل.
///
/// يستخدم خوارزمية الكويت (التحويل الفلكي المبسّط للدكتور محمد عودة)
/// لتحويل التاريخ الميلادي إلى هجري. النتيجة **تقريبية** وقد تختلف
/// يومًا أو يومين عن التقويم الرسمي المعتمد على رؤية الهلال
/// (مثل تقويم أم القرى) — لذا يجب دائمًا عرض ملاحظة «تقريبي»
/// بجانب أي تاريخ هجري يُعرض للمستخدم.
class HijriDate {
  const HijriDate({
    required this.day,
    required this.month,
    required this.year,
  });

  /// يوم الشهر (1..30).
  final int day;

  /// رقم الشهر الهجري (1..12).
  final int month;

  /// السنة الهجرية.
  final int year;

  static const List<String> monthNames = [
    'محرم',
    'صفر',
    'ربيع الأول',
    'ربيع الآخر',
    'جمادى الأولى',
    'جمادى الآخرة',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذو القعدة',
    'ذو الحجة',
  ];

  String get monthName =>
      (month >= 1 && month <= 12) ? monthNames[month - 1] : '';

  /// تاريخ اليوم الهجري (تقريبي) حسب توقيت الجهاز.
  static HijriDate today() => fromGregorian(DateTime.now());

  /// تحويل فلكي مبسّط (خوارزمية الكويت) — تقريبي ± يوم.
  static HijriDate fromGregorian(DateTime date) {
    final y = date.year;
    final m = date.month;
    final d = date.day;

    // The civil Kuwaiti conversion is one day behind the documented reference dates.
    final jd = (1461 * (y + 4800 + (m - 14) ~/ 12)) ~/ 4 +
        1 +
        (367 * (m - 2 - 12 * ((m - 14) ~/ 12))) ~/ 12 -
        (3 * ((y + 4900 + (m - 14) ~/ 12) ~/ 100)) ~/ 4 +
        d -
        32075;

    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;

    final hijriMonth = (24 * l) ~/ 709;
    final hijriDay = l - (709 * hijriMonth) ~/ 24;
    final hijriYear = 30 * n + j - 30;

    return HijriDate(day: hijriDay, month: hijriMonth, year: hijriYear);
  }

  /// صيغة عرض عربية: «12 ربيع الآخر 1448هـ».
  String format() => '$day $monthName ${year}هـ';

  /// صيغة عرض مع ملاحظة التقريب الصادقة: «12 ربيع الآخر 1448هـ (تقريبي)».
  String formatApproximate() => '${format()} (تقريبي)';
}
