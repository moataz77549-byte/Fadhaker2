import 'package:fadhkur_mobile/features/quran/data/qcf_page_font_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QCF glyph entity decoding changes display codes only', () {
    expect(QcfPageFontLoader.glyphs('&#xE001;&#57346;'),
        '${String.fromCharCode(0xE001)}${String.fromCharCode(57346)}');
    expect(QcfPageFontLoader.glyphs('بِسْمِ'), 'بِسْمِ');
  });
}
