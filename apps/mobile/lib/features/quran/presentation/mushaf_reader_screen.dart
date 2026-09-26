import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/audio_playback_service.dart';
import '../../home/data/reading_progress_repository.dart';
import '../data/mushaf_bookmark_repository.dart';
import '../data/mushaf_repository.dart';
import '../data/quran_api_repository.dart';
import '../data/quran_config_repository.dart';
import '../data/quran_font_loader.dart';
import '../data/quran_reading_state_repository.dart';
import '../data/quran_topic_repository.dart';
import '../data/tafsir_cache_repository.dart';
import '../domain/mushaf_edition.dart';
import '../domain/quran_audio.dart';
import '../domain/mushaf_page.dart';
import '../domain/quran_font.dart';
import '../domain/quran_navigation.dart';
import '../domain/quran_location.dart';
import '../domain/riwaya.dart';
import '../domain/tafsir_source.dart';
import '../../../core/widgets/skeleton.dart';
import 'quran_search_sheet.dart';
import 'quran_settings_sheet.dart';
import 'quran_unified_page_view.dart';
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
class MushafReaderScreen extends ConsumerStatefulWidget {
  const MushafReaderScreen({super.key, this.initialPage = 293, this.initialRiwayaId});
  final int initialPage;
  final String? initialRiwayaId;

  @override
  ConsumerState<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends ConsumerState<MushafReaderScreen>
    with WidgetsBindingObserver {
  final _configRepo = QuranConfigRepository();
  final _apiRepo = QuranApiRepository();
  final _mushafRepo = MushafRepository();
  final _stateRepo = QuranReadingStateRepository();
  final _progressRepo = ReadingProgressRepository();
  final _bookmarkRepo = MushafBookmarkRepository();
  final _topicRepo = QuranTopicRepository();

  // مسارات رجوع مؤقتة خلال فترة التحقق. لا تُفعّل في الإنتاج افتراضيًا.
  static const _legacyImageRenderer = bool.fromEnvironment(
    'QURAN_LEGACY_IMAGE_RENDERER',
    defaultValue: false,
  );
  static const _legacyTextRenderer = bool.fromEnvironment(
    'QURAN_LEGACY_TEXT_RENDERER',
    defaultValue: false,
  );

  late Future<_ReaderInit> _initFuture;
  PageController? _controller;
  final Map<int, Future<MushafPage>> _textPages = {};
  List<QuranRecitation>? _recitations;
  _ReaderInit? _activeInit;

  int _currentPage = 1;
  String? _currentVerseKey;
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final init = _activeInit;
      if (init != null) {
        unawaited(_persistProgress(init, _currentPage));
      }
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
    // إصدار المصحف المصوّر (عادي/تجويد ملوّن) — يجب أن يتبع الرواية المختارة.
    final riwayaEditions = MushafEditionRegistry.forRiwaya(riwaya.id, config.editions);
    MushafEdition? edition;
    if (riwayaEditions.isNotEmpty) {
      final savedId = await _stateRepo.mushafEditionId();
      final match = riwayaEditions.where((e) => e.id == savedId);
      edition = match.isNotEmpty ? match.first : riwayaEditions.first;
      if (!edition.supportsPages) edition = null;
    }
    final mode = await _stateRepo.readingMode();
    final savedLocation = await _stateRepo.lastLocation(riwaya.id);
    final savedPage = savedLocation?.pageNumber ?? await _stateRepo.lastPage(riwaya.id);
    var page = savedPage ?? widget.initialPage;
    page = page.clamp(1, QuranNavigation.quranFoundationTextPages);
    _currentPage = page;
    _currentVerseKey = savedLocation?.verseKey;
    _controller = PageController(initialPage: QuranNavigation.pageToIndex(page));
    final result = _ReaderInit(
      config: config,
      riwaya: riwaya,
      edition: edition,
      font: font,
      loadedFontFamily: loadedFontFamily,
      fontSize: fontSize,
      mode: mode,
    );
    _activeInit = result;
    return result;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final init = _activeInit;
    if (init != null) {
      final key = _currentVerseKey;
      if (key != null) {
        try {
          final parsed = QuranNavigation.parseAyahKey(key);
          unawaited(
            _stateRepo.saveLastLocation(
              init.riwaya.id,
              QuranLocation(
                pageNumber: _currentPage,
                surahNumber: parsed.chapter,
                ayahNumber: parsed.verse,
                verseKey: key,
              ),
            ),
          );
        } catch (_) {
          unawaited(_stateRepo.saveLastPage(init.riwaya.id, _currentPage));
        }
      } else {
        unawaited(_stateRepo.saveLastPage(init.riwaya.id, _currentPage));
      }
    }
    _controller?.dispose();
    _configRepo.dispose();
    _apiRepo.dispose();
    _mushafRepo.dispose();
    unawaited(_topicRepo.dispose());
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

  void _retryTextPage(int page) => setState(() => _textPages.remove(page));

  void _prefetchAdjacent(_ReaderInit init, int page) {
    _textPages.removeWhere((cachedPage, _) => (cachedPage - page).abs() > 2);
    for (final candidate in [page - 1, page + 1]) {
      if (candidate >= 1 && candidate <= QuranNavigation.quranFoundationTextPages) {
        unawaited(_loadTextPage(init, candidate));
      }
    }
  }

  Future<void> _openVerseKey(_ReaderInit init, String verseKey) async {
    try {
      final parsed = QuranNavigation.parseAyahKey(verseKey);
      final page = await _apiRepo.lookupPage(
        chapter: parsed.chapter,
        verse: parsed.verse,
      );
      if (!mounted) return;
      setState(() => _currentVerseKey = verseKey);
      await _jumpToPage(init, page);
      await _persistProgress(init, page);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الانتقال إلى الآية المطلوبة')),
        );
      }
    }
  }

  void _onPageChanged(_ReaderInit init, int index) {
    final page = QuranNavigation.indexToPage(index);
    setState(() {
      _currentPage = page;
      _currentVerseKey = null;
    });
    _prefetchAdjacent(init, page);
    unawaited(_persistProgress(init, page));
  }

  Future<void> _persistProgress(_ReaderInit init, int page) async {
    try {
      final pageData = await _loadTextPage(init, page);
      MushafAyah? current;
      final wanted = _currentVerseKey;
      if (wanted != null) {
        for (final ayah in pageData.ayahs) {
          if (ayah.key == wanted) {
            current = ayah;
            break;
          }
        }
      }
      current ??= pageData.ayahs.isEmpty ? null : pageData.ayahs.first;
      if (current != null) {
        final location = QuranLocation(
          pageNumber: page,
          surahNumber: current.chapterId,
          ayahNumber: current.number,
          verseKey: current.key,
        );
        await _stateRepo.saveLastLocation(init.riwaya.id, location);
      } else {
        await _stateRepo.saveLastPage(init.riwaya.id, page);
      }
      await _progressRepo.save(
        page: page,
        surahName: pageData.surahName,
        surahNumber: current?.chapterId,
        ayahKey: current?.key,
        riwayaId: init.riwaya.id,
      );
    } catch (_) {
      // القراءة لا تتعطل بسبب فشل حفظ الموضع.
      await _stateRepo.saveLastPage(init.riwaya.id, page);
    }
  }

  Future<void> _jumpToPage(_ReaderInit init, int page) async {
    final target = page.clamp(1, QuranNavigation.quranFoundationTextPages);
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
    final selection = await showModalBottomSheet<QuranSearchSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuranSearchSheet(
        api: _apiRepo,
        topicRepository: _topicRepo,
      ),
    );
    if (selection == null || !mounted) return;
    try {
      var page = selection.pageNumber;
      final key = selection.verseKey;
      if (page == null && key != null) {
        final parsed = QuranNavigation.parseAyahKey(key);
        page = await _apiRepo.lookupPage(
          chapter: parsed.chapter,
          verse: parsed.verse,
        );
      }
      if (page == null) return;
      setState(() => _currentVerseKey = key);
      await _jumpToPage(init, page);
      await _persistProgress(init, page);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديد موضع نتيجة البحث')),
        );
      }
    }
  }

  Future<QuranRecitation?> _resolveRecitation({
    bool forcePicker = false,
  }) async {
    var recitations = _recitations;
    if (recitations == null) {
      try {
        recitations = await _apiRepo.recitations();
        _recitations = recitations;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذّر تحميل قائمة القراء الآن')),
          );
        }
        return null;
      }
    }
    if (recitations.isEmpty) return null;

    final saved = await _stateRepo.preferredReciter();
    final savedId = saved != null && saved.startsWith('qf:')
        ? int.tryParse(saved.substring(3))
        : null;
    if (!forcePicker && savedId != null) {
      for (final item in recitations) {
        if (item.id == savedId) return item;
      }
    }

    if (!mounted) return null;
    final picked = await showModalBottomSheet<QuranRecitation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, controller) => Column(
            children: [
              const Text(
                'اختر قارئًا للآيات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'القائمة من Quran Foundation — تلاوات آية بآية',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: recitations!.length,
                  itemBuilder: (context, index) {
                    final item = recitations![index];
                    return ListTile(
                      leading: const Icon(Icons.record_voice_over_outlined),
                      title: Text(item.nameAr),
                      subtitle: item.style == null ? null : Text(item.style!),
                      trailing: item.id == savedId
                          ? const Icon(Icons.check_circle_outline)
                          : null,
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await _stateRepo.savePreferredReciter('qf:${picked.id}');
    }
    return picked;
  }

  Future<void> _playAyahAudio(
    _ReaderInit init,
    MushafAyah ayah, {
    bool fromHere = false,
    bool chooseReciter = false,
  }) async {
    final recitation =
        await _resolveRecitation(forcePicker: chooseReciter);
    if (recitation == null || !mounted) return;

    try {
      final page = await _loadTextPage(init, _currentPage);
      final title = 'سورة ${page.surahName} • الآية ${ayah.key}';
      final player = ref.read(audioPlaybackProvider.notifier);
      if (fromHere) {
        final queue = await _apiRepo.audioFromAyah(
          verseKey: ayah.key,
          recitationId: recitation.id,
        );
        if (queue.isEmpty) throw StateError('Empty Quran audio queue');
        await player.playQuranQueue(
          'سورة ${page.surahName} • من الآية ${ayah.key}',
          recitation.nameAr,
          queue.map((item) => item.audioUrl).toList(growable: false),
        );
      } else {
        final audio = await _apiRepo.ayahAudio(
          verseKey: ayah.key,
          recitationId: recitation.id,
        );
        await player.playQuranTrack(
          title,
          recitation.nameAr,
          audio.audioUrl,
          duration: audio.duration,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fromHere
                  ? 'بدأ التشغيل من الآية ${ayah.key}'
                  : 'بدأ تشغيل الآية ${ayah.key}',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تشغيل التلاوة الآن')),
        );
      }
    }
  }

  Future<void> _showAyahActions(_ReaderInit init, MushafAyah ayah) async {
    setState(() => _currentVerseKey = ayah.key);
    unawaited(_persistProgress(init, _currentPage));
    final label = '﴿${ayah.text}﴾ [${ayah.key}]';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('تشغيل هذه الآية'),
            onTap: () {
              Navigator.pop(context);
              unawaited(_playAyahAudio(init, ayah));
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_outlined),
            title: const Text('تشغيل من هذه الآية'),
            subtitle: const Text('حتى نهاية السورة بالتلاوة آيةً آية'),
            onTap: () {
              Navigator.pop(context);
              unawaited(_playAyahAudio(init, ayah, fromHere: true));
            },
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('اختيار قارئ وتشغيل الآية'),
            onTap: () {
              Navigator.pop(context);
              unawaited(_playAyahAudio(init, ayah, chooseReciter: true));
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
        const maxPage = QuranNavigation.quranFoundationTextPages;
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
                  child: _legacyImageRenderer &&
                          init.mode == QuranReadingMode.madani &&
                          init.edition != null
                      ? _ImagePageView(
                          key: ValueKey('legacy-image-${init.riwaya.id}-${init.edition?.id}'),
                          controller: _controller!,
                          edition: init.edition,
                          riwayaName: init.riwaya.nameAr,
                          palette: palette,
                          onPageChanged: (i) => _onPageChanged(init, i),
                        )
                      : _legacyTextRenderer
                          ? _TextPageView(
                              key: ValueKey('legacy-text-${init.riwaya.id}'),
                              controller: _controller!,
                              init: init,
                              palette: palette,
                              tajweed: init.mode == QuranReadingMode.tajweed,
                              loadPage: (p) => _loadTextPage(init, p),
                              onPageChanged: (i) => _onPageChanged(init, i),
                              onRetry: _retryTextPage,
                              onAyahPressed: (a) => _showAyahActions(init, a),
                            )
                          : QuranUnifiedPageView(
                              key: ValueKey(
                                'unified-${init.riwaya.id}-${init.mode.name}',
                              ),
                              controller: _controller!,
                              mode: init.mode,
                              dark: _dark,
                              pageColor: palette.page,
                              inkColor: palette.ink,
                              goldColor: palette.gold,
                              mutedColor: palette.muted,
                              fontFamily: init.loadedFontFamily,
                              fontSize: init.fontSize,
                              lineHeight: init.font.lineHeight,
                              loadPage: (p) => _loadTextPage(init, p),
                              onPageChanged: (i) => _onPageChanged(init, i),
                              onRetry: _retryTextPage,
                              onAyahPressed: (a) => _showAyahActions(init, a),
                              onVerseKeyRequested: (key) => _openVerseKey(init, key),
                              topicRepository: _topicRepo,
                            ),
                ),
                _ReaderControls(
                  page: _currentPage,
                  maxPage: maxPage,
                  mode: init.mode,
                  dark: _dark,
                  onPageChanged: (p) => _jumpToPage(init, p),
                  onModeChanged: (m) async {
                    await _persistProgress(init, _currentPage);
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
    required this.tajweed,
    required this.loadPage,
    required this.onPageChanged,
    required this.onRetry,
    required this.onAyahPressed,
  });

  final PageController controller;
  final _ReaderInit init;
  final _ReaderPalette palette;
  final bool tajweed;
  final Future<MushafPage> Function(int page) loadPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRetry;
  final ValueChanged<MushafAyah> onAyahPressed;

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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                                child: Text(
                                  '${_clean(tajweed ? ayah.tajweedText : ayah.text)} ﴿${_arabicNumber(ayah.number)}﴾',
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

  static String _clean(String input) => input.replaceAll(RegExp(r'<[^>]+>'), '');

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
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
                tooltip: 'البحث والتنقل',
                onPressed: onGotoPressed,
                icon: const Icon(Icons.search),
              ),
              PopupMenuButton<QuranReadingMode>(
                tooltip: 'نوع عرض المصحف',
                initialValue: mode,
                onSelected: onModeChanged,
                itemBuilder: (context) => [
                  for (final value in QuranReadingMode.values)
                    PopupMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(_modeIcon(value), size: 19),
                          const SizedBox(width: 10),
                          Text(_modeLabel(value)),
                        ],
                      ),
                    ),
                ],
                child: Chip(
                  avatar: Icon(_modeIcon(mode), size: 17),
                  label: Text(_modeLabel(mode)),
                ),
              ),
              IconButton(
                tooltip: 'الإعدادات',
                onPressed: onSettingsPressed,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  static String _modeLabel(QuranReadingMode mode) => switch (mode) {
        QuranReadingMode.madani => 'المدينة',
        QuranReadingMode.tajweed => 'التجويد',
        QuranReadingMode.thematic => 'موضوعي',
        QuranReadingMode.text => 'نص',
      };

  static IconData _modeIcon(QuranReadingMode mode) => switch (mode) {
        QuranReadingMode.madani => Icons.menu_book_rounded,
        QuranReadingMode.tajweed => Icons.palette_outlined,
        QuranReadingMode.thematic => Icons.layers_outlined,
        QuranReadingMode.text => Icons.text_fields,
      };
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
