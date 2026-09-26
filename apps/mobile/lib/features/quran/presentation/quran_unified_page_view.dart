import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import '../data/surah_metadata.dart';
import '../data/quran_reading_state_repository.dart';
import '../data/quran_topic_repository.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_topic.dart';
import '../domain/quran_navigation.dart';
import 'tajweed_markup.dart';

class QuranUnifiedPageView extends StatelessWidget {
  const QuranUnifiedPageView({
    super.key,
    required this.controller,
    required this.mode,
    required this.showTopicColors,
    required this.showTajweedLegend,
    required this.dark,
    required this.pageColor,
    required this.inkColor,
    required this.goldColor,
    required this.mutedColor,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.loadPage,
    required this.onPageChanged,
    required this.onRetry,
    required this.onAyahPressed,
    required this.onVerseKeyRequested,
    required this.topicRepository,
  });

  final PageController controller;
  final QuranReadingMode mode;
  final bool showTopicColors;
  final bool showTajweedLegend;
  final bool dark;
  final Color pageColor;
  final Color inkColor;
  final Color goldColor;
  final Color mutedColor;
  final String? fontFamily;
  final double fontSize;
  final double lineHeight;
  final Future<MushafPage> Function(int page) loadPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRetry;
  final ValueChanged<MushafAyah> onAyahPressed;
  final ValueChanged<String> onVerseKeyRequested;
  final QuranTopicRepository topicRepository;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      reverse: true,
      itemCount: QuranNavigation.quranFoundationTextPages,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final page = QuranNavigation.indexToPage(index);
        return FutureBuilder<MushafPage>(
          future: loadPage(page),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _UnifiedPageSkeleton();
            }
            final data = snapshot.data;
            if (snapshot.hasError || data == null) {
              return Center(
                child: FilledButton.icon(
                  onPressed: () => onRetry(page),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة تحميل الصفحة'),
                ),
              );
            }
            return _PageBody(
              page: data,
              mode: mode,
              showTopicColors: showTopicColors,
              showTajweedLegend: showTajweedLegend,
              dark: dark,
              pageColor: pageColor,
              inkColor: inkColor,
              goldColor: goldColor,
              mutedColor: mutedColor,
              fontFamily: fontFamily,
              fontSize: fontSize,
              lineHeight: lineHeight,
              onAyahPressed: onAyahPressed,
              onVerseKeyRequested: onVerseKeyRequested,
              topicRepository: topicRepository,
            );
          },
        );
      },
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.page,
    required this.mode,
    required this.showTopicColors,
    required this.showTajweedLegend,
    required this.dark,
    required this.pageColor,
    required this.inkColor,
    required this.goldColor,
    required this.mutedColor,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    required this.onAyahPressed,
    required this.onVerseKeyRequested,
    required this.topicRepository,
  });

  final MushafPage page;
  final QuranReadingMode mode;
  final bool showTopicColors;
  final bool showTajweedLegend;
  final bool dark;
  final Color pageColor;
  final Color inkColor;
  final Color goldColor;
  final Color mutedColor;
  final String? fontFamily;
  final double fontSize;
  final double lineHeight;
  final ValueChanged<MushafAyah> onAyahPressed;
  final ValueChanged<String> onVerseKeyRequested;
  final QuranTopicRepository topicRepository;

  TextStyle get _baseStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: mode == QuranReadingMode.madani || mode == QuranReadingMode.text
            ? lineHeight.clamp(1.65, 1.9)
            : lineHeight,
        color: inkColor,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 12,
              maxWidth: 650,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: pageColor,
              border: Border.all(color: goldColor, width: 2),
            ),
            alignment: page.number == 1 ? Alignment.center : Alignment.topCenter,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: switch (mode) {
                QuranReadingMode.madani => _MadaniLayout(
                    page: page,
                    style: _baseStyle,
                    goldColor: goldColor,
                    mutedColor: mutedColor,
                    onAyahPressed: onAyahPressed,
                  ),
                QuranReadingMode.tajweed => _TajweedLayout(
                    page: page,
                    style: _baseStyle,
                    dark: dark,
                    showLegend: showTajweedLegend,
                    onAyahPressed: onAyahPressed,
                  ),
                QuranReadingMode.thematic => _ThematicLayout(
                    page: page,
                    style: _baseStyle,
                    dark: dark,
                    showTopicColors: showTopicColors,
                    pageColor: pageColor,
                    mutedColor: mutedColor,
                    topicRepository: topicRepository,
                    onAyahPressed: onAyahPressed,
                    onVerseKeyRequested: onVerseKeyRequested,
                  ),
                QuranReadingMode.text => _PlainTextLayout(
                    page: page,
                    style: _baseStyle,
                    onAyahPressed: onAyahPressed,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MadaniLayout extends StatelessWidget {
  const _MadaniLayout({
    required this.page,
    required this.style,
    required this.goldColor,
    required this.mutedColor,
    required this.onAyahPressed,
  });

  final MushafPage page;
  final TextStyle style;
  final Color goldColor;
  final Color mutedColor;
  final ValueChanged<MushafAyah> onAyahPressed;

  @override
  Widget build(BuildContext context) {
    final allWords = page.ayahs.expand((ayah) => ayah.words).toList();
    final usableWords =
        allWords.where((word) => word.lineNumber > 0 && word.textQpcHafs.isNotEmpty).toList();
    if (usableWords.isEmpty) {
      return Column(
        children: [
          Text(
            'تعذّر تحميل تخطيط QCF لهذه الصفحة؛ يُعرض النص العثماني كاحتياط.',
            style: TextStyle(fontSize: 11, color: mutedColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          QuranVerseFlow(
            page: page,
            style: style,
            goldColor: goldColor,
            onAyahPressed: onAyahPressed,
          ),
        ],
      );
    }

    final ayahByKey = {for (final ayah in page.ayahs) ayah.key: ayah};
    final lines = <int, List<MushafWord>>{};
    for (final word in usableWords) {
      (lines[word.lineNumber] ??= <MushafWord>[]).add(word);
    }
    final numbers = lines.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SurahHeader(page: page, goldColor: goldColor, style: style),
        for (final lineNumber in numbers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  for (final word in lines[lineNumber]!)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          final ayah = ayahByKey[word.verseKey];
                          if (ayah != null) onAyahPressed(ayah);
                        },
                        child: Text(
                          word.textQpcHafs,
                          textDirection: TextDirection.rtl,
                          style: style.copyWith(height: 1.75),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TajweedLayout extends StatelessWidget {
  const _TajweedLayout({
    required this.page,
    required this.style,
    required this.dark,
    required this.showLegend,
    required this.onAyahPressed,
  });

  final MushafPage page;
  final TextStyle style;
  final bool dark;
  final bool showLegend;
  final ValueChanged<MushafAyah> onAyahPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showLegend) Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => TajweedLegendSheet(dark: dark),
            ),
            icon: const Icon(Icons.palette_outlined, size: 18),
            label: const Text('مفتاح التجويد'),
          ),
        ),
        for (final ayah in page.ayahs)
          InkWell(
            onTap: () => onAyahPressed(ayah),
            onLongPress: () => onAyahPressed(ayah),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: RichText(
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                text: TextSpan(
                  children: [
                    TajweedMarkup.parse(
                      ayah.tajweedText,
                      baseStyle: style,
                      dark: dark,
                    ),
                    TextSpan(
                      text: ' ﴿${_arabicNumber(ayah.number)}﴾',
                      style: style,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A continuous, selectable-by-verse fallback. Original verse text is kept
/// intact; the heading and verse marker are separate display elements.
class QuranVerseFlow extends StatefulWidget {
  const QuranVerseFlow({
    super.key,
    required this.page,
    required this.style,
    required this.goldColor,
    required this.onAyahPressed,
  });

  final MushafPage page;
  final TextStyle style;
  final Color goldColor;
  final ValueChanged<MushafAyah> onAyahPressed;

  @override
  State<QuranVerseFlow> createState() => _QuranVerseFlowState();
}

class _QuranVerseFlowState extends State<QuranVerseFlow> {
  final Map<String, TapGestureRecognizer> _recognizers = {};
  final Map<int, GlobalKey> _paragraphKeys = {};

  void _openLongPressedVerse(List<MushafAyah> group, int chapter, Offset at) {
    final paragraph = _paragraphKeys[chapter]?.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return;
    final position = paragraph.getPositionForOffset(paragraph.globalToLocal(at));
    var offset = 0;
    for (final ayah in group) {
      offset += ayah.text.length + 1 + '﴿${_arabicNumber(ayah.number)}﴾ '.length;
      if (position.offset < offset) {
        widget.onAyahPressed(ayah);
        return;
      }
    }
  }

  @override
  void didUpdateWidget(QuranVerseFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) {
      for (final recognizer in _recognizers.values) {
        recognizer.dispose();
      }
      _recognizers.clear();
      _paragraphKeys.clear();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <List<MushafAyah>>[];
    for (final ayah in widget.page.ayahs) {
      if (groups.isEmpty || groups.last.last.chapterId != ayah.chapterId) {
        groups.add(<MushafAyah>[]);
      }
      groups.last.add(ayah);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          if (group.first.number == 1)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: widget.goldColor.withValues(alpha: 0.65)),
                ),
              ),
              child: Text(
                group.first.chapterId >= 1 && group.first.chapterId <= allSurahs.length
                    ? allSurahs[group.first.chapterId - 1].displayName
                    : widget.page.surahName,
                textAlign: TextAlign.center,
                style: widget.style.copyWith(
                  fontSize: widget.style.fontSize! * 0.85,
                  color: widget.goldColor,
                ),
              ),
            ),
          GestureDetector(
            onLongPressStart: (details) => _openLongPressedVerse(
              group, group.first.chapterId, details.globalPosition,
            ),
            child: Text.rich(
            TextSpan(
              style: widget.style,
              children: [
                for (final ayah in group) ...[
                  TextSpan(
                    text: '${ayah.text} ',
                    recognizer: (_recognizers[ayah.key] ??= TapGestureRecognizer())
                      ..onTap = () => widget.onAyahPressed(ayah),
                  ),
                  TextSpan(
                    text: '﴿${_arabicNumber(ayah.number)}﴾ ',
                    style: widget.style.copyWith(color: widget.goldColor),
                    recognizer: _recognizers[ayah.key],
                  ),
                ],
              ],
            ),
            textAlign: widget.page.number == 1 ? TextAlign.center : TextAlign.justify,
            textDirection: TextDirection.rtl,
            key: _paragraphKeys.putIfAbsent(group.first.chapterId, GlobalKey.new),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlainTextLayout extends StatelessWidget {
  const _PlainTextLayout({
    required this.page,
    required this.style,
    required this.onAyahPressed,
  });

  final MushafPage page;
  final TextStyle style;
  final ValueChanged<MushafAyah> onAyahPressed;

  @override
  Widget build(BuildContext context) {
    return QuranVerseFlow(
      page: page,
      style: style,
      goldColor: Theme.of(context).colorScheme.primary,
      onAyahPressed: onAyahPressed,
    );
  }
}

class _ThematicLayout extends StatelessWidget {
  const _ThematicLayout({
    required this.page,
    required this.style,
    required this.dark,
    required this.showTopicColors,
    required this.pageColor,
    required this.mutedColor,
    required this.topicRepository,
    required this.onAyahPressed,
    required this.onVerseKeyRequested,
  });

  final MushafPage page;
  final TextStyle style;
  final bool dark;
  final bool showTopicColors;
  final Color pageColor;
  final Color mutedColor;
  final QuranTopicRepository topicRepository;
  final ValueChanged<MushafAyah> onAyahPressed;
  final ValueChanged<String> onVerseKeyRequested;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<QuranTopic>>>(
      future: topicRepository.topicsForPage(page),
      builder: (context, snapshot) {
        final topicsByVerse = snapshot.data ?? const <String, List<QuranTopic>>{};
        return Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: topicsByVerse.isEmpty
                    ? null
                    : () => _showPageLegend(context, topicsByVerse),
                icon: const Icon(Icons.layers_outlined, size: 18),
                label: const Text('دليل موضوعات الصفحة'),
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              LinearProgressIndicator(color: mutedColor),
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'تعذّرت مزامنة الموضوعات؛ النص القرآني ما زال متاحًا.',
                  style: TextStyle(fontSize: 11, color: mutedColor),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final ayah in page.ayahs)
              _ThematicAyah(
                ayah: ayah,
                topics: topicsByVerse[ayah.key] ?? const [],
                style: style,
                dark: dark,
                showTopicColors: showTopicColors,
                pageColor: pageColor,
                topicRepository: topicRepository,
                onAyahPressed: onAyahPressed,
                onVerseKeyRequested: onVerseKeyRequested,
              ),
          ],
        );
      },
    );
  }

  Future<void> _showPageLegend(
    BuildContext context,
    Map<String, List<QuranTopic>> topicsByVerse,
  ) async {
    final unique = <int, QuranTopic>{};
    for (final topics in topicsByVerse.values) {
      for (final topic in topics) {
        unique[topic.id] = topic;
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text(
              'موضوعات هذه الصفحة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final topic in unique.values)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.circle,
                  size: 16,
                  color: _topicColor(topic.id, dark),
                ),
                title: Text(topic.titleAr),
              ),
            const Divider(),
            const Text(
              'التصنيف الموضوعي محتوى فهرسي من Quranpedia وليس جزءًا من نص القرآن.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThematicAyah extends StatelessWidget {
  const _ThematicAyah({
    required this.ayah,
    required this.topics,
    required this.style,
    required this.dark,
    required this.showTopicColors,
    required this.pageColor,
    required this.topicRepository,
    required this.onAyahPressed,
    required this.onVerseKeyRequested,
  });

  final MushafAyah ayah;
  final List<QuranTopic> topics;
  final TextStyle style;
  final bool dark;
  final bool showTopicColors;
  final Color pageColor;
  final QuranTopicRepository topicRepository;
  final ValueChanged<MushafAyah> onAyahPressed;
  final ValueChanged<String> onVerseKeyRequested;

  @override
  Widget build(BuildContext context) {
    final topic = topics.isEmpty ? null : topics.first;
    final accent = topic == null || !showTopicColors
        ? null
        : _topicColor(topic.id, dark);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: accent == null
            ? null
            : Color.alphaBlend(
                accent.withValues(alpha: dark ? 0.20 : 0.12),
                pageColor,
              ),
        borderRadius: BorderRadius.circular(8),
        border: accent == null
            ? null
            : BorderDirectional(
                start: BorderSide(color: accent, width: 3),
              ),
      ),
      child: InkWell(
        onTap: () => topics.isEmpty
            ? onAyahPressed(ayah)
            : _showTopicDetails(context),
        onLongPress: () => onAyahPressed(ayah),
        child: Column(
          children: [
            Text(
              '${ayah.text} ﴿${_arabicNumber(ayah.number)}﴾',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: style,
            ),
            if (topics.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  for (final item in topics.take(3))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        item.titleAr,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  if (topics.length > 3)
                    Text('+${topics.length - 3}', style: const TextStyle(fontSize: 10)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRelatedVerses(
    BuildContext context,
    String title,
    List<String> keys, {
    bool focusSearch = false,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: focusSearch ? 0.78 : 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  focusSearch ? 'نتائج موضوع «$title»' : 'الآيات المتعلقة بـ «$title»',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'هذه نتائج تصنيف موضوعي، وليست مجرد آيات تحتوي كلمة الموضوع.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: keys.length,
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    return ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text('الآية $key'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.pop(context, key),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      onVerseKeyRequested(selected);
    }
  }

  Future<void> _showTopicDetails(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              Text(
                'الآية ${ayah.key}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                ayah.text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: style,
              ),
              const Divider(height: 28),
              for (final topic in topics)
                Card(
                  child: ExpansionTile(
                    title: Text(topic.titleAr),
                    subtitle: topic.parentTopicId == null
                        ? null
                        : Text('الموضوع الأعلى: #${topic.parentTopicId}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: FutureBuilder<List<String>>(
                          future: topicRepository.relatedVerseKeys(topic.id),
                          builder: (context, snapshot) {
                            final keys = snapshot.data ?? const <String>[];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  snapshot.connectionState == ConnectionState.waiting
                                      ? 'جارٍ تحميل الآيات المتعلقة…'
                                      : 'الآيات المتعلقة: ${keys.length}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                if (keys.isNotEmpty)
                                  SelectableText(
                                    keys.take(80).join('، '),
                                    textDirection: TextDirection.rtl,
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: keys.isEmpty
                                            ? null
                                            : () => _showRelatedVerses(
                                                  context,
                                                  topic.titleAr,
                                                  keys,
                                                ),
                                        icon: const Icon(Icons.list_alt_outlined),
                                        label: const Text('عرض الآيات المتعلقة'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: keys.isEmpty
                                            ? null
                                            : () => _showRelatedVerses(
                                                  context,
                                                  topic.titleAr,
                                                  keys,
                                                  focusSearch: true,
                                                ),
                                        icon: const Icon(Icons.search),
                                        label: const Text('البحث في الموضوع'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'المصدر: Quranpedia.net — هذا التصنيف فهرسي/تفسيري وليس جزءًا من النص القرآني.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({
    required this.page,
    required this.goldColor,
    required this.style,
  });

  final MushafPage page;
  final Color goldColor;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (page.ayahs.isEmpty || page.ayahs.first.number != 1) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: goldColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'سورة ${page.surahName}',
        textAlign: TextAlign.center,
        style: style.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

Color _topicColor(int id, bool dark) {
  const palette = <Color>[
    Color(0xFF3F6F8A),
    Color(0xFF7A5B8C),
    Color(0xFF3F7B63),
    Color(0xFF9A6B3D),
    Color(0xFF8A4F5D),
    Color(0xFF5B6F3F),
    Color(0xFF4E668A),
    Color(0xFF806F3E),
  ];
  final base = palette[id.abs() % palette.length];
  return dark ? Color.lerp(base, Colors.white, 0.25)! : base;
}

String _arabicNumber(int value) => value
    .toString()
    .split('')
    .map((digit) => '٠١٢٣٤٥٦٧٨٩'[int.parse(digit)])
    .join();

class _UnifiedPageSkeleton extends StatelessWidget {
  const _UnifiedPageSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
