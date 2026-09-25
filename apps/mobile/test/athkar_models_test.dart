import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/features/athkar/data/athkar_source.dart';
import 'package:fadhkur_mobile/features/athkar/domain/athkar_models.dart';

void main() {
  final chapter = AthkarChapter.fromJson(<String, dynamic>{
    'id': 'b028',
    'title': 'أذكار الصباح والمساء',
    'items': [
      {'id': 'b028_0', 'text': 'سُبْحَانَ اللهِ وَبِحَمْدِهِ', 'repeat': 3},
      {'id': 'b028_1', 'text': 'أَعُوذُ بِكَلِمَاتِ اللهِ', 'repeat': 1},
    ],
  });

  test('parses chapter and totals repeats', () {
    expect(chapter.items.length, 2);
    expect(chapter.totalRepeats, 4);
    expect(chapter.items.first.note, isNull);
  });

  test('progress increments and caps at the repeat target', () {
    var progress = AthkarProgress(chapterId: chapter.id, counts: const {});
    for (var i = 0; i < 5; i++) {
      progress = progress.increment(chapter.items.first);
    }
    expect(progress.countFor('b028_0'), 3);
    expect(progress.isItemDone(chapter.items.first), isTrue);
    expect(progress.isChapterDone(chapter), isFalse);

    progress = progress.increment(chapter.items[1]);
    expect(progress.isChapterDone(chapter), isTrue);
    expect(progress.ratio(chapter), 1.0);

    expect(progress.reset().countFor('b028_0'), 0);
  });

  test('search ignores diacritics and alef variants', () {
    final library = AthkarLibrary(
      source: 'test',
      groups: [
        AthkarGroup(id: 'g', title: 'g', chapters: [chapter]),
      ],
    );
    expect(library.search('اذكار الصباح').length, 1);
    expect(library.search('سبحان الله وبحمده').length, 1);
    expect(library.search('لا يوجد شيء كهذا'), isEmpty);
  });

  test('builds grouped library from the upstream Hisn al-Muslim shape', () {
    final raw = <String, dynamic>{
      'المقدمة': {
        'text': ['بسم الله الرحمن الرحيم'],
        'footnote': [''],
      },
      'فضل الذكر': {
        'text': ['من قال سبحان الله وبحمده'],
        'footnote': ['رواه البخاري'],
      },
      'أذكار الاستيقاظ من النوم': {
        'text': ['الحمد لله الذي أحيانا بعد ما أماتنا وإليه النشور'],
        'footnote': [''],
      },
    };

    final library = buildAthkarLibrary(raw, source: 'test');

    expect(library.groups.map((g) => g.id), containsAll(['tasbih', 'wakeup']));
    expect(library.allChapters.length, 2);
    expect(library.chapterById('b002')?.title, 'أذكار الاستيقاظ من النوم');
    expect(library.chapterById('b001')?.items.first.note, 'رواه البخاري');
    // The introduction is skipped.
    expect(
      library.allChapters.any((c) => c.title == 'المقدمة'),
      isFalse,
    );
  });
}
