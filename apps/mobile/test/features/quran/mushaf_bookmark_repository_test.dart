import 'package:fadhkur_mobile/features/quran/data/mushaf_bookmark_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MushafBookmark _bookmark({
  String ayahKey = '18:1',
  int surahNumber = 18,
  int verseNumber = 1,
  int? page = 293,
  String riwayaId = 'hafs',
}) =>
    MushafBookmark(
      ayahKey: ayahKey,
      surahNumber: surahNumber,
      verseNumber: verseNumber,
      page: page,
      surahName: 'سورة الكهف',
      riwayaId: riwayaId,
      savedAt: DateTime.now(),
    );

void main() {
  group('MushafBookmarkRepository', () {
    late MushafBookmarkRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repository = MushafBookmarkRepository();
    });

    test('قائمة فارغة في البداية (empty state)', () async {
      expect(await repository.list(), isEmpty);
    });

    test('إضافة فاصلة واسترجاعها ببياناتها الكاملة', () async {
      await repository.add(_bookmark());

      final items = await repository.list();
      expect(items, hasLength(1));
      expect(items.first.ayahKey, '18:1');
      expect(items.first.surahNumber, 18);
      expect(items.first.verseNumber, 1);
      expect(items.first.page, 293);
      expect(items.first.riwayaId, 'hafs');
    });

    test('الفاصلة لنفس الآية برواية مختلفة تُحفظ مستقلة', () async {
      await repository.add(_bookmark(riwayaId: 'hafs'));
      await repository.add(_bookmark(riwayaId: 'warsh', page: null));

      final items = await repository.list();
      expect(items, hasLength(2));
    });

    test('إعادة الحفظ لنفس الآية والرواية تستبدل ولا تكرر', () async {
      await repository.add(_bookmark(page: 293));
      await repository.add(_bookmark(page: 294));

      final items = await repository.list();
      expect(items, hasLength(1));
      expect(items.first.page, 294);
    });

    test('الحذف يزيل الفاصلة المحددة فقط', () async {
      await repository.add(_bookmark(ayahKey: '18:1'));
      await repository.add(_bookmark(ayahKey: '18:2', verseNumber: 2));
      await repository.remove('18:1', riwayaId: 'hafs');

      final items = await repository.list();
      expect(items, hasLength(1));
      expect(items.first.ayahKey, '18:2');
    });

    test('ترحيل التنسيق القديم: مفاتيح خام تُحوَّل لفاصلات دون صفحة', () async {
      SharedPreferences.setMockInitialValues({
        'mushaf_bookmarks': ['18:1', '2:255'],
      });
      repository = MushafBookmarkRepository();

      final items = await repository.list();
      expect(items, hasLength(2));
      expect(items.map((b) => b.ayahKey), containsAll(['18:1', '2:255']));
      // الفواصل القديمة لا تحمل رقم صفحة — تُرحَّل بصدق دون تخمين.
      expect(items.every((b) => b.page == null), isTrue);

      // الترحيل لمرة واحدة: المفتاح القديم يُحذف بعد الترحيل.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('mushaf_bookmarks'), isNull);
      expect((await repository.list()), hasLength(2));
    });
  });
}
