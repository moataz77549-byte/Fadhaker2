class QuranLocation {
  const QuranLocation({
    required this.pageNumber,
    required this.surahNumber,
    required this.ayahNumber,
    required this.verseKey,
    this.wordOffset,
  });

  final int pageNumber;
  final int surahNumber;
  final int ayahNumber;
  final String verseKey;
  final int? wordOffset;

  QuranLocation copyWith({
    int? pageNumber,
    int? surahNumber,
    int? ayahNumber,
    String? verseKey,
    int? wordOffset,
  }) =>
      QuranLocation(
        pageNumber: pageNumber ?? this.pageNumber,
        surahNumber: surahNumber ?? this.surahNumber,
        ayahNumber: ayahNumber ?? this.ayahNumber,
        verseKey: verseKey ?? this.verseKey,
        wordOffset: wordOffset ?? this.wordOffset,
      );

  Map<String, dynamic> toJson() => {
        'pageNumber': pageNumber,
        'surahNumber': surahNumber,
        'ayahNumber': ayahNumber,
        'verseKey': verseKey,
        if (wordOffset != null) 'wordOffset': wordOffset,
      };

  factory QuranLocation.fromJson(Map<String, dynamic> json) {
    final key = (json['verseKey'] ?? '').toString();
    final parts = key.split(':');
    final surah = (json['surahNumber'] as num?)?.toInt() ??
        (parts.isNotEmpty ? int.tryParse(parts.first) : null) ??
        1;
    final ayah = (json['ayahNumber'] as num?)?.toInt() ??
        (parts.length > 1 ? int.tryParse(parts[1]) : null) ??
        1;
    return QuranLocation(
      pageNumber: ((json['pageNumber'] as num?)?.toInt() ?? 1).clamp(1, 604),
      surahNumber: surah,
      ayahNumber: ayah,
      verseKey: key.isEmpty ? '$surah:$ayah' : key,
      wordOffset: (json['wordOffset'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuranLocation &&
      other.pageNumber == pageNumber &&
      other.verseKey == verseKey &&
      other.wordOffset == wordOffset;

  @override
  int get hashCode => Object.hash(pageNumber, verseKey, wordOffset);

  @override
  String toString() => 'QuranLocation(page=$pageNumber, verse=$verseKey)';
}
