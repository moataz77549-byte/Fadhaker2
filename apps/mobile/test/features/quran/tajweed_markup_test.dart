import 'package:fadhkur_mobile/features/quran/presentation/tajweed_markup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tajweed parser preserves visible Quran text while removing markup', () {
    const source =
        'بِسْمِ <tajweed class=ham_wasl>ٱ</tajweed>للَّهِ '
        '<tajweed class=madda_normal>ـٰ</tajweed> '
        '<span class=end>١</span>';
    final span = TajweedMarkup.parse(
      source,
      baseStyle: const TextStyle(color: Colors.black),
      dark: false,
    );
    final plain = span.toPlainText();
    expect(plain, contains('بِسْمِ'));
    expect(plain, contains('ٱ'));
    expect(plain, contains('للَّهِ'));
    expect(plain, contains('ـٰ'));
    expect(plain, contains('١'));
    expect(plain, isNot(contains('<tajweed')));
  });

  test('known Quran Foundation rule classes have semantic colors', () {
    expect(TajweedMarkup.colorForClass('ham_wasl', false), isNotNull);
    expect(TajweedMarkup.colorForClass('madda_normal', false), isNotNull);
    expect(TajweedMarkup.colorForClass('ghunnah', true), isNotNull);
    expect(TajweedMarkup.colorForClass('unknown_rule', false), isNull);
  });
}
