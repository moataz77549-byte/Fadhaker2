import 'package:fadhkur_mobile/features/home/data/reading_progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingProgressRepository', () {
    late ReadingProgressRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = ReadingProgressRepository();
    });

    test('يرجع null عندما لا يوجد تقدّم محفوظ (empty state)', () async {
      expect(await repository.load(), isNull);
    });

    test('يحفظ ويسترجع الصفحة واسم السورة', () async {
      await repository.save(page: 293, surahName: 'سورة الكهف');

      final progress = await repository.load();
      expect(progress, isNotNull);
      expect(progress!.page, 293);
      expect(progress.surahName, 'سورة الكهف');
    });

    test('يحفظ الصفحة دون اسم سورة', () async {
      await repository.save(page: 12);

      final progress = await repository.load();
      expect(progress, isNotNull);
      expect(progress!.page, 12);
      expect(progress.surahName, isNull);
    });

    test('يرفض أرقام الصفحات خارج النطاق', () async {
      await repository.save(page: 0);
      expect(await repository.load(), isNull);

      await repository.save(page: 605);
      expect(await repository.load(), isNull);
    });

    test('الكتابة فوق تقدّم سابق تحدّث القيم', () async {
      await repository.save(page: 10, surahName: 'سورة الفاتحة');
      await repository.save(page: 20, surahName: 'سورة البقرة');

      final progress = await repository.load();
      expect(progress!.page, 20);
      expect(progress.surahName, 'سورة البقرة');
    });

    test('المسح يعيد الحالة الفارغة', () async {
      await repository.save(page: 100, surahName: 'سورة الكهف');
      await repository.clear();

      expect(await repository.load(), isNull);
    });

    test('يحفظ سياق القراءة الكامل: السورة والآية والرواية والطوابع', () async {
      await repository.save(
        page: 293,
        surahName: 'سورة الكهف',
        surahNumber: 18,
        ayahKey: '18:1',
        riwayaId: 'warsh',
      );

      final progress = await repository.load();
      expect(progress, isNotNull);
      expect(progress!.page, 293);
      expect(progress.surahNumber, 18);
      expect(progress.ayahKey, '18:1');
      expect(progress.surahName, 'سورة الكهف');
      expect(progress.riwayaId, 'warsh');
      expect(progress.updatedAt.millisecondsSinceEpoch, greaterThan(0));
    });

    test('التوافق مع الحفظ القديم: الرواية الافتراضية حفص', () async {
      SharedPreferences.setMockInitialValues({
        'reading_progress.page': 10,
        'reading_progress.surah_name': 'سورة الفاتحة',
      });
      repository = ReadingProgressRepository();

      final progress = await repository.load();
      expect(progress, isNotNull);
      expect(progress!.riwayaId, 'hafs');
      expect(progress.surahNumber, isNull);
      expect(progress.ayahKey, isNull);
    });

    test('updated_at يتحدث مع بقاء saved_at الأول', () async {
      await repository.save(page: 10, riwayaId: 'hafs');
      final first = await repository.load();
      await Future.delayed(const Duration(milliseconds: 5));
      await repository.save(page: 11, riwayaId: 'hafs');
      final second = await repository.load();

      expect(second!.page, 11);
      expect(second.savedAt.millisecondsSinceEpoch,
          first!.savedAt.millisecondsSinceEpoch);
      expect(second.updatedAt.millisecondsSinceEpoch,
          greaterThanOrEqualTo(second.savedAt.millisecondsSinceEpoch));
    });
  });
}
