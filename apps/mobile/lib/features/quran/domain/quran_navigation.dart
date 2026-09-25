import 'riwaya.dart';

/// منطق التنقل في المصحف: مفاتيح الآيات، نطاقات الصفحات، وربط الفهارس.
///
/// كل الدوال خالصة (pure) وقابلة للاختبار دون أي اعتماد على الشبكة.
class QuranNavigation {
  const QuranNavigation._();

  /// يتحقق من مفتاح آية بصيغة «chapter:verse» مثل «18:1».
  /// يرمي [FormatException] عند الصيغة الخاطئة و[RangeError] خارج النطاق.
  static ({int chapter, int verse}) parseAyahKey(String key) {
    final parts = key.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('صيغة مفتاح الآية غير صحيحة: $key (المتوقع chapter:verse)');
    }
    final chapter = int.tryParse(parts[0]);
    final verse = int.tryParse(parts[1]);
    if (chapter == null || verse == null) {
      throw FormatException('مفتاح الآية يجب أن يكون رقمين: $key');
    }
    if (chapter < 1 || chapter > 114) {
      throw RangeError.range(chapter, 1, 114, 'chapter');
    }
    final maxVerse = _maxVerses[chapter - 1];
    if (verse < 1 || verse > maxVerse) {
      throw RangeError.range(verse, 1, maxVersesFor(chapter), 'verse');
    }
    return (chapter: chapter, verse: verse);
  }

  /// عدد آيات السورة (بيانات بنيوية ثابتة وموثّقة).
  static int maxVersesFor(int chapter) {
    if (chapter < 1 || chapter > 114) {
      throw RangeError.range(chapter, 1, 114, 'chapter');
    }
    return _maxVerses[chapter - 1];
  }

  /// يتحقق من رقم صفحة ضمن رواية معيّنة.
  /// إذا كان عدد صفحات الرواية غير موثّق (null) رُفضت صفحات وضع الصور
  /// لأن التخطيط غير معروف — يُستخدم [validateTextPage] لوضع النص.
  static int validateImagePage(Riwaya riwaya, int page) {
    final total = riwaya.totalPages;
    if (total == null) {
      throw StateError('تخطيط صفحات الرواية «${riwaya.nameAr}» غير موثّق بعد');
    }
    if (page < 1 || page > total) {
      throw RangeError.range(page, 1, total, 'page');
    }
    return page;
  }

  /// نطاق صفحات وضع النص (نص حفص العثماني عبر Quran Foundation = 604).
  static const int quranFoundationTextPages = 604;

  static int validateTextPage(int page) {
    if (page < 1 || page > quranFoundationTextPages) {
      throw RangeError.range(page, 1, quranFoundationTextPages, 'page');
    }
    return page;
  }

  /// في PageView.builder مع reverse: true (ترتيب RTL):
  /// الصفحة رقم N تقابل الفهرس N-1.
  static int pageToIndex(int page) => page - 1;
  static int indexToPage(int index) => index + 1;

  /// عدد آيات السور الـ 114 بالترتيب.
  static const List<int> _maxVerses = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99,
    128, 111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
    34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35,
    38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11,
    11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40,
    46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8,
    8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
  ];
}
