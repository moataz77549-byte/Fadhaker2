import 'package:flutter/material.dart';

import '../data/quran_api_repository.dart';
import '../data/quran_topic_repository.dart';
import '../domain/quran_search_result.dart';
import '../domain/quran_topic.dart';

class QuranSearchSelection {
  const QuranSearchSelection({this.verseKey, this.pageNumber});

  final String? verseKey;
  final int? pageNumber;
}

class QuranSearchSheet extends StatefulWidget {
  const QuranSearchSheet({
    super.key,
    required this.api,
    required this.topicRepository,
  });

  final QuranApiRepository api;
  final QuranTopicRepository topicRepository;

  @override
  State<QuranSearchSheet> createState() => _QuranSearchSheetState();
}

class _QuranSearchSheetState extends State<QuranSearchSheet> {
  final _controller = TextEditingController();
  Future<({List<QuranSearchResult> quran, List<QuranTopicRecord> topics})>?
      _future;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    setState(() {
      _future = _load(query);
    });
  }

  Future<({List<QuranSearchResult> quran, List<QuranTopicRecord> topics})>
      _load(String query) async {
    List<QuranSearchResult> quran = const [];
    List<QuranTopicRecord> topics = const [];
    try {
      quran = await widget.api.searchQuran(query);
    } catch (_) {
      // Search API may be temporarily unavailable; topic/offline results remain.
    }
    try {
      topics = await widget.topicRepository.searchTopics(query);
    } catch (_) {
      // First topic sync may fail offline. Quran search can still be shown.
    }

    final exact = RegExp(r'^(\d{1,3}):(\d{1,3})$').firstMatch(query);
    if (exact != null &&
        !quran.any((result) => result.verseKey == query)) {
      quran = [
        QuranSearchResult(
          type: QuranSearchResultType.navigation,
          title: 'الآية $query',
          subtitle: 'انتقال مباشر برقم السورة والآية',
          verseKey: query,
        ),
        ...quran,
      ];
    }
    return (quran: quran, topics: topics);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              const Text(
                'البحث في القرآن والموضوعات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'نص آية، اسم سورة، 2:255، أو موضوع مثل الصبر',
                  suffixIcon: IconButton(
                    onPressed: _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _future == null
                    ? const Center(
                        child: Text(
                          'نتائج نص القرآن والموضوعات تظهر في أقسام منفصلة.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : FutureBuilder<
                        ({
                          List<QuranSearchResult> quran,
                          List<QuranTopicRecord> topics
                        })>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final data = snapshot.data;
                          if (data == null) {
                            return const Center(
                              child: Text('تعذّر تنفيذ البحث'),
                            );
                          }
                          if (data.quran.isEmpty && data.topics.isEmpty) {
                            return const Center(
                              child: Text('لا توجد نتائج مطابقة'),
                            );
                          }
                          return ListView(
                            controller: scrollController,
                            children: [
                              if (data.quran.isNotEmpty) ...[
                                const _SectionHeader(
                                  title: 'نص القرآن والتنقل',
                                  subtitle:
                                      'مطابقة نصية/تنقل من Quran Foundation',
                                ),
                                for (final result in data.quran)
                                  ListTile(
                                    leading: Icon(
                                      result.type ==
                                              QuranSearchResultType.verseText
                                          ? Icons.menu_book_outlined
                                          : Icons.navigation_outlined,
                                    ),
                                    title: Text(
                                      result.title,
                                      textDirection: TextDirection.rtl,
                                    ),
                                    subtitle: result.subtitle == null
                                        ? null
                                        : Text(result.subtitle!),
                                    enabled: result.verseKey != null ||
                                        result.pageNumber != null,
                                    onTap: () => Navigator.pop(
                                      context,
                                      QuranSearchSelection(
                                        verseKey: result.verseKey,
                                        pageNumber: result.pageNumber,
                                      ),
                                    ),
                                  ),
                              ],
                              if (data.topics.isNotEmpty) ...[
                                const _SectionHeader(
                                  title: 'الموضوعات',
                                  subtitle:
                                      'تصنيف موضوعي من Quranpedia — وليس مطابقة كلمة في نص الآية',
                                ),
                                for (final record in data.topics)
                                  _TopicSearchResult(
                                    record: record,
                                    onVerse: (verseKey) => Navigator.pop(
                                      context,
                                      QuranSearchSelection(
                                        verseKey: verseKey,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _TopicSearchResult extends StatelessWidget {
  const _TopicSearchResult({
    required this.record,
    required this.onVerse,
  });

  final QuranTopicRecord record;
  final ValueChanged<String> onVerse;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.layers_outlined),
      title: Text(record.topic.titleAr),
      subtitle: Text('${record.verseKeys.length} آية مصنفة تحت هذا الموضوع'),
      children: [
        if (record.verseKeys.isEmpty)
          const ListTile(title: Text('لا توجد آيات مرتبطة في البيانات المحلية'))
        else
          for (final key in record.verseKeys.take(80))
            ListTile(
              dense: true,
              leading: const Icon(Icons.arrow_back, size: 16),
              title: Text('الآية $key'),
              onTap: () => onVerse(key),
            ),
      ],
    );
  }
}
