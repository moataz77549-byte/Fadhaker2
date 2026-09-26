import 'package:fadhkur_mobile/features/quran/domain/mushaf_page.dart';
import 'package:fadhkur_mobile/features/quran/presentation/quran_unified_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('continuous page keeps source verses and separates surah headings',
      (tester) async {
    const first = MushafAyah(
      key: '76:31', chapterId: 76, number: 31,
      text: 'يُدْخِلُ مَن يَشَاءُ فِي رَحْمَتِهِ', tajweedText: '',
    );
    const second = MushafAyah(
      key: '77:1', chapterId: 77, number: 1,
      text: 'وَالْمُرْسَلَاتِ عُرْفًا', tajweedText: '',
    );
    const page = MushafPage(
      number: 580, juz: 29, hizb: 58,
      surahName: 'الإنسان', ayahs: [first, second],
    );
    MushafAyah? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: QuranVerseFlow(
      page: page,
      style: const TextStyle(fontSize: 22, height: 1.8),
      goldColor: Colors.green,
      onAyahPressed: (ayah) => selected = ayah,
    ))));

    expect(find.text('سورة المرسلات'), findsOneWidget);
    final content = tester.widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText()).join(' ');
    expect(content, contains(first.text));
    expect(content, contains(second.text));
    expect(content, contains('﴿٣١﴾'));
    expect(content, contains('﴿١﴾'));
    await tester.tap(find.textContaining(second.text, findRichText: true));
    expect(selected?.key, second.key);
    selected = null;
    await tester.longPress(find.textContaining(second.text, findRichText: true));
    expect(selected?.key, second.key);
  });
}
