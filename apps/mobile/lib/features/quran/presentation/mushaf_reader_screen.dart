import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../home/data/reading_progress_repository.dart';
import '../data/mushaf_bookmark_repository.dart';
import '../data/mushaf_repository.dart';
import '../data/quran_api_repository.dart';
import '../data/quran_config_repository.dart';
import '../data/quran_font_loader.dart';
import '../data/quran_reading_state_repository.dart';
import '../data/tafsir_cache_repository.dart';
import '../domain/mushaf_edition.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_font.dart';
import '../domain/quran_navigation.dart';
import '../domain/riwaya.dart';
import '../domain/tafsir_source.dart';
import '../../../core/widgets/skeleton.dart';
import 'quran_settings_sheet.dart';
import 'quran_translation_sheet.dart';

/// شاشة المصحف: وضع مصوّر (صور الصفحات) ووضع نص.
///
/// - ترتيب الصفحات RTL عبر PageView.builder مع reverse: true.
/// - لا تُحمَّل كل الصفحات في الذاكرة (بناء كسول لكل صفحة).
/// - آخر صفحة تُحفظ لكل رواية على حدة.
/// - كل المحتوى (النصوص، التفاسير، قوالب الصور) يأتي من الـ Backend —
///   لا نصوص آيات ولا تفاسير مضمّنة في الكود.
///
/// الاعتماديات في pubspec (موجودة):
/// - cached_network_image (تخزين صور الصفحات مؤقتًا على القرص)
/// - http + path_provider (تحميل ملفات الخطوط عند أول استخدام وتخزينها —
///   راجع data/quran_font_loader.dart)
/// - share_plus (مشاركة الآيات)
class MushafReaderScreen extends StatefulWidget {
  const MushafReaderScreen({super.key, this.initialPage = 293, this.initialRiwayaId,
    this.initialVerseKey});
  final int initialPage;
  final String? initialRiwayaId;
  final String? initialVerseKey;

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> with WidgetsBindingObserver {
  final _configRepo = QuranConfigRepository();
  final _apiRepo = QuranApiRepository();
  final _mushafRepo = MushafRepository();
  final _stateRepo = QuranReadingStateRepository();
  final _progressRepo = ReadingProgressRepository();
  final _bookmarkRepo = MushafBookmarkRepository();

  late Future<_ReaderInit> _initFuture;
  PageController? _controller;
  final Map<int, Future<MushafPage>> _textPages = {};
  Future<void>? _topicSync;

  int _currentPage = 1;
  bool _dark = false;
  String? _currentVerseKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stateRepo.riwayaId().then((id) => _stateRepo.saveLocation(id,
        QuranLocation(page: _currentPage, verseKey: _currentVerseKey)));
    }
  }

  Future<_ReaderInit> _init() async {
    final config = await _configRepo.load();
    var riwayaId = widget.initialRiwayaId ?? await _stateRepo.riwayaId();
    Riwaya riwaya;
    try {
      riwaya = RiwayaRegistry.byId(riwayaId, config.riwayat);
    } catch (_) {
      // رجوع آمن إن تغيّرت قائمة الـ Backend بعد حفظ الاختيار.
      riwaya = config.riwayat.first;
      riwayaId = riwaya.id;
    }
    final font = _resolveFont(await _stateRepo.fontId(), riwaya, config.fonts);
    final fontSize = await _stateRepo.fontSize();
    // الخط يُحمَّل عند أول استخدام ويُخزَّن على القرص؛ null = خط النظام.
    final loadedFontFamily = await QuranFontLoader.ensureLoaded(font);
    // The two image modes retain their existing verified page sources.
    final riwayaEditions = MushafEditionRegistry.forRiwaya(riwaya.id, config.editions);
    MushafEdition? edition;
    if (riwayaEditions.isNotEmpty) {
      final savedId = await _stateRepo.mushafEditionId();
      final match = riwayaEditions.where((e) => e.id == savedId);
      edition = match.isNotEmpty ? match.first : riwayaEditions.first;
      if (!edition.supportsPages) edition = null;
    }
    var mode = await _stateRepo.readingMode();
    if (mode == QuranReadingMode.tajweed) {
      final tajweed = riwayaEditions.where((e) => e.id == 'hafs-madani-tajweed' && e.supportsPages);
      edition = tajweed.isEmpty ? null : tajweed.first;
    } else if (mode == QuranReadingMode.image) {
      final madani = riwayaEditions.where((e) => e.id == 'hafs-madani' && e.supportsPages);
      edition = madani.isEmpty ? null : madani.first;
    }
    if ((mode == QuranReadingMode.image || mode == QuranReadingMode.tajweed) && edition == null) {
      mode = QuranReadingMode.text;
    }
    final location = await _stateRepo.lastLocation(riwaya.id);
    var page = widget.initialVerseKey == null ?
        (location?.page ?? widget.initialPage) : widget.initialPage;
    _currentVerseKey = widget.initialVerseKey ?? location?.verseKey;
    final maxPage = mode == QuranReadingMode.image || mode == QuranReadingMode.tajweed
        ? (edition?.totalPages ?? QuranNavigation.quranFoundationTextPages)
        : QuranNavigation.quranFoundationTextPages;
    page = page.clamp(1, maxPage);
    _currentPage = page;
    _controller = PageController(initialPage: QuranNavigation.pageToIndex(page));
    return _ReaderInit(
      config: config,
      riwaya: riwaya,
      edition: edition,
      font: font,
      loadedFontFamily: loadedFontFamily,
      fontSize: fontSize,
      mode: mode,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _configRepo.dispose();
    _apiRepo.dispose();
    _mushafRepo.dispose();
    super.dispose();
  }

  /// الخط الفعلي للرواية: المحفوظ إن كان يدعمها، وإلا أول خط داعم
  /// من الإعدادات (الرواية تؤثر فعليًا على الخط المعروض).
  QuranFontOption _resolveFont(String fontId, Riwaya riwaya, List<QuranFontOption> fonts) {
    final saved = QuranFontRegistry.byId(fontId, fonts);
    if (saved.supportsRiwaya(riwaya.id)) return saved;
    return QuranFontRegistry.bestForRiwaya(riwaya.id, fonts);
  }

  Future<MushafPage> _loadTextPage(_ReaderInit init, int page) =>
      _textPages.putIfAbsent(page, () => _mushafRepo.page(riwaya: init.riwaya, page: page));

  Future<Map<String, List<QuranTopic>>> _loadTopics(MushafPage page) async {
    try {
      await (_topicSync ??= _mushafRepo.refreshTopicsIfNeeded());
    } catch (_) {
      _topicSync = Future<void>.value(); // Retain offline catalog; no network loop.
    }
    return _mushafRepo.topicsForPage(page);
  }

  void _retryTextPage(int page) => setState(() => _textPages.remove(page));

  void _onPageChanged(_ReaderInit init, int index) {
    final page = QuranNavigation.indexToPage(index);
    setState(() => _currentPage = page);
    _persistProgress(init, page);
  }

  Future<void> _persistProgress(_ReaderInit init, int page) async {
    try {
      if (page != _currentPage) return;
      await _stateRepo.saveLastPage(init.riwaya.id, page);
      String? surahName;
      int? surahNumber;
      String? ayahKey;
      if (page == _currentPage) {
        try {
          final pageData = await _loadTextPage(init, page);
          surahName = pageData.surahName;
          if (pageData.ayahs.isNotEmpty) {
            final first = pageData.ayahs.first;
            surahNumber = first.chapterId;
            ayahKey = first.key.isNotEmpty ? first.key : null;
            if (_currentVerseKey == null || _currentVerseKey != ayahKey) {
              _currentVerseKey = ayahKey;
            }
          }
        } catch (_) {/* best-effort */}
      }
      await _stateRepo.saveLocation(init.riwaya.id,
          QuranLocation(page: page, verseKey: _currentVerseKey));
      await _progressRepo.save(
        page: page,
        surahName: surahName,
        surahNumber: surahNumber,
        ayahKey: ayahKey,
        riwayaId: init.riwaya.id,
      );
    } catch (_) {
      // تجاهل هادئ: لا نعطّل القراءة بسبب فشل الحفظ.
    }
  }

  Future<void> _jumpToPage(_ReaderInit init, int page) async {
    final max = init.mode == QuranReadingMode.image || init.mode == QuranReadingMode.tajweed
        ? (init.edition?.totalPages ?? QuranNavigation.quranFoundationTextPages)
        : QuranNavigation.quranFoundationTextPages;
    final target = page.clamp(1, max);
    await _controller?.animateToPage(
      QuranNavigation.pageToIndex(target),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openSettings(_ReaderInit init) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => QuranSettingsSheet(
        riwayat: init.config.riwayat,
        editions: init.config.editions,
        fonts: init.config.fonts,
        stateRepository: _stateRepo,
        onChanged: () {},
      ),
    );
    if (!mounted) return;
    // إعادة التحميل لتطبيق الرواية/الخط/الوضع الجديد.
    setState(() {
      _textPages.clear();
      _controller?.dispose();
      _controller = null;
      _initFuture = _init();
    });
  }

  Future<void> _openGotoAyah(_ReaderInit init) async {
    final surahCtrl = TextEditingController();
    final ayahCtrl = TextEditingController();
    final result = await showDialog<({int chapter, int verse})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الانتقال إلى آية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: surahCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'رقم السورة (1-114)'),
            ),
            TextField(
              controller: ayahCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'رقم الآية'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              try {
                final chapter = int.parse(surahCtrl.text.trim());
                final verse = int.parse(ayahCtrl.text.trim());
                final parsed = QuranNavigation.parseAyahKey('$chapter:$verse');
                Navigator.pop(context, parsed);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تحقق من رقمي السورة والآية')),
                );
              }
            },
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      final page = await _apiRepo.lookupPage(chapter: result.chapter, verse: result.verse);
      _currentVerseKey = '${result.chapter}:${result.verse}';
      await _stateRepo.saveLocation(init.riwaya.id,
          QuranLocation(page: page, verseKey: _currentVerseKey));
      await _jumpToPage(init, page);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديد صفحة الآية')),
        );
      }
    }
  }

  Future<void> _showAyahActions(_ReaderInit init, MushafAyah ayah) async {
    _currentVerseKey = ayah.key;
    await _stateRepo.saveLocation(init.riwaya.id,
        QuranLocation(page: _currentPage, verseKey: ayah.key));
    final label = '﴿${ayah.text}﴾ [${ayah.key}]';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.topic_outlined),
            title: const Text('موضوعات الآية'),
            onTap: () {
              Navigator.pop(context);
              _showTopicDetails(init, ayah.key);
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('عرض التفسير'),
            onTap: () {
              Navigator.pop(context);
              _openTafsirSheet(init, ayah);
            },
          ),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: const Text('ترجمة معنى الآية'),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet<void>(
                context: this.context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(this.context).height * 0.65,
                  child: QuranTranslationSheet(verseKey: ayah.key),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('نسخ الآية بالتشكيل'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: label));
              if (context.mounted) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('مشاركة الآية'),
            onTap: () async {
              Navigator.pop(context);
              await Share.share(label, subject: 'آية من القرآن الكريم');
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: const Text('حفظ فاصلة على الآية'),
            onTap: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final already = await _bookmarkRepo.contains(ayah.key);
              if (already) {
                await _bookmarkRepo.remove(ayah.key, riwayaId: init.riwaya.id);
                messenger.showSnackBar(const SnackBar(content: Text('أُزيلت الفاصلة')));
              } else {
                await _bookmarkRepo.add(MushafBookmark(
                  ayahKey: ayah.key,
                  surahNumber: ayah.chapterId,
                  verseNumber: ayah.number,
                  page: _currentPage,
                  riwayaId: init.riwaya.id,
                ));
                messenger.showSnackBar(const SnackBar(content: Text('حُفظت الفاصلة على الآية')));
              }
              navigator.pop();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _showTopicDetails(_ReaderInit init, String verseKey) async {
    final topics = await _mushafRepo.topicsForVerse(verseKey);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('موضوعات الآية $verseKey', style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('تصنيف فهرسي من الموسوعة القرآنية، وليس جزءًا من نص المصحف.'),
          if (topics.isEmpty) const Text('لا توجد موضوعات محفوظة لهذه الآية.'),
          for (final topic in topics) ListTile(
            title: Text(topic.title),
            subtitle: const Text('الموسوعة القرآنية Quranpedia.net'),
            trailing: const Icon(Icons.arrow_back),
            onTap: () async {
              final keys = await _mushafRepo.versesForTopic(topic.id);
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              if (!mounted) return;
              await showModalBottomSheet<void>(context: context,
                builder: (context) => SafeArea(child: ListView(
                  children: [
                    ListTile(title: Text(topic.title), subtitle: Text('${keys.length} آيات مرتبطة')),
                    for (final key in keys.take(100)) ListTile(title: Text(key), onTap: () async {
                      Navigator.pop(context);
                      final parsed = QuranNavigation.parseAyahKey(key);
                      final page = await _apiRepo.lookupPage(chapter: parsed.chapter, verse: parsed.verse);
                      _currentVerseKey = key;
                      await _jumpToPage(init, page);
                    }),
                  ],
                )));
            },
          ),
        ]),
      )),
    );
  }

  Future<void> _searchTopics(_ReaderInit init) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (sheetContext) => SafeArea(child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: controller, autofocus: true,
            decoration: const InputDecoration(labelText: 'بحث في الموضوعات', prefixIcon: Icon(Icons.search))),
          SizedBox(height: 300, child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller, builder: (context, value, _) {
            return FutureBuilder<List<QuranTopic>>(
              future: _mushafRepo.searchTopics(value.text),
              builder: (context, snapshot) => ListView(children: [
                for (final topic in snapshot.data ?? const <QuranTopic>[])
                  ListTile(title: Text(topic.title), onTap: () async {
                    final keys = await _mushafRepo.versesForTopic(topic.id);
                    if (!sheetContext.mounted || keys.isEmpty) return;
                    Navigator.pop(sheetContext);
                    final parsed = QuranNavigation.parseAyahKey(keys.first);
                    final page = await _apiRepo.lookupPage(chapter: parsed.chapter, verse: parsed.verse);
                    _currentVerseKey = keys.first;
                    await _jumpToPage(init, page);
                  }),
              ]),
            );
          })),
        ]),
      )));
    controller.dispose();
  }

  Future<void> _openTafsirSheet(_ReaderInit init, MushafAyah ayah) async {
    final sourceId = await _stateRepo.tafsirSourceId();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TafsirSheet(
        ayahKey: ayah.key,
        ayahText: ayah.text,
        sources: init.config.tafsirs,
        initialSourceId: sourceId,
        api: _apiRepo,
        onSourceChanged: (id) => _stateRepo.saveTafsirSourceId(id),
      ),
    );
  }

  Future<void> _openBookmarks(_ReaderInit init) async {
    final bookmark = await showModalBottomSheet<MushafBookmark>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _BookmarksSheet(repository: _bookmarkRepo),
    );
    if (bookmark == null || !mounted) return;
    final page = bookmark.page;
    if (page == null || page < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الفاصلة قديمة ولا تحمل رقم الصفحة — احذفها وأعد حفظها')),
      );
      return;
    }
    // الانتقال للفاصلة قد يتطلب تبديل الرواية أولًا.
    if (bookmark.riwayaId != init.riwaya.id) {
      await _stateRepo.saveRiwayaId(bookmark.riwayaId);
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MushafReaderScreen(
          initialPage: page,
          initialRiwayaId: bookmark.riwayaId,
          initialVerseKey: bookmark.ayahKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReaderInit>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: SafeArea(child: _PageSkeleton()));
        }
        final init = snapshot.data;
        if (snapshot.hasError || init == null || _controller == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('المصحف الشريف')),
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('تعذّر تحميل إعدادات المصحف'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => setState(() => _initFuture = _init()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ]),
            ),
          );
        }
        final palette = _dark ? const _ReaderPalette.dark() : const _ReaderPalette.sepia();
        final maxPage = init.mode == QuranReadingMode.image || init.mode == QuranReadingMode.tajweed
            ? (init.edition?.totalPages ?? QuranNavigation.quranFoundationTextPages)
            : QuranNavigation.quranFoundationTextPages;
        return Theme(
          data: Theme.of(context).copyWith(scaffoldBackgroundColor: palette.canvas),
          child: Scaffold(
            body: SafeArea(
              child: Column(children: [
                _ReaderHeader(
                  page: _currentPage,
                  riwayaName: init.riwaya.nameAr,
                  pageFuture: _loadTextPage(init, _currentPage),
                  palette: palette,
                  onRiwayaPressed: () => _openSettings(init),
                ),
                Expanded(
                  child: init.mode == QuranReadingMode.image || init.mode == QuranReadingMode.tajweed
                      ? _ImagePageView(
                          key: ValueKey('image-${init.riwaya.id}-${init.edition?.id}'),
                          controller: _controller!,
                          edition: init.edition,
                          riwayaName: init.riwaya.nameAr,
                          palette: palette,
                          onPageChanged: (i) => _onPageChanged(init, i),
                        )
                      : _TextPageView(
                          key: ValueKey('text-${init.riwaya.id}'),
                          controller: _controller!,
                          init: init,
                          palette: palette,
                          thematic: init.mode == QuranReadingMode.thematic,
                          loadPage: (p) => _loadTextPage(init, p),
                          loadTopics: _loadTopics,
                          onPageChanged: (i) => _onPageChanged(init, i),
                          onRetry: _retryTextPage,
                          onAyahPressed: (a) => _showAyahActions(init, a),
                          onTopicPressed: (key) => _showTopicDetails(init, key),
                        ),
                ),
                _ReaderControls(
                  page: _currentPage,
                  maxPage: maxPage,
                  mode: init.mode,
                  dark: _dark,
                  onPageChanged: (p) => _jumpToPage(init, p),
                  onModeChanged: (m) async {
                    await _stateRepo.saveLocation(init.riwaya.id,
                        QuranLocation(page: _currentPage, verseKey: _currentVerseKey));
                    await _stateRepo.saveReadingMode(m);
                    if (mounted) {
                      setState(() {
                        _textPages.clear();
                        _controller?.dispose();
                        _controller = null;
                        _initFuture = _init();
                      });
                    }
                  },
                  onDarkChanged: () => setState(() => _dark = !_dark),
                  onTopicSearchPressed: () => _searchTopics(init),
                  onSettingsPressed: () => _openSettings(init),
                  onGotoPressed: () => _openGotoAyah(init),
                  onBookmarksPressed: () => _openBookmarks(init),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _ReaderInit {
  const _ReaderInit({
    required this.config,
    required this.riwaya,
    required this.edition,
    required this.font,
    required this.loadedFontFamily,
    required this.fontSize,
    required this.mode,
  });
  final QuranRuntimeConfig config;
  final Riwaya riwaya;

  /// إصدار المصحف المصوّر المختار؛ null عندما لا تتوفّر نسخة موثّقة
  /// للرواية (حينها يُجبَر الوضع على النص).
  final MushafEdition? edition;
  final QuranFontOption font;

  /// اسم عائلة الخط بعد تحميله من القرص/الشبكة؛ null = خط النظام.
  final String? loadedFontFamily;
  final double fontSize;
  final QuranReadingMode mode;
}

/// وضع المصحف المصوّر: صور عالية الدقة مع تخزين مؤقت، تكبير/تصغير، وترتيب RTL.
///
/// مصدر الصور هو إصدار المصحف المختار ([MushafEdition]) — عادي أو تجويد ملوّن —
/// لا قالب الرواية العام. تُبنى الصفحات كسولًا عبر PageView.builder ولا تُحمَّل
/// كل الصفحات في الذاكرة؛ التخزين المؤقت على القرص عبر CachedNetworkImage.
class _ImagePageView extends StatelessWidget {
  const _ImagePageView({
    super.key,
    required this.controller,
    required this.edition,
    required this.riwayaName,
    required this.palette,
    required this.onPageChanged,
  });

  final PageController controller;
  final MushafEdition? edition;
  final String riwayaName;
  final _ReaderPalette palette;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final edition = this.edition;
    if (edition == null || !edition.supportsPages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.image_not_supported_outlined, size: 56, color: palette.muted),
            const SizedBox(height: 12),
            Text(
              'المصحف المصوّر غير متوفّر لرواية «$riwayaName» بعد — لا توجد نسخة مصحف موثّقة بتخطيط 604 صفحات.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ]),
        ),
      );
    }
    final total = edition.totalPages;
    return PageView.builder(
      controller: controller,
      reverse: true, // ترتيب RTL: الصفحة الأولى يمينًا
      itemCount: total,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final page = QuranNavigation.indexToPage(index);
        return InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: edition.pageImageUrl(page),
              fit: BoxFit.contain,
              // دقة عالية مع حدّ أقصى معقول للذاكرة
              memCacheWidth: 1400,
              maxWidthDiskCache: 1600,
              placeholder: (context, url) => const _PageSkeleton(),
              errorWidget: (context, url, error) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.broken_image_outlined, size: 48, color: palette.muted),
                  const SizedBox(height: 8),
                  const Text('تعذّر تحميل الصفحة'),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// وضع النص: آيات بخطوط عثمانية قابلة للاختيار مع منع تداخل الحروف.
class _TextPageView extends StatelessWidget {
  const _TextPageView({
    super.key,
    required this.controller,
    required this.init,
    required this.palette,
    required this.thematic,
    required this.loadPage,
    required this.loadTopics,
    required this.onPageChanged,
    required this.onRetry,
    required this.onAyahPressed,
    required this.onTopicPressed,
  });

  final PageController controller;
  final _ReaderInit init;
  final _ReaderPalette palette;
  final bool thematic;
  final Future<MushafPage> Function(int page) loadPage;
  final Future<Map<String, List<QuranTopic>>> Function(MushafPage page) loadTopics;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRetry;
  final ValueChanged<MushafAyah> onAyahPressed;
  final ValueChanged<String> onTopicPressed;

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
              return const _PageSkeleton();
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
            return FutureBuilder<Map<String, List<QuranTopic>>>(
              future: thematic ? loadTopics(data) : null,
              builder: (context, topicsSnapshot) {
                final topics = topicsSnapshot.data ?? const <String, List<QuranTopic>>{};
                return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 12,
                      maxWidth: 620,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: palette.page,
                      border: Border.all(color: palette.gold, width: 2),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          // اسم السورة أعلى الصفحة عند تغيّرها
                          ..._surahHeaders(data),
                          ...data.ayahs.map(
                            (ayah) => InkWell(
                              onTap: () => onAyahPressed(ayah),
                              onLongPress: () => onAyahPressed(ayah),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                                decoration: thematic && (topics[ayah.key]?.isNotEmpty ?? false)
                                    ? BoxDecoration(
                                        color: (Theme.of(context).brightness == Brightness.dark
                                            ? Colors.teal.shade900 : Colors.teal.shade50),
                                        border: Border(bottom: BorderSide(color: Colors.teal.shade400, width: 2)),
                                      ) : null,
                                child: Text(
                                  '${ayah.text} ﴿${_arabicNumber(ayah.number)}﴾',
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    // الخط المحمَّل عند أول استخدام (null = خط النظام)،
                                    // مع ارتفاع سطر سخي لمنع تداخل الحروف والتشكيل.
                                    fontFamily: init.loadedFontFamily,
                                    fontSize: init.fontSize,
                                    height: init.font.lineHeight,
                                    color: palette.ink,
                                    // منع التفاف الكلمات العربية بشكل مكسور
                                    wordSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (thematic && topics.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                final first = data.ayahs.firstWhere(
                                  (ayah) => topics[ayah.key]?.isNotEmpty ?? false,
                                  orElse: () => data.ayahs.first,
                                );
                                onTopicPressed(first.key);
                              },
                              icon: const Icon(Icons.info_outline),
                              label: const Text('دليل الموضوعات ومصدرها'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  /// عناوين السور عند بدء سورة جديدة داخل الصفحة.
  List<Widget> _surahHeaders(MushafPage page) {
    final widgets = <Widget>[];
    var lastChapter = -1;
    for (final ayah in page.ayahs) {
      if (ayah.chapterId != lastChapter && ayah.number == 1) {
        lastChapter = ayah.chapterId;
        widgets.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: palette.gold),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'سورة ${page.surahName}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: init.loadedFontFamily,
              fontSize: init.fontSize + 2,
              height: init.font.lineHeight,
              fontWeight: FontWeight.bold,
              color: palette.ink,
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  static String _arabicNumber(int value) =>
      value.toString().split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.page,
    required this.riwayaName,
    required this.pageFuture,
    required this.palette,
    required this.onRiwayaPressed,
  });

  final int page;
  final String riwayaName;
  final Future<MushafPage>? pageFuture;
  final _ReaderPalette palette;
  final VoidCallback onRiwayaPressed;

  @override
  Widget build(BuildContext context) {
    final future = pageFuture;
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(
            child: future == null
                ? Text(riwayaName,
                    maxLines: 2, textAlign: TextAlign.start,
                    style: TextStyle(fontSize: 12, color: palette.muted))
                : FutureBuilder<MushafPage>(
                    future: future,
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      return Text(
                        'الجزء ${data?.juz ?? '—'}\nالحزب ${data?.hizb ?? '—'}',
                        maxLines: 2,
                        textAlign: TextAlign.start,
                        style: TextStyle(fontSize: 12, color: palette.muted),
                      );
                    },
                  ),
          ),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: onRiwayaPressed,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  'المصحف الشريف',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.ink),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(riwayaName, style: TextStyle(fontSize: 11, color: palette.muted)),
                  Icon(Icons.arrow_drop_down, size: 16, color: palette.muted),
                ]),
              ]),
            ),
          ),
          Expanded(
            child: Text(
              'صفحة $page',
              maxLines: 1,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.page,
    required this.maxPage,
    required this.mode,
    required this.dark,
    required this.onPageChanged,
    required this.onModeChanged,
    required this.onDarkChanged,
    required this.onTopicSearchPressed,
    required this.onSettingsPressed,
    required this.onGotoPressed,
    required this.onBookmarksPressed,
  });

  final int page;
  final int maxPage;
  final QuranReadingMode mode;
  final bool dark;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<QuranReadingMode> onModeChanged;
  final VoidCallback onDarkChanged;
  final VoidCallback onTopicSearchPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback onGotoPressed;
  final VoidCallback onBookmarksPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Slider(
            value: page.toDouble().clamp(1, maxPage.toDouble()),
            min: 1,
            max: maxPage.toDouble(),
            divisions: maxPage - 1,
            label: '$page',
            onChanged: (value) => onPageChanged(value.round()),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(
              tooltip: 'الوضع الليلي',
              onPressed: onDarkChanged,
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              tooltip: 'الفواصل',
              onPressed: onBookmarksPressed,
              icon: const Icon(Icons.bookmarks_outlined),
            ),
            IconButton(
              tooltip: 'الانتقال إلى آية',
              onPressed: onGotoPressed,
              icon: const Icon(Icons.search),
            ),
            PopupMenuButton<QuranReadingMode>(
              tooltip: 'نوع المصحف',
              icon: const Icon(Icons.menu_book_outlined),
              initialValue: mode,
              onSelected: onModeChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(value: QuranReadingMode.image, child: Text('مصحف المدينة')),
                PopupMenuItem(value: QuranReadingMode.tajweed, child: Text('التجويد')),
                PopupMenuItem(value: QuranReadingMode.thematic, child: Text('موضوعي')),
                PopupMenuItem(value: QuranReadingMode.text, child: Text('نص')),
              ],
            ),
            if (mode == QuranReadingMode.thematic)
              IconButton(tooltip: 'بحث في الموضوعات', onPressed: onTopicSearchPressed,
                icon: const Icon(Icons.topic_outlined)),
            IconButton(
              tooltip: 'الإعدادات',
              onPressed: onSettingsPressed,
              icon: const Icon(Icons.settings_outlined),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// ورقة التفسير: اختيار المصدر ثم عرض النص من الـ Backend.
class _TafsirSheet extends StatefulWidget {
  const _TafsirSheet({
    required this.ayahKey,
    required this.ayahText,
    required this.sources,
    required this.initialSourceId,
    required this.api,
    required this.onSourceChanged,
  });

  final String ayahKey;
  final String ayahText;
  final List<TafsirSource> sources;
  final int initialSourceId;
  final QuranApiRepository api;
  final ValueChanged<int> onSourceChanged;

  @override
  State<_TafsirSheet> createState() => _TafsirSheetState();
}

class _TafsirSheetState extends State<_TafsirSheet> {
  late int _sourceId;
  late Future<TafsirEntry> _future;
  late final TafsirCacheRepository _cacheRepo =
      TafsirCacheRepository(api: widget.api);

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId;
    _future = _load();
  }

  TafsirSource get _source => widget.sources.firstWhere(
        (s) => s.resourceId == _sourceId,
        orElse: () => widget.sources.first,
      );

  Future<TafsirEntry> _load() => _cacheRepo.get(source: _source, ayahKey: widget.ayahKey);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('التفسير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('الآية ${widget.ayahKey}', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.sources.map((s) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(s.nameAr),
                    selected: s.resourceId == _sourceId,
                    onSelected: (_) {
                      setState(() {
                        _sourceId = s.resourceId;
                        _future = _load();
                      });
                      widget.onSourceChanged(s.resourceId);
                    },
                  ),
                )).toList(),
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: FutureBuilder<TafsirEntry>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entry = snapshot.data;
                  if (snapshot.hasError || entry == null || entry.plainText.isEmpty) {
                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.menu_book_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        const Text('تعذّر تحميل التفسير من المصدر المحدد'),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => setState(() => _future = _load()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ]),
                    );
                  }
                  return SingleChildScrollView(
                    controller: scrollController,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.ayahText,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontSize: 18, height: 2.0),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        entry.plainText,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 16, height: 1.9),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'المصدر: ${entry.sourceNameAr} — عبر Quran Foundation',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ورقة الفواصل: قائمة الفواصل المحفوظة مع الانتقال والحذف.
/// حالة فارغة صادقة عند عدم وجود فواصل.
class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({required this.repository});

  final MushafBookmarkRepository repository;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  late Future<List<MushafBookmark>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.list();
  }

  Future<void> _delete(MushafBookmark bookmark) async {
    await widget.repository.remove(bookmark.ayahKey, riwayaId: bookmark.riwayaId);
    if (mounted) setState(() => _future = widget.repository.list());
  }

  static String _riwayaLabel(String id) {
    try {
      return RiwayaRegistry.byId(id).nameAr;
    } catch (_) {
      return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('الفواصل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<MushafBookmark>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('لا توجد فواصل بعد'),
                        SizedBox(height: 4),
                        Text(
                          'اضغط على أي آية ثم «حفظ فاصلة على الآية»',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ]),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bookmark = items[index];
                      final pageLabel = bookmark.page == null
                          ? 'صفحة غير مسجلة'
                          : 'صفحة ${bookmark.page}';
                      return ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: Text(
                          'سورة ${bookmark.surahNumber} • آية ${bookmark.verseNumber}',
                          textDirection: TextDirection.rtl,
                        ),
                        subtitle: Text('$pageLabel • ${_riwayaLabel(bookmark.riwayaId)}'),
                        trailing: IconButton(
                          tooltip: 'حذف الفاصلة',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(bookmark),
                        ),
                        onTap: () => Navigator.of(context).pop(bookmark),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ReaderPalette {
  const _ReaderPalette.sepia()
      : canvas = const Color(0xFFF3EAD7),
        page = const Color(0xFFFFFCF3),
        ink = const Color(0xFF1D2A24),
        muted = const Color(0xFF675C4A),
        gold = const Color(0xFFAA7A2D);
  const _ReaderPalette.dark()
      : canvas = const Color(0xFF111714),
        page = const Color(0xFF1C2520),
        ink = const Color(0xFFF0E7D2),
        muted = const Color(0xFFB7AD98),
        gold = const Color(0xFFC8A45C);
  final Color canvas;
  final Color page;
  final Color ink;
  final Color muted;
  final Color gold;
}

/// هيكل تحميل لصفحة المصحف — أسطر نابضة تحاكي صفحة النص أثناء الجلب،
/// بدل مؤشر التحميل الدوّار العام.
class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const SkeletonBox(width: 180, height: 22),
              SizedBox(height: 20),
              for (var i = 0; i < 10; i++) ...[
                SkeletonBox(height: 16),
                SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
