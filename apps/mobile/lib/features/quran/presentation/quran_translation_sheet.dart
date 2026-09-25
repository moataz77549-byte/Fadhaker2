import 'package:flutter/material.dart';

import '../data/quran_translation_repository.dart';

class QuranTranslationSheet extends StatefulWidget {
  const QuranTranslationSheet({super.key, required this.verseKey});
  final String verseKey;

  @override
  State<QuranTranslationSheet> createState() => _QuranTranslationSheetState();
}

class _QuranTranslationSheetState extends State<QuranTranslationSheet> {
  final _repository = QuranTranslationRepository();
  late Future<List<QuranTranslationEdition>> _editions;
  String? _selected;
  @override
  void initState() {
    super.initState();
    _editions = _repository.editions();
    _repository.selectedKey().then((value) {
      if (mounted) setState(() => _selected = value);
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: const EdgeInsets.all(20),
    child: FutureBuilder<List<QuranTranslationEdition>>(
      future: _editions,
      builder: (context, catalog) {
        if (!catalog.hasData && !catalog.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (catalog.hasError) return const Center(child: Text(
          'تعذّر تحميل الترجمات. تحقق من الاتصال ثم حاول مجددًا.'));
        final editions = catalog.data!;
        if (editions.isEmpty) return const Center(child: Text(
          'لا توجد ترجمة معتمدة متاحة حاليًا.'));
        final selected = editions.any((e) => e.key == _selected)
            ? _selected! : editions.first.key;
        return ListView(shrinkWrap: true, children: [
          Text('ترجمة معنى الآية ${widget.verseKey}',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButton<String>(value: selected, isExpanded: true,
            items: editions.map((e) => DropdownMenuItem(value: e.key,
              child: Text('${e.title} (${e.language})'))).toList(),
            onChanged: (key) {
              if (key == null) return;
              setState(() => _selected = key);
              _repository.select(key);
            }),
          FutureBuilder<QuranVerseTranslation?>(
            key: ValueKey('$selected:${widget.verseKey}'),
            future: _repository.verse(widget.verseKey, selected),
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError &&
                  snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return const Text('تعذّر تحميل هذه الترجمة.');
              final verse = snapshot.data;
              if (verse == null) return const Text('هذه الآية غير متاحة بهذه الترجمة بعد.');
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(verse.text, style: const TextStyle(fontSize: 18, height: 1.8)),
                if (verse.footnotes.isNotEmpty) ...[
                  const SizedBox(height: 12), Text(verse.footnotes),
                ],
                const SizedBox(height: 16),
                Text('المصدر: QuranEnc.com · الإصدار ${verse.version}',
                  style: Theme.of(context).textTheme.bodySmall),
              ]);
            }),
        ]);
      },
    ),
  ));
}
