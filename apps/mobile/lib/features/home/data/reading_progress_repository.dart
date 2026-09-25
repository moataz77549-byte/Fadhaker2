import 'package:shared_preferences/shared_preferences.dart';

/// آخر موضع قراءة حفظه المستخدم في المصحف.
///
/// يُحفظ محليًا على الجهاز فقط (لا يُرسل لأي خادم)، ويُستخدم لعرض
/// بطاقة «وردك اليومي» في الشاشة الرئيسية ببيانات فعلية بدل القيم الثابتة.
///
/// ملاحظة بنيوية: التطبيق لا يملك نظام حسابات للمستخدمين (لا مصادقة)،
/// لذا لا توجد مزامنة عبر الأجهزة — الحفظ محلي بحت ويُستعاد بعد إعادة
/// تشغيل التطبيق من نفس الجهاز.
class ReadingProgress {
  const ReadingProgress({
    required this.page,
    this.surahNumber,
    this.ayahKey,
    this.surahName,
    this.riwayaId = 'hafs',
    required this.savedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? savedAt;

  /// رقم الصفحة (1..604).
  final int page;

  /// رقم السورة الظاهرة وقت الحفظ (قد يكون null في وضع الصور).
  final int? surahNumber;

  /// مفتاح أول آية في الصفحة بصيغة «chapter:verse» (قد يكون null).
  final String? ayahKey;

  /// اسم السورة الظاهرة في أعلى الصفحة وقت الحفظ (قد يكون null).
  final String? surahName;

  /// معرّف الرواية التي كان يقرأ بها المستخدم (حفص/ورش/قالون/الدوري).
  final String riwayaId;

  /// وقت أول حفظ.
  final DateTime savedAt;

  /// وقت آخر تحديث للموضع.
  final DateTime updatedAt;
}

class ReadingProgressRepository {
  static const _kPage = 'reading_progress.page';
  static const _kSurahNumber = 'reading_progress.surah_number';
  static const _kAyahKey = 'reading_progress.ayah_key';
  static const _kSurahName = 'reading_progress.surah_name';
  static const _kRiwayaId = 'reading_progress.riwaya_id';
  static const _kSavedAt = 'reading_progress.saved_at_ms';
  static const _kUpdatedAt = 'reading_progress.updated_at_ms';

  /// يقرأ آخر تقدّم محفوظ، أو null إذا لم يبدأ المستخدم القراءة بعد.
  /// متوافق مع النسخ القديمة التي كانت تحفظ الصفحة واسم السورة فقط.
  Future<ReadingProgress?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final page = prefs.getInt(_kPage);
    if (page == null || page < 1 || page > 604) return null;
    final savedAtMs = prefs.getInt(_kSavedAt);
    final updatedAtMs = prefs.getInt(_kUpdatedAt);
    return ReadingProgress(
      page: page,
      surahNumber: prefs.getInt(_kSurahNumber),
      ayahKey: prefs.getString(_kAyahKey),
      surahName: prefs.getString(_kSurahName),
      riwayaId: prefs.getString(_kRiwayaId) ?? 'hafs',
      savedAt: savedAtMs == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(savedAtMs),
      updatedAt: updatedAtMs == null
          ? (savedAtMs == null
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : DateTime.fromMillisecondsSinceEpoch(savedAtMs))
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  /// يحفظ الموضع الحالي مع بيانات السياق الكاملة. الحفظ best-effort
  /// ولا يرمي استثناءات للواجهة.
  Future<void> save({
    required int page,
    String? surahName,
    int? surahNumber,
    String? ayahKey,
    String riwayaId = 'hafs',
  }) async {
    if (page < 1 || page > 604) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final hadPrevious = prefs.getInt(_kPage) != null;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_kPage, page);
      if (surahName == null || surahName.isEmpty) {
        await prefs.remove(_kSurahName);
      } else {
        await prefs.setString(_kSurahName, surahName);
      }
      if (surahNumber == null || surahNumber < 1 || surahNumber > 114) {
        await prefs.remove(_kSurahNumber);
      } else {
        await prefs.setInt(_kSurahNumber, surahNumber);
      }
      if (ayahKey == null || ayahKey.isEmpty) {
        await prefs.remove(_kAyahKey);
      } else {
        await prefs.setString(_kAyahKey, ayahKey);
      }
      await prefs.setString(_kRiwayaId, riwayaId);
      if (!hadPrevious) {
        await prefs.setInt(_kSavedAt, nowMs);
      }
      await prefs.setInt(_kUpdatedAt, nowMs);
    } catch (_) {
      // تجاهل هادئ: تقدّم القراءة ميزة مساعدة وليست حرجة.
    }
  }

  /// يمسح التقدّم المحفوظ.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPage);
    await prefs.remove(_kSurahNumber);
    await prefs.remove(_kAyahKey);
    await prefs.remove(_kSurahName);
    await prefs.remove(_kRiwayaId);
    await prefs.remove(_kSavedAt);
    await prefs.remove(_kUpdatedAt);
  }
}
