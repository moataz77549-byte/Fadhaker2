import '../domain/quran_topic.dart';

abstract class QuranTopicProvider {
  String get sourceName;
  String get sourceVersion;
  String get attribution;
  String get licenseReference;

  Future<List<QuranTopicRecord>> fetchAllTopics();

  Future<bool> hasUpdatesSince(DateTime since);

  Future<List<QuranTopicRecord>> searchTopics(String query);
}
