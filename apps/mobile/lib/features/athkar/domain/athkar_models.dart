/// Domain models for the Athkar (Hisn al-Muslim) engine.
class AthkarItem {
  const AthkarItem({
    required this.id,
    required this.text,
    required this.repeat,
    this.note,
  });

  final String id;
  final String text;
  final int repeat;
  final String? note;

  factory AthkarItem.fromJson(Map<String, dynamic> json) {
    final rawRepeat = json['repeat'];
    final repeat = rawRepeat is int
        ? rawRepeat
        : int.tryParse('${rawRepeat ?? 1}') ?? 1;
    final note = json['note'];
    return AthkarItem(
      id: '${json['id']}',
      text: '${json['text']}'.trim(),
      repeat: repeat < 1 ? 1 : repeat,
      note: (note == null || '$note'.trim().isEmpty) ? null : '$note'.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'repeat': repeat,
        'note': note,
      };
}

class AthkarChapter {
  const AthkarChapter({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<AthkarItem> items;

  int get totalRepeats =>
      items.fold<int>(0, (sum, item) => sum + item.repeat);

  factory AthkarChapter.fromJson(Map<String, dynamic> json) => AthkarChapter(
        id: '${json['id']}',
        title: '${json['title']}'.trim(),
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AthkarItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class AthkarGroup {
  const AthkarGroup({
    required this.id,
    required this.title,
    required this.chapters,
  });

  final String id;
  final String title;
  final List<AthkarChapter> chapters;

  factory AthkarGroup.fromJson(Map<String, dynamic> json) => AthkarGroup(
        id: '${json['id']}',
        title: '${json['title']}'.trim(),
        chapters: ((json['chapters'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AthkarChapter.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );
}

class AthkarLibrary {
  const AthkarLibrary({required this.groups, required this.source});

  final List<AthkarGroup> groups;
  final String source;

  static const empty = AthkarLibrary(groups: [], source: '');

  List<AthkarChapter> get allChapters =>
      groups.expand((group) => group.chapters).toList(growable: false);

  AthkarChapter? chapterById(String id) {
    for (final chapter in allChapters) {
      if (chapter.id == id) return chapter;
    }
    return null;
  }

  List<AthkarChapter> search(String query) {
    final needle = _normalize(query);
    if (needle.isEmpty) return const [];
    return allChapters
        .where((chapter) =>
            _normalize(chapter.title).contains(needle) ||
            chapter.items.any((item) => _normalize(item.text).contains(needle)))
        .toList(growable: false);
  }

  factory AthkarLibrary.fromJson(Map<String, dynamic> json) => AthkarLibrary(
        source: '${json['source'] ?? ''}',
        groups: ((json['groups'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AthkarGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );
}

/// Normalizes Arabic text for search: strips diacritics and unifies letters.
String _normalize(String input) {
  final stripped = input.replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '');
  return stripped
      .replaceAll(RegExp(r'[إأآا]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Progress of a single chapter session (how many repeats are done).
class AthkarProgress {
  const AthkarProgress({required this.chapterId, required this.counts});

  final String chapterId;
  final Map<String, int> counts;

  int countFor(String itemId) => counts[itemId] ?? 0;

  bool isItemDone(AthkarItem item) => countFor(item.id) >= item.repeat;

  bool isChapterDone(AthkarChapter chapter) =>
      chapter.items.every(isItemDone);

  double ratio(AthkarChapter chapter) {
    final total = chapter.totalRepeats;
    if (total == 0) return 0;
    var done = 0;
    for (final item in chapter.items) {
      final count = countFor(item.id);
      done += count > item.repeat ? item.repeat : count;
    }
    return done / total;
  }

  AthkarProgress increment(AthkarItem item) {
    final next = Map<String, int>.from(counts);
    final current = next[item.id] ?? 0;
    next[item.id] = current >= item.repeat ? item.repeat : current + 1;
    return AthkarProgress(chapterId: chapterId, counts: next);
  }

  AthkarProgress reset() =>
      AthkarProgress(chapterId: chapterId, counts: const {});
}
