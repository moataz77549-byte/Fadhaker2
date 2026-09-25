import 'package:fadhkur_mobile/features/quran/domain/quran_navigation.dart';
import 'package:fadhkur_mobile/features/quran/domain/riwaya.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuranNavigation.parseAyahKey', () {
    test('يقبل مفاتيح صحيحة', () {
      expect(QuranNavigation.parseAyahKey('18:1'), (chapter: 18, verse: 1));
      expect(QuranNavigation.parseAyahKey('114:6'), (chapter: 114, verse: 6));
      expect(QuranNavigation.parseAyahKey(' 2:255 '), (chapter: 2, verse: 255));
    });

    test('يرفض الصيغ الخاطئة', () {
      expect(() => QuranNavigation.parseAyahKey('18'), throwsFormatException);
      expect(() => QuranNavigation.parseAyahKey('18:1:2'), throwsFormatException);
      expect(() => QuranNavigation.parseAyahKey('abc:1'), throwsFormatException);
      expect(() => QuranNavigation.parseAyahKey(''), throwsFormatException);
    });

    test('يرفض ما خارج النطاق', () {
      expect(() => QuranNavigation.parseAyahKey('0:1'), throwsRangeError);
      expect(() => QuranNavigation.parseAyahKey('115:1'), throwsRangeError);
      expect(() => QuranNavigation.parseAyahKey('2:287'), throwsRangeError); // البقرة 286
      expect(() => QuranNavigation.parseAyahKey('1:0'), throwsRangeError);
    });

    test('عدد آيات السور صحيح', () {
      expect(QuranNavigation.maxVersesFor(1), 7);
      expect(QuranNavigation.maxVersesFor(2), 286);
      expect(QuranNavigation.maxVersesFor(114), 6);
      expect(() => QuranNavigation.maxVersesFor(115), throwsRangeError);
    });
  });

  group('نطاقات الصفحات حسب الرواية', () {
    test('حفص: 604 صفحة ولا يُفترض ذلك لغيرها', () {
      expect(RiwayaRegistry.hafs.totalPages, 604);
      expect(
        () => QuranNavigation.validateImagePage(RiwayaRegistry.hafs, 604),
        returnsNormally,
      );
      expect(() => QuranNavigation.validateImagePage(RiwayaRegistry.hafs, 605), throwsRangeError);
      expect(() => QuranNavigation.validateImagePage(RiwayaRegistry.hafs, 0), throwsRangeError);
    });

    test('ورش/قالون/الدوري: التخطيط غير موثّق → رفض وضع الصور', () {
      for (final riwaya in [RiwayaRegistry.warsh, RiwayaRegistry.qalun, RiwayaRegistry.duri]) {
        expect(riwaya.totalPages, isNull, reason: riwaya.id);
        expect(riwaya.supportsImagePages, isFalse, reason: riwaya.id);
        expect(() => QuranNavigation.validateImagePage(riwaya, 1), throwsStateError);
      }
    });

    test('وضع النص: 604 صفحة لنص حفص عبر Quran Foundation', () {
      expect(() => QuranNavigation.validateTextPage(1), returnsNormally);
      expect(() => QuranNavigation.validateTextPage(604), returnsNormally);
      expect(() => QuranNavigation.validateTextPage(605), throwsRangeError);
    });
  });

  group('ربط الفهارس RTL', () {
    test('الصفحة N تقابل الفهرس N-1 مع reverse: true', () {
      expect(QuranNavigation.pageToIndex(1), 0);
      expect(QuranNavigation.pageToIndex(604), 603);
      expect(QuranNavigation.indexToPage(0), 1);
      expect(QuranNavigation.indexToPage(292), 293);
      // ذهاب وإياب
      for (final page in [1, 50, 293, 604]) {
        expect(QuranNavigation.indexToPage(QuranNavigation.pageToIndex(page)), page);
      }
    });
  });

  group('RiwayaRegistry', () {
    test('السجل المضمّن يحوي الروايات الأربع', () {
      final ids = RiwayaRegistry.builtin.map((r) => r.id).toList();
      expect(ids, ['hafs', 'warsh', 'qalun', 'duri']);
    });

    test('byId يرمي لرواية غير معروفة', () {
      expect(() => RiwayaRegistry.byId('unknown'), throwsArgumentError);
    });

    test('pageImageUrl يستبدل {page} برقم من 3 خانات', () {
      const riwaya = Riwaya(
        id: 'hafs', nameAr: 'حفص عن عاصم', narratorAr: '',
        totalPages: 604,
        pageImageTemplate: 'https://cdn.example.com/{page}.webp',
        qfMushafId: 1, textAvailable: true,
      );
      expect(riwaya.supportsImagePages, isTrue);
      expect(riwaya.pageImageUrl(5), 'https://cdn.example.com/005.webp');
      expect(riwaya.pageImageUrl(604), 'https://cdn.example.com/604.webp');
    });

    test('parseList يتجاهل المدخلات الفاسدة', () {
      final list = RiwayaRegistry.parseList([
        {'id': 'hafs', 'nameAr': 'حفص', 'totalPages': 604, 'textAvailable': true},
        {'nameAr': 'بلا معرّف'},
        'not-a-map',
      ]);
      expect(list.map((r) => r.id), ['hafs']);
      expect(RiwayaRegistry.parseList('nope'), isEmpty);
      expect(RiwayaRegistry.parseList(null), isEmpty);
    });

    test('merge يعطي الأولوية لقيم الـ Backend', () {
      const backendWarsh = Riwaya(
        id: 'warsh', nameAr: 'ورش عن نافع', narratorAr: '',
        totalPages: 573, pageImageTemplate: 'https://cdn.example.com/w/{page}.webp',
        qfMushafId: null, textAvailable: false,
      );
      final merged = RiwayaRegistry.merge([backendWarsh]);
      expect(merged.length, 4);
      final warsh = RiwayaRegistry.byId('warsh', merged);
      expect(warsh.totalPages, 573);
      expect(warsh.supportsImagePages, isTrue);
      // حفص بقي كما هو
      expect(RiwayaRegistry.byId('hafs', merged).totalPages, 604);
    });

    test('JSON ذهاب وإياب', () {
      final restored = Riwaya.fromJson(RiwayaRegistry.hafs.toJson());
      expect(restored.id, 'hafs');
      expect(restored.totalPages, 604);
      expect(restored.qfMushafId, 1);
    });
  });
}
