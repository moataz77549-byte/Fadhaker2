class QuranTopic {
  const QuranTopic({
    required this.id,
    required this.titleAr,
    this.parentTopicId,
    this.category,
    this.source = 'quranpedia',
    this.sourceReference,
  });

  final int id;
  final String titleAr;
  final int? parentTopicId;
  final String? category;
  final String source;
  final String? sourceReference;

  factory QuranTopic.fromJson(Map<String, dynamic> json) => QuranTopic(
        id: (json['id'] as num).toInt(),
        titleAr: (json['name'] ?? json['titleAr'] ?? '').toString(),
        parentTopicId: (json['parent_id'] as num?)?.toInt() ??
            (json['parentTopicId'] as num?)?.toInt(),
        category: json['category']?.toString(),
        source: (json['source'] ?? 'quranpedia').toString(),
        sourceReference: json['sourceReference']?.toString(),
      );
}

class QuranTopicRecord {
  const QuranTopicRecord({
    required this.topic,
    required this.verseKeys,
  });

  final QuranTopic topic;
  final List<String> verseKeys;
}

class TopicSourceInfo {
  const TopicSourceInfo({
    required this.sourceId,
    required this.sourceName,
    required this.sourceVersion,
    required this.license,
    required this.attribution,
    required this.lastUpdated,
  });

  final String sourceId;
  final String sourceName;
  final String sourceVersion;
  final String license;
  final String attribution;
  final DateTime lastUpdated;
}
