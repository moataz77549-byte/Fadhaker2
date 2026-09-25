/// بيانات بنيوية لسور القرآن الكريم الـ 114 (offline).
///
/// الاسم وعدد الآيات ونوع النزول (مكي/مدني) حقائق قرآنية ثابتة،
/// وتُستخدم في شاشة القارئ لعرض التلاوات الكاملة بدل أي قائمة تجريبية.
class SurahMeta {
  const SurahMeta({
    required this.number,
    required this.name,
    required this.ayahs,
    required this.revelationType,
  });

  /// رقم السورة في المصحف (1..114).
  final int number;
  /// الاسم بدون «سورة».
  final String name;
  /// عدد الآيات.
  final int ayahs;
  /// «مكية» أو «مدنية».
  final String revelationType;

  /// الاسم الكامل للعرض.
  String get displayName => 'سورة $name';
}

/// السور الـ 114 مرتّبة حسب المصحف.
const List<SurahMeta> allSurahs = [
  SurahMeta(number: 1, name: 'الفاتحة', ayahs: 7, revelationType: 'مكية'),
  SurahMeta(number: 2, name: 'البقرة', ayahs: 286, revelationType: 'مدنية'),
  SurahMeta(number: 3, name: 'آل عمران', ayahs: 200, revelationType: 'مدنية'),
  SurahMeta(number: 4, name: 'النساء', ayahs: 176, revelationType: 'مدنية'),
  SurahMeta(number: 5, name: 'المائدة', ayahs: 120, revelationType: 'مدنية'),
  SurahMeta(number: 6, name: 'الأنعام', ayahs: 165, revelationType: 'مكية'),
  SurahMeta(number: 7, name: 'الأعراف', ayahs: 206, revelationType: 'مكية'),
  SurahMeta(number: 8, name: 'الأنفال', ayahs: 75, revelationType: 'مدنية'),
  SurahMeta(number: 9, name: 'التوبة', ayahs: 129, revelationType: 'مدنية'),
  SurahMeta(number: 10, name: 'يونس', ayahs: 109, revelationType: 'مكية'),
  SurahMeta(number: 11, name: 'هود', ayahs: 123, revelationType: 'مكية'),
  SurahMeta(number: 12, name: 'يوسف', ayahs: 111, revelationType: 'مكية'),
  SurahMeta(number: 13, name: 'الرعد', ayahs: 43, revelationType: 'مدنية'),
  SurahMeta(number: 14, name: 'إبراهيم', ayahs: 52, revelationType: 'مكية'),
  SurahMeta(number: 15, name: 'الحجر', ayahs: 99, revelationType: 'مكية'),
  SurahMeta(number: 16, name: 'النحل', ayahs: 128, revelationType: 'مكية'),
  SurahMeta(number: 17, name: 'الإسراء', ayahs: 111, revelationType: 'مكية'),
  SurahMeta(number: 18, name: 'الكهف', ayahs: 110, revelationType: 'مكية'),
  SurahMeta(number: 19, name: 'مريم', ayahs: 98, revelationType: 'مكية'),
  SurahMeta(number: 20, name: 'طه', ayahs: 135, revelationType: 'مكية'),
  SurahMeta(number: 21, name: 'الأنبياء', ayahs: 112, revelationType: 'مكية'),
  SurahMeta(number: 22, name: 'الحج', ayahs: 78, revelationType: 'مدنية'),
  SurahMeta(number: 23, name: 'المؤمنون', ayahs: 118, revelationType: 'مكية'),
  SurahMeta(number: 24, name: 'النور', ayahs: 64, revelationType: 'مدنية'),
  SurahMeta(number: 25, name: 'الفرقان', ayahs: 77, revelationType: 'مكية'),
  SurahMeta(number: 26, name: 'الشعراء', ayahs: 227, revelationType: 'مكية'),
  SurahMeta(number: 27, name: 'النمل', ayahs: 93, revelationType: 'مكية'),
  SurahMeta(number: 28, name: 'القصص', ayahs: 88, revelationType: 'مكية'),
  SurahMeta(number: 29, name: 'العنكبوت', ayahs: 69, revelationType: 'مكية'),
  SurahMeta(number: 30, name: 'الروم', ayahs: 60, revelationType: 'مكية'),
  SurahMeta(number: 31, name: 'لقمان', ayahs: 34, revelationType: 'مكية'),
  SurahMeta(number: 32, name: 'السجدة', ayahs: 30, revelationType: 'مكية'),
  SurahMeta(number: 33, name: 'الأحزاب', ayahs: 73, revelationType: 'مدنية'),
  SurahMeta(number: 34, name: 'سبأ', ayahs: 54, revelationType: 'مكية'),
  SurahMeta(number: 35, name: 'فاطر', ayahs: 45, revelationType: 'مكية'),
  SurahMeta(number: 36, name: 'يس', ayahs: 83, revelationType: 'مكية'),
  SurahMeta(number: 37, name: 'الصافات', ayahs: 182, revelationType: 'مكية'),
  SurahMeta(number: 38, name: 'ص', ayahs: 88, revelationType: 'مكية'),
  SurahMeta(number: 39, name: 'الزمر', ayahs: 75, revelationType: 'مكية'),
  SurahMeta(number: 40, name: 'غافر', ayahs: 85, revelationType: 'مكية'),
  SurahMeta(number: 41, name: 'فصلت', ayahs: 54, revelationType: 'مكية'),
  SurahMeta(number: 42, name: 'الشورى', ayahs: 53, revelationType: 'مكية'),
  SurahMeta(number: 43, name: 'الزخرف', ayahs: 89, revelationType: 'مكية'),
  SurahMeta(number: 44, name: 'الدخان', ayahs: 59, revelationType: 'مكية'),
  SurahMeta(number: 45, name: 'الجاثية', ayahs: 37, revelationType: 'مكية'),
  SurahMeta(number: 46, name: 'الأحقاف', ayahs: 35, revelationType: 'مكية'),
  SurahMeta(number: 47, name: 'محمد', ayahs: 38, revelationType: 'مدنية'),
  SurahMeta(number: 48, name: 'الفتح', ayahs: 29, revelationType: 'مدنية'),
  SurahMeta(number: 49, name: 'الحجرات', ayahs: 18, revelationType: 'مدنية'),
  SurahMeta(number: 50, name: 'ق', ayahs: 45, revelationType: 'مكية'),
  SurahMeta(number: 51, name: 'الذاريات', ayahs: 60, revelationType: 'مكية'),
  SurahMeta(number: 52, name: 'الطور', ayahs: 49, revelationType: 'مكية'),
  SurahMeta(number: 53, name: 'النجم', ayahs: 62, revelationType: 'مكية'),
  SurahMeta(number: 54, name: 'القمر', ayahs: 55, revelationType: 'مكية'),
  SurahMeta(number: 55, name: 'الرحمن', ayahs: 78, revelationType: 'مدنية'),
  SurahMeta(number: 56, name: 'الواقعة', ayahs: 96, revelationType: 'مكية'),
  SurahMeta(number: 57, name: 'الحديد', ayahs: 29, revelationType: 'مدنية'),
  SurahMeta(number: 58, name: 'المجادلة', ayahs: 22, revelationType: 'مدنية'),
  SurahMeta(number: 59, name: 'الحشر', ayahs: 24, revelationType: 'مدنية'),
  SurahMeta(number: 60, name: 'الممتحنة', ayahs: 13, revelationType: 'مدنية'),
  SurahMeta(number: 61, name: 'الصف', ayahs: 14, revelationType: 'مدنية'),
  SurahMeta(number: 62, name: 'الجمعة', ayahs: 11, revelationType: 'مدنية'),
  SurahMeta(number: 63, name: 'المنافقون', ayahs: 11, revelationType: 'مدنية'),
  SurahMeta(number: 64, name: 'التغابن', ayahs: 18, revelationType: 'مدنية'),
  SurahMeta(number: 65, name: 'الطلاق', ayahs: 12, revelationType: 'مدنية'),
  SurahMeta(number: 66, name: 'التحريم', ayahs: 12, revelationType: 'مدنية'),
  SurahMeta(number: 67, name: 'الملك', ayahs: 30, revelationType: 'مكية'),
  SurahMeta(number: 68, name: 'القلم', ayahs: 52, revelationType: 'مكية'),
  SurahMeta(number: 69, name: 'الحاقة', ayahs: 52, revelationType: 'مكية'),
  SurahMeta(number: 70, name: 'المعارج', ayahs: 44, revelationType: 'مكية'),
  SurahMeta(number: 71, name: 'نوح', ayahs: 28, revelationType: 'مكية'),
  SurahMeta(number: 72, name: 'الجن', ayahs: 28, revelationType: 'مكية'),
  SurahMeta(number: 73, name: 'المزمل', ayahs: 20, revelationType: 'مكية'),
  SurahMeta(number: 74, name: 'المدثر', ayahs: 56, revelationType: 'مكية'),
  SurahMeta(number: 75, name: 'القيامة', ayahs: 40, revelationType: 'مكية'),
  SurahMeta(number: 76, name: 'الإنسان', ayahs: 31, revelationType: 'مدنية'),
  SurahMeta(number: 77, name: 'المرسلات', ayahs: 50, revelationType: 'مكية'),
  SurahMeta(number: 78, name: 'النبأ', ayahs: 40, revelationType: 'مكية'),
  SurahMeta(number: 79, name: 'النازعات', ayahs: 46, revelationType: 'مكية'),
  SurahMeta(number: 80, name: 'عبس', ayahs: 42, revelationType: 'مكية'),
  SurahMeta(number: 81, name: 'التكوير', ayahs: 29, revelationType: 'مكية'),
  SurahMeta(number: 82, name: 'الانفطار', ayahs: 19, revelationType: 'مكية'),
  SurahMeta(number: 83, name: 'المطففين', ayahs: 36, revelationType: 'مكية'),
  SurahMeta(number: 84, name: 'الانشقاق', ayahs: 25, revelationType: 'مكية'),
  SurahMeta(number: 85, name: 'البروج', ayahs: 22, revelationType: 'مكية'),
  SurahMeta(number: 86, name: 'الطارق', ayahs: 17, revelationType: 'مكية'),
  SurahMeta(number: 87, name: 'الأعلى', ayahs: 19, revelationType: 'مكية'),
  SurahMeta(number: 88, name: 'الغاشية', ayahs: 26, revelationType: 'مكية'),
  SurahMeta(number: 89, name: 'الفجر', ayahs: 30, revelationType: 'مكية'),
  SurahMeta(number: 90, name: 'البلد', ayahs: 20, revelationType: 'مكية'),
  SurahMeta(number: 91, name: 'الشمس', ayahs: 15, revelationType: 'مكية'),
  SurahMeta(number: 92, name: 'الليل', ayahs: 21, revelationType: 'مكية'),
  SurahMeta(number: 93, name: 'الضحى', ayahs: 11, revelationType: 'مكية'),
  SurahMeta(number: 94, name: 'الشرح', ayahs: 8, revelationType: 'مكية'),
  SurahMeta(number: 95, name: 'التين', ayahs: 8, revelationType: 'مكية'),
  SurahMeta(number: 96, name: 'العلق', ayahs: 19, revelationType: 'مكية'),
  SurahMeta(number: 97, name: 'القدر', ayahs: 5, revelationType: 'مكية'),
  SurahMeta(number: 98, name: 'البينة', ayahs: 8, revelationType: 'مدنية'),
  SurahMeta(number: 99, name: 'الزلزلة', ayahs: 8, revelationType: 'مدنية'),
  SurahMeta(number: 100, name: 'العاديات', ayahs: 11, revelationType: 'مكية'),
  SurahMeta(number: 101, name: 'القارعة', ayahs: 11, revelationType: 'مكية'),
  SurahMeta(number: 102, name: 'التكاثر', ayahs: 8, revelationType: 'مكية'),
  SurahMeta(number: 103, name: 'العصر', ayahs: 3, revelationType: 'مكية'),
  SurahMeta(number: 104, name: 'الهمزة', ayahs: 9, revelationType: 'مكية'),
  SurahMeta(number: 105, name: 'الفيل', ayahs: 5, revelationType: 'مكية'),
  SurahMeta(number: 106, name: 'قريش', ayahs: 4, revelationType: 'مكية'),
  SurahMeta(number: 107, name: 'الماعون', ayahs: 7, revelationType: 'مكية'),
  SurahMeta(number: 108, name: 'الكوثر', ayahs: 3, revelationType: 'مكية'),
  SurahMeta(number: 109, name: 'الكافرون', ayahs: 6, revelationType: 'مكية'),
  SurahMeta(number: 110, name: 'النصر', ayahs: 3, revelationType: 'مدنية'),
  SurahMeta(number: 111, name: 'المسد', ayahs: 5, revelationType: 'مكية'),
  SurahMeta(number: 112, name: 'الإخلاص', ayahs: 4, revelationType: 'مكية'),
  SurahMeta(number: 113, name: 'الفلق', ayahs: 5, revelationType: 'مكية'),
  SurahMeta(number: 114, name: 'الناس', ayahs: 6, revelationType: 'مكية'),
];


/// صفحات بداية السور في مصحف المدينة (604 صفحات).
const List<int> surahStartPages = [
  1, 2, 50, 77, 106, 128, 151, 177, 187, 208,
  221, 235, 249, 255, 262, 267, 282, 293, 305, 312,
  322, 332, 342, 350, 359, 367, 377, 385, 396, 404,
  411, 415, 418, 428, 434, 440, 446, 453, 458, 467,
  477, 483, 489, 496, 499, 502, 507, 511, 515, 518,
  520, 523, 526, 528, 531, 534, 537, 542, 545, 549,
  552, 553, 554, 556, 558, 560, 562, 564, 566, 568,
  570, 572, 574, 575, 577, 578, 580, 582, 583, 585,
  586, 587, 587, 589, 590, 591, 592, 592, 593, 594,
  595, 595, 596, 596, 597, 597, 598, 598, 599, 599,
  600, 600, 601, 601, 601, 602, 602, 603, 603, 603,
  603, 604, 604, 604,
];

int startPageForSurah(int surahNumber) {
  if (surahNumber < 1 || surahNumber > surahStartPages.length) return 1;
  return surahStartPages[surahNumber - 1];
}
