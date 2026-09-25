import 'package:fadhkur_mobile/features/tasbih/data/tasbih_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TasbihRepository', () {
    late TasbihRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = TasbihRepository();
    });

    test('يحمّل العدّادات المسبقة الستة افتراضيًا', () async {
      final counters = await repository.loadCounters();
      expect(counters.length, 6);
      expect(counters.every((c) => !c.isCustom), isTrue);
      expect(counters.first.name, 'سبحان الله');
      expect(counters.first.target, 33);
    });

    test('الزيادة والحفظ والاسترجاع', () async {
      final id = (await repository.loadCounters()).first.id;
      final updated = await repository.increment(id);
      expect(updated.count, 1);

      final reloaded = await repository.loadCounters();
      expect(reloaded.firstWhere((c) => c.id == id).count, 1);
    });

    test('التصفير يبقي الاسم والهدف', () async {
      final id = (await repository.loadCounters()).first.id;
      await repository.increment(id);
      final reset = await repository.reset(id);
      expect(reset.count, 0);
      expect(reset.name, 'سبحان الله');
      expect(reset.target, 33);
    });

    test('إنشاء عدّاد مخصص وحذفه', () async {
      final custom = await repository.createCustom(
        name: 'الصلاة على النبي',
        target: 100,
      );
      expect(custom.isCustom, isTrue);
      expect(custom.count, 0);

      var counters = await repository.loadCounters();
      expect(counters.length, 7);
      expect(counters.any((c) => c.id == custom.id), isTrue);

      await repository.deleteCustom(custom.id);
      counters = await repository.loadCounters();
      expect(counters.length, 6);
      expect(counters.any((c) => c.id == custom.id), isFalse);
    });

    test('cycleProgress و cycleCount للهدف 33', () async {
      final id = (await repository.loadCounters()).first.id;
      for (var i = 0; i < 34; i++) {
        await repository.increment(id);
      }
      final counter =
          (await repository.loadCounters()).firstWhere((c) => c.id == id);
      expect(counter.count, 34);
      expect(counter.cycleCount, 1);
      expect(counter.cycleProgress, closeTo(1 / 33, 0.0001));
    });
  });
}
