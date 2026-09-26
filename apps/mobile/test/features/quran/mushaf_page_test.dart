import 'package:fadhkur_mobile/features/quran/domain/mushaf_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and caches a Quran page without losing ayah metadata', () {
    final page = MushafPage.fromApi(293, {'verses': [{'verse_key': '18:1', 'text_uthmani': 'الْحَمْدُ لِلَّهِ', 'text_uthmani_tajweed': '<tajweed>الْحَمْدُ</tajweed> لِلَّهِ', 'juz_number': 15, 'hizb_number': 29}]}, 'الكهف');
    final restored = MushafPage.decode(page.encode());
    expect(restored.number, 293);
    expect(restored.juz, 15);
    expect(restored.hizb, 29);
    expect(restored.surahName, 'الكهف');
    expect(restored.ayahs.single.key, '18:1');
  });

  test('يحفظ معرّف الرواية في التخزين المؤقت مع توافق رجعي', () {
    final page = MushafPage.fromApi(
      293,
      {'verses': [{'verse_key': '18:1', 'text_uthmani': 'نص', 'juz_number': 15}]},
      'الكهف',
      riwayaId: 'hafs',
    );
    final restored = MushafPage.decode(page.encode());
    expect(restored.riwayaId, 'hafs');

    // حمولة قديمة بلا riwayaId → الافتراضي hafs
    final legacy = MushafPage.decode('{"number":1,"juz":1,"hizb":1,"surahName":"الفاتحة","ayahs":[]}');
    expect(legacy.riwayaId, 'hafs');
  });

  test('يدعم صيغة verseKey البديلة (camelCase)', () {
    final ayah = MushafAyah.fromJson({'verseKey': '2:255', 'textUthmani': 'نص'});
    expect(ayah.chapterId, 2);
    expect(ayah.number, 255);
    expect(ayah.text, 'نص');
  });

  test('QCF word derives verse key and position from location fallback', () {
    final word = MushafWord.fromJson({
      'location': '2:255:7',
      'line_number': 8,
      'text_qpc_hafs': 'ٱللَّهُ',
    });
    expect(word.verseKey, '2:255');
    expect(word.position, 7);
    expect(word.lineNumber, 8);
    expect(word.textQpcHafs, 'ٱللَّهُ');
  });

}
