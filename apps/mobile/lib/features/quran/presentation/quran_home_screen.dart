import 'package:flutter/material.dart';

import '../../home/data/reading_progress_repository.dart';
import '../data/surah_metadata.dart';
import 'mushaf_reader_screen.dart';

class QuranHomeScreen extends StatefulWidget {
  const QuranHomeScreen({super.key});

  @override
  State<QuranHomeScreen> createState() => _QuranHomeScreenState();
}

class _QuranHomeScreenState extends State<QuranHomeScreen> {
  String _query = '';

  String _normalize(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needle = _normalize(_query);
    final surahs = needle.isEmpty
        ? allSurahs
        : allSurahs
            .where(
              (surah) =>
                  _normalize(surah.displayName).contains(needle) ||
                  surah.number.toString() == needle,
            )
            .toList(growable: false);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                Text(
                  'القرآن الكريم',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'فهرس كامل للسور مع متابعة آخر موضع قراءة.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                const _LastPositionCard(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.headphones_rounded,
                        title: 'الاستماع',
                        subtitle: 'اختر القارئ',
                        onTap: () => Navigator.of(context).pushNamed('/reciters'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.download_for_offline_rounded,
                        title: 'التنزيلات',
                        subtitle: 'دون اتصال',
                        onTap: () => Navigator.of(context).pushNamed('/library'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'ابحث باسم السورة أو رقمها',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'فهرس السور',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Text(
                      '${surahs.length} سورة',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        if (surahs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'لا توجد سورة مطابقة للبحث',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: surahs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final surah = surahs[index];
                return _SurahTile(surah: surah);
              },
            ),
          ),
      ],
    );
  }
}

class _LastPositionCard extends StatelessWidget {
  const _LastPositionCard();

  @override
  Widget build(BuildContext context) {
    final progressRepository = ReadingProgressRepository();
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<ReadingProgress?>(
      future: progressRepository.load(),
      builder: (context, snapshot) {
        final progress = snapshot.data;
        final hasProgress = progress != null;
        final page = progress?.page ?? 1;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.primaryContainer],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MushafReaderScreen(
                  initialPage: page,
                  initialRiwayaId: progress?.riwayaId,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
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
                        hasProgress ? 'متابعة القراءة' : 'ابدأ قراءة المصحف',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasProgress
                            ? '${progress.surahName ?? 'المصحف'} • الصفحة $page'
                            : 'من الصفحة الأولى',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimary.withValues(alpha: 0.82),
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_back_rounded, color: scheme.onPrimary),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: scheme.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurahTile extends StatelessWidget {
  const _SurahTile({required this.surah});
  final SurahMeta surah;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startPage = startPageForSurah(surah.number);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '${surah.number}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
          ),
        ),
        title: Text(surah.displayName),
        subtitle: Text(
          '${surah.ayahs} آية • ${surah.revelationType} • ص $startPage',
        ),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MushafReaderScreen(initialPage: startPage),
          ),
        ),
      ),
    );
  }
}
