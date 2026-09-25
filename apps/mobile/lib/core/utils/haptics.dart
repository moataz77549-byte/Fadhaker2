import 'package:flutter/services.dart';

/// اهتزازات موحّدة للأفعال المهمة في التطبيق.
///
/// يستخدم [HapticFeedback] من `flutter/services` فقط — لا حاجة لأي إذن
/// إضافي في Android. كل الدوال best-effort ولا ترمي استثناءات.
class AppHaptics {
  AppHaptics._();

  /// نقرة خفيفة: تنقّل، اختيار عنصر، عدّ تسبيحة عادية.
  static Future<void> lightTap() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// تأكيد متوسط: حفظ، تبديل مفضلة، اختيار سرعة/مؤقت.
  static Future<void> confirm() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// إنجاز مهم: إتمام هدف تسبيح، إكمال جزء، تصفير عدّاد.
  static Future<void> milestone() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
