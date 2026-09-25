import 'package:fadhkur_mobile/features/quran/domain/mushaf_edition.dart';
import 'package:fadhkur_mobile/features/quran/domain/quran_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MushafEdition — نسخ المصحف المصوّر', () {
    test('النسختان المضمّنتان بتخطيط 604 صفحات فقط', () {
      expect(MushafEditionRegistry.builtin.length, 2);
      for (final edition in MushafEditionRegistry.builtin) {
        expect(edition.totalPages, 604,
            reason: 'النسخة ${edition.id} يجب أن تكون 604 صفحات');
        expect(edition.supportsPages, isTrue);
        expect(edition.riwayaId, 'hafs');
      }
    });

    test('رابط الصفحة بلا تبطين (1.jpg لا 001.jpg)', () {
      final edition = MushafEditionRegistry.byId('hafs-madani');
      expect(
        edition.pageImageUrl(1),
        'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat/1.jpg',
      );
      expect(
        edition.pageImageUrl(604),
        'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat/604.jpg',
      );
      final tajweed = MushafEditionRegistry.byId('hafs-madani-tajweed');
      expect(
        tajweed.pageImageUrl(1),
        'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/easyquran.com/hafs-tajweed/1.jpg',
      );
    });

    test('supportsPages كاذبة عند عدد صفحات غير 604 (لا ادّعاء ضمني)', () {
      const edition = MushafEdition(
        id: 'x',
        riwayaId: 'hafs',
        nameAr: 'س',
        pageImageTemplate: 'https://cdn.example.com/{page}.jpg',
        totalPages: 573,
      );
      expect(edition.supportsPages, isFalse);
    });

    test('forRiwaya يعيد نسخ الرواية فقط', () {
      final hafs = MushafEditionRegistry.forRiwaya('hafs');
      expect(hafs.length, 2);
      expect(MushafEditionRegistry.forRiwaya('warsh'), isEmpty);
    });

    test('دمج الـ Backend يطغى على المضمّن عند تطابق id', () {
      const backend = MushafEdition(
        id: 'hafs-madani',
        riwayaId: 'hafs',
        nameAr: 'اسم من الـ Backend',
        pageImageTemplate: 'https://cdn.example.com/m/{page}.jpg',
      );
      final merged = MushafEditionRegistry.merge([backend]);
      expect(merged.length, 2);
      expect(MushafEditionRegistry.byId('hafs-madani', merged).nameAr,
          'اسم من الـ Backend');
    });

    test('التسلسل يحفظ الحقول ذهابًا وإيابًا', () {
      final edition = MushafEditionRegistry.byId('hafs-madani-tajweed');
      final restored =
          MushafEdition.fromJson(edition.toJson().cast<String, dynamic>());
      expect(restored.pageImageUrl(7), edition.pageImageUrl(7));
      expect(restored.pagePadWidth, 0);
    });
  });

  group('QuranFontOption — روابط التحميل', () {
    test('الخطان الموثّقان يحملان رابط تحميل', () {
      final uthmanic =
          QuranFontRegistry.byId('uthmanic-hafs').hasDownload;
      final kfgqpc = QuranFontRegistry.byId('kfgqpc-hafs').hasDownload;
      expect(uthmanic, isTrue);
      expect(kfgqpc, isTrue);
    });

    test('الخطان غير الموثّقين بلا رابط — fallback صريح لخط النظام', () {
      expect(QuranFontRegistry.byId('qcf').hasDownload, isFalse);
      expect(QuranFontRegistry.byId('uthmanic-vector').hasDownload, isFalse);
    });

    test('fromJson/toJson يحفظان downloadUrl', () {
      final font = QuranFontRegistry.byId('uthmanic-hafs');
      final restored = QuranFontOption.fromJson(
          font.toJson().cast<String, dynamic>());
      expect(restored.downloadUrl, font.downloadUrl);
      expect(restored.hasDownload, isTrue);
    });

    test('غياب downloadUrl من الـ Backend يعني null (لا ادّعاء ضمني)', () {
      final font = QuranFontOption.fromJson({'id': 'x', 'nameAr': 'س'});
      expect(font.downloadUrl, isNull);
      expect(font.hasDownload, isFalse);
    });
  });
}
