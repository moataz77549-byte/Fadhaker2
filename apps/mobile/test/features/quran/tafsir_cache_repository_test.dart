import 'package:fadhkur_mobile/features/quran/data/tafsir_cache_repository.dart';
import 'package:fadhkur_mobile/features/quran/domain/tafsir_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// ملاحظة: لا تُستخدم أي نصوص تفسير حقيقية هنا — المحتوى اصطناعي للاختبار فقط.

class _FakeTafsirApi {
  int calls = 0;
  final Map<String, String> responses;

  _FakeTafsirApi(this.responses);

  Future<TafsirEntry> getTafsir({
    required TafsirSource source,
    required String ayahKey,
  }) async {
    calls++;
    final html = responses[ayahKey];
    if (html == null) throw StateError('لا يوجد تفسير');
    return TafsirEntry(
      resourceId: source.resourceId,
      ayahKey: ayahKey,
      sourceNameAr: source.nameAr,
      htmlText: html,
    );
  }
}

void main() {
  const source = TafsirSource(resourceId: 16, nameAr: 'الميسر', slug: 'test');

  group('TafsirCacheRepository', () {
    test('يجلب من الشبكة عند غياب الكاش ثم يخزّن', () async {
      final api = _FakeTafsirApi({'18:1': '<p>نص-اختباري</p>'});
      final repo = TafsirCacheRepository(
        store: InMemoryTafsirCacheStore(),
        api: api,
      );

      final first = await repo.get(source: source, ayahKey: '18:1');
      expect(first.plainText, contains('نص-اختباري'));
      expect(api.calls, 1);

      // الطلب الثاني يُخدم من الكاش دون شبكة.
      final second = await repo.get(source: source, ayahKey: '18:1');
      expect(second.plainText, contains('نص-اختباري'));
      expect(api.calls, 1);
    });

    test('مصادر مختلفة تُخزَّن بمفاتيح مستقلة', () async {
      final store = InMemoryTafsirCacheStore();
      final api = _FakeTafsirApi({'18:1': '<p>أ</p>'});
      final repo = TafsirCacheRepository(store: store, api: api);
      const other = TafsirSource(resourceId: 14, nameAr: 'آخر', slug: 'x');

      await repo.get(source: source, ayahKey: '18:1');
      // المصدر الآخر غير مخزّن — مستودع بلا شبكة يرمي خطأ صريحًا
      // بدل إرجاع تفسير المصدر الأول خطأً.
      final offlineRepo = TafsirCacheRepository(store: store);
      await expectLater(
        offlineRepo.get(source: other, ayahKey: '18:1'),
        throwsStateError,
      );
      // والمصدر الأصلي ما زال يُخدم من الكاش.
      final again = await offlineRepo.get(source: source, ayahKey: '18:1');
      expect(again.plainText, contains('أ'));
    });

    test('دون api محقون وكاش فارغ: خطأ صريح لا بيانات وهمية', () async {
      final repo = TafsirCacheRepository(store: InMemoryTafsirCacheStore());

      await expectLater(
        repo.get(source: source, ayahKey: '18:1'),
        throwsStateError,
      );
    });

    test('مفتاح آية غير صالح يُرفض', () async {
      final repo = TafsirCacheRepository(store: InMemoryTafsirCacheStore());

      await expectLater(
        repo.get(source: source, ayahKey: 'غير-صالح'),
        throwsFormatException,
      );
    });

    test('المسح يفرّغ الكاش', () async {
      final api = _FakeTafsirApi({'18:1': '<p>أ</p>'});
      final repo = TafsirCacheRepository(
        store: InMemoryTafsirCacheStore(),
        api: api,
      );

      await repo.get(source: source, ayahKey: '18:1');
      await repo.clear();
      await repo.get(source: source, ayahKey: '18:1');
      expect(api.calls, 2);
    });
  });
}
