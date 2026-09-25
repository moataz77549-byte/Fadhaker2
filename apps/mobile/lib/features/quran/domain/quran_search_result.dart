enum QuranSearchResultType {
  verseText,
  navigation,
  topic,
  topicVerse,
}

class QuranSearchResult {
  const QuranSearchResult({
    required this.type,
    required this.title,
    this.subtitle,
    this.verseKey,
    this.pageNumber,
    this.topicId,
  });

  final QuranSearchResultType type;
  final String title;
  final String? subtitle;
  final String? verseKey;
  final int? pageNumber;
  final int? topicId;

  factory QuranSearchResult.fromFoundation(Map<String, dynamic> json) {
    final key = json['key'];
    final resultType = (json['result_type'] ?? '').toString();
    return QuranSearchResult(
      type: resultType == 'ayah'
          ? QuranSearchResultType.verseText
          : QuranSearchResultType.navigation,
      title: (json['name'] ?? json['arabic'] ?? '').toString(),
      subtitle: resultType,
      verseKey: resultType == 'ayah' ? key?.toString() : null,
      pageNumber: resultType == 'page'
          ? (key is num ? key.toInt() : int.tryParse('$key'))
          : null,
    );
  }
}
