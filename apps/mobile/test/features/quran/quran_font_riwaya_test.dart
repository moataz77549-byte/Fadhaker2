import 'package:fadhkur_mobile/features/quran/domain/quran_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuranFontOption — دعم الروايات', () {
    test('الخطوط المضمّنة تدعم حفص صراحةً', () {
      for (final font in QuranFontRegistry.builtin) {
        expect(font.supportsRiwaya('hafs'), isTrue,
            reason: 'الخط ${font.id} يجب أن يعلن دعم حفص');
      }
    });

    test('fromJson يقرأ supportedRiwayaIds من الـ Backend', () {
      final font = QuranFontOption.fromJson({
        'id': 'warsh-naskh',
        'nameAr': 'نسخ — ورش',
        'fontFamily': 'WarshNaskh',
        'lineHeight': 2.0,
        'supportedRiwayaIds': ['warsh', 'qalun'],
      });
      expect(font.supportsRiwaya('warsh'), isTrue);
      expect(font.supportsRiwaya('qalun'), isTrue);
      expect(font.supportsRiwaya('hafs'), isFalse);
    });

    test('غياب الحقل من الـ Backend يعني حفص فقط (لا ادّعاء ضمني)', () {
      final font = QuranFontOption.fromJson({'id': 'x', 'nameAr': 'س'});
      expect(font.supportedRiwayaIds, ['hafs']);
    });

    test('bestForRiwaya يختار أول خط داعم للرواية', () {
      final fonts = [
        const QuranFontOption(
          id: 'a',
          nameAr: 'أ',
          fontFamily: 'A',
          lineHeight: 2.0,
          licenseNoteAr: '',
          supportedRiwayaIds: ['hafs'],
        ),
        const QuranFontOption(
          id: 'b',
          nameAr: 'ب',
          fontFamily: 'B',
          lineHeight: 2.0,
          licenseNoteAr: '',
          supportedRiwayaIds: ['warsh'],
        ),
      ];
      expect(QuranFontRegistry.bestForRiwaya('warsh', fonts).id, 'b');
      expect(QuranFontRegistry.bestForRiwaya('hafs', fonts).id, 'a');
    });

    test('bestForRiwaya يسقط على أول خط عند غياب الدعم (لا كسر)', () {
      final fonts = [
        const QuranFontOption(
          id: 'a',
          nameAr: 'أ',
          fontFamily: 'A',
          lineHeight: 2.0,
          licenseNoteAr: '',
          supportedRiwayaIds: ['hafs'],
        ),
      ];
      expect(QuranFontRegistry.bestForRiwaya('duri', fonts).id, 'a');
    });

    test('التسلسل يحفظ supportedRiwayaIds ذهابًا وإيابًا', () {
      final font = QuranFontOption.fromJson({
        'id': 'w',
        'supportedRiwayaIds': ['warsh'],
      });
      final restored = QuranFontOption.fromJson(font.toJson());
      expect(restored.supportedRiwayaIds, ['warsh']);
    });
  });
}
