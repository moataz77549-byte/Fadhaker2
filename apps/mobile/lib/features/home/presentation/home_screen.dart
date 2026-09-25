import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/models/app_models.dart';
import '../../../core/services/prayer_times_service.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/hijri_date.dart';
import '../../../core/widgets/skeleton.dart';
import '../../daily_hadith/data/daily_hadith_repository.dart';
import '../../quran/presentation/mushaf_reader_screen.dart';
import '../data/reading_progress_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<PrayerTimesModel> _prayerTimes;
  late Future<ReadingProgress?> _readingProgress;
  final _progressRepository = ReadingProgressRepository();

  @override
  void initState() {
    super.initState();
    _prayerTimes = prayerTimesService.loadToday();
    _readingProgress = _progressRepository.load();
  }

  void _reloadPrayerTimes() {
    setState(() => _prayerTimes = prayerTimesService.loadToday());
  }

  void _reloadReadingProgress() {
    setState(() => _readingProgress = _progressRepository.load());
  }

  Future<void> _refresh() async {
    setState(() {
      _prayerTimes = prayerTimesService.loadToday();
      _readingProgress = _progressRepository.load();
    });
    await Future.wait<void>([
      _prayerTimes.then<void>((_) {}).catchError((_) {}),
      _readingProgress.then<void>((_) {}).catchError((_) {}),
    ]);
  }

  Future<void> _openReader({int? page}) async {
    final progress = await _progressRepository.load();
    final target = page ?? progress?.page ?? 1;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MushafReaderScreen(
          initialPage: target,
          initialRiwayaId: progress?.riwayaId,
        ),
      ),
    );
    _reloadReadingProgress();
  }

  Future<void> _chooseManualLocation() async {
    final cityController = TextEditingController();
    final countryController = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختيار المدينة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cityController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'المدينة'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: countryController,
              decoration: const InputDecoration(labelText: 'الدولة (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ('__clear__', '')),
            child: const Text('موقع الجهاز'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (cityController.text, countryController.text),
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    cityController.dispose();
    countryController.dispose();
    if (result == null || !mounted) return;

    if (result.$1.trim() == '__clear__') {
      await prayerTimesService.clearManualLocation();
      _reloadPrayerTimes();
      return;
    }
    if (result.$1.trim().isEmpty) return;

    try {
      await prayerTimesService.saveManualLocation(
        city: result.$1,
        country: result.$2,
      );
      _reloadPrayerTimes();
    } on PrayerTimesException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(prayerErrorArabicMessage(error.message))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final hijri = HijriDate.today();
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          'السلام عليكم',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      Text(
                        '${today.day}/${today.month}/${today.year}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hijri.formatApproximate(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 18),
                  _WirdCard(
                    progress: _readingProgress,
                    onOpenReader: _openReader,
                  ),
                  const SizedBox(height: 12),
                  _PrayerCard(
                    prayerTimes: _prayerTimes,
                    onChooseLocation: _chooseManualLocation,
                    onRetry: _reloadPrayerTimes,
                  ),
                  const SizedBox(height: 12),
                  const _DailyHadithPreview(),
                  const SizedBox(height: 22),
                  Text(
                    'وصول سريع',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildListDelegate(
                [
                  _ServiceTile(
                    icon: Icons.menu_book_rounded,
                    title: 'المصحف',
                    value: 'القراءة والمتابعة',
                    onTap: () => Navigator.of(context).pushNamed('/quran'),
                  ),
                  _ServiceTile(
                    icon: Icons.headphones_rounded,
                    title: 'الاستماع',
                    value: 'قراء وإذاعات',
                    onTap: () => Navigator.of(context).pushNamed('/listen'),
                  ),
                  _ServiceTile(
                    icon: Icons.brightness_low_rounded,
                    title: 'الأذكار',
                    value: 'حصن المسلم',
                    onTap: () => Navigator.of(context).pushNamed('/adhkar'),
                  ),
                  _ServiceTile(
                    icon: Icons.school_rounded,
                    title: 'الحفظ',
                    value: 'خطة ومراجعة',
                    onTap: () => Navigator.of(context).pushNamed('/learning'),
                  ),
                  _ServiceTile(
                    icon: Icons.touch_app_rounded,
                    title: 'السبحة',
                    value: 'عدادات محفوظة',
                    onTap: () => Navigator.of(context).pushNamed('/tasbih'),
                  ),
                  _ServiceTile(
                    icon: Icons.track_changes_rounded,
                    title: 'الختمة',
                    value: 'متابعة التقدم',
                    onTap: () => Navigator.of(context).pushNamed('/khatma'),
                  ),
                ],
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 118,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _DailyHadithPreview extends ConsumerWidget {
  const _DailyHadithPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hadith = ref.watch(dailyHadithProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).pushNamed('/daily-hadith'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.format_quote_rounded,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'حديث اليوم',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                hadith.title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.secondary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '«${hadith.text}»',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WirdCard extends StatelessWidget {
  const _WirdCard({
    required this.progress,
    required this.onOpenReader,
  });

  final Future<ReadingProgress?> progress;
  final Future<void> Function({int? page}) onOpenReader;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<ReadingProgress?>(
      future: progress,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SkeletonCard(height: 150);
        }

        final data = snapshot.data;
        final title = data == null
            ? 'ابدأ وردك اليومي'
            : 'متابعة القراءة${data.surahName == null ? '' : ' • ${data.surahName}'}';
        final subtitle = data == null
            ? 'افتح المصحف وابدأ من أي صفحة'
            : 'آخر موضع محفوظ: الصفحة ${data.page}';

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.primaryContainer],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () => onOpenReader(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: scheme.onPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      color: scheme.onPrimary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'وردك اليومي',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: scheme.onPrimary.withValues(alpha: 0.8),
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.onPrimary,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        scheme.onPrimary.withValues(alpha: 0.78),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_back_rounded, color: scheme.onPrimary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({
    required this.prayerTimes,
    required this.onChooseLocation,
    required this.onRetry,
  });

  final Future<PrayerTimesModel> prayerTimes;
  final VoidCallback onChooseLocation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<PrayerTimesModel>(
          future: prayerTimes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonCard(height: 150);
            }

            if (snapshot.hasError) {
              final code = snapshot.error is PrayerTimesException
                  ? (snapshot.error as PrayerTimesException).message
                  : snapshot.error.toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مواقيت الصلاة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(prayerErrorArabicMessage(code)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (code == 'location_permission_denied_forever')
                        OutlinedButton.icon(
                          onPressed: Geolocator.openAppSettings,
                          icon: const Icon(Icons.settings_rounded),
                          label: const Text('إعدادات التطبيق'),
                        ),
                      if (code == 'location_service_disabled')
                        OutlinedButton.icon(
                          onPressed: Geolocator.openLocationSettings,
                          icon: const Icon(Icons.location_on_rounded),
                          label: const Text('تشغيل الموقع'),
                        ),
                      OutlinedButton.icon(
                        onPressed: onChooseLocation,
                        icon: const Icon(Icons.location_city_rounded),
                        label: const Text('اختيار مدينة'),
                      ),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ],
              );
            }

            final model = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mosque_rounded, color: scheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مواقيت الصلاة • ${model.city}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'تغيير الموقع',
                      onPressed: onChooseLocation,
                      icon: const Icon(Icons.edit_location_alt_outlined),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${model.nextPrayerName} بعد ${model.nextPrayerRemaining}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                  ),
                ),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    _PrayerTimeItem('الفجر', model.fajr),
                    _PrayerTimeItem('الظهر', model.dhuhr),
                    _PrayerTimeItem('العصر', model.asr),
                    _PrayerTimeItem('المغرب', model.maghrib),
                    _PrayerTimeItem('العشاء', model.isha),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PrayerTimeItem extends StatelessWidget {
  const _PrayerTimeItem(this.name, this.time);

  final String name;
  final String time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 2),
        Text(time, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: () async {
          await AppHaptics.lightTap();
          onTap();
        },
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.secondary),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
