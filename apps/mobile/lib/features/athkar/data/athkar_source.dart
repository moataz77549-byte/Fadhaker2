import '../domain/athkar_models.dart';

/// Chapter indexes (in the upstream Hisn al-Muslim JSON order) that make up
/// each in-app group. Anything not listed falls into the "general" group.
const _groupIndexes = <String, List<int>>{
  'wakeup': [2],
  'morning_evening': [28],
  'prayer': [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 33, 34],
  'sleep': [29, 30, 31, 32],
  'travel': [96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106],
  'roqyah': [49, 50, 51, 52, 125, 126, 127, 129],
  'home': [3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
  'tasbih': [1, 130, 131, 132],
};

const _groupTitles = <String, String>{
  'wakeup': 'أذكار الاستيقاظ',
  'morning_evening': 'أذكار الصباح والمساء',
  'prayer': 'أذكار الصلاة',
  'sleep': 'أذكار النوم',
  'travel': 'أذكار السفر',
  'roqyah': 'الرقية والشفاء',
  'home': 'أذكار المنزل واللباس',
  'tasbih': 'التسبيح والاستغفار',
  'general': 'أدعية متنوعة',
};

final _whitespace = RegExp(r'\s+');

/// Converts the upstream `{ "باب": { "text": [], "footnote": [] } }` shape
/// into the grouped [AthkarLibrary] used by the app.
AthkarLibrary buildAthkarLibrary(
  Map<String, dynamic> raw, {
  required String source,
}) {
  final keys = raw.keys.toList(growable: false);
  final chapters = <int, AthkarChapter>{};

  for (var index = 0; index < keys.length; index++) {
    final key = keys[index];
    if (key.trim() == 'المقدمة') continue;
    final value = raw[key];
    if (value is! Map) continue;
    final texts = (value['text'] as List?) ?? const [];
    final notes = (value['footnote'] as List?) ?? const [];
    final items = <AthkarItem>[];
    for (var i = 0; i < texts.length; i++) {
      final text = '${texts[i]}'.replaceAll(_whitespace, ' ').trim();
      if (text.isEmpty) continue;
      final note = i < notes.length ? '${notes[i]}'.trim() : '';
      items.add(AthkarItem(
        id: 'b${index.toString().padLeft(3, '0')}_$i',
        text: text,
        repeat: 1,
        note: note.isEmpty ? null : note,
      ));
    }
    if (items.isEmpty) continue;
    chapters[index] = AthkarChapter(
      id: 'b${index.toString().padLeft(3, '0')}',
      title: key.trim(),
      items: items,
    );
  }

  final assigned = <int>{};
  final groups = <AthkarGroup>[];

  for (final entry in _groupIndexes.entries) {
    final picked = <AthkarChapter>[];
    for (final index in entry.value) {
      final chapter = chapters[index];
      if (chapter == null) continue;
      picked.add(chapter);
      assigned.add(index);
    }
    if (picked.isEmpty) continue;
    groups.add(AthkarGroup(
      id: entry.key,
      title: _groupTitles[entry.key] ?? entry.key,
      chapters: picked,
    ));
  }

  final rest = chapters.keys.where((index) => !assigned.contains(index)).toList()
    ..sort();
  if (rest.isNotEmpty) {
    groups.add(AthkarGroup(
      id: 'general',
      title: _groupTitles['general']!,
      chapters: rest.map((index) => chapters[index]!).toList(growable: false),
    ));
  }

  return AthkarLibrary(groups: groups, source: source);
}
