import 'package:fadhkur_mobile/features/khatma/data/khatma_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KhatmaRepository', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('جدول الأجزاء: 30 جزءًا ببدايات صحيحة', () {
      expect(KhatmaRepository.juzStartPages.length, 30);
      expect(KhatmaRepository.juzStartPages.first, 1);
      expect(KhatmaRepository.juzStartPages[1], 22);
      expect(KhatmaRepository.juzStartPages.last, 582);
      // تصاعدي صارم وداخل 1..604
      for (var i = 1; i < 30; i++) {
        expect(KhatmaRepository.juzStartPages[i],
            greaterThan(KhatmaRepository.juzStartPages[i - 1]));
      }
    });

    test('juzForPage يشتق الجزء من الصفحة', () {
      expect(KhatmaRepository.juzForPage(1), 1);
      expect(KhatmaRepository.juzForPage(21), 1);
      expect(KhatmaRepository.juzForPage(22), 2);
      expect(KhatmaRepository.juzForPage(293), 15);
      expect(KhatmaRepository.juzForPage(322), 17);
      expect(KhatmaRepository.juzForPage(582), 30);
      expect(KhatmaRepository.juzForPage(604), 30);
    });

    test('juzPageCount يجمع 604 صفحات', () {
      var total = 0;
      for (var juz = 1; juz <= 30; juz++) {
        total += KhatmaRepository.juzPageCount(juz);
      }
      expect(total, 604);
    });

    test('حالة أولية صادقة: لا إكمال ولا تقدّم', () async {
      final state = await KhatmaRepository().load();
      expect(state.completedJuz, isEmpty);
      expect(state.progress, 0.0);
      expect(state.savedPage, isNull);
      expect(state.currentJuz, 1);
      expect(state.isComplete, isFalse);
    });

    test('تبديل إكمال جزء يحسب النسبة ويحفظها', () async {
      final repo = KhatmaRepository();
      var state = await repo.toggleJuzComplete(1);
      expect(state.completedJuz, {1});
      expect(state.progressPercent, 3); // 1/30 ≈ 3.33%

      state = await repo.toggleJuzComplete(2);
      expect(state.completedCount, 2);

      // إلغاء الإكمال
      state = await repo.toggleJuzComplete(1);
      expect(state.completedJuz, {2});

      // الاستمرارية عبر مثيل جديد (نفس SharedPreferences)
      final reloaded = await KhatmaRepository().load();
      expect(reloaded.completedJuz, {2});
    });

    test('الجزء الحالي يُشتق من موضع القراءة المحفوظ', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reading_progress.page', 293);
      await prefs.setInt(
          'reading_progress.saved_at_ms', DateTime.now().millisecondsSinceEpoch);

      final state = await KhatmaRepository().load();
      expect(state.savedPage, 293);
      expect(state.currentJuz, 15);
    });
  });
}
