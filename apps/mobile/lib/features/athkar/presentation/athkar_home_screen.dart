import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/athkar_repository.dart';
import '../domain/athkar_models.dart';
import '../../tasbih/presentation/tasbih_screen.dart';
import 'athkar_chapter_screen.dart';

class AthkarHomeScreen extends ConsumerStatefulWidget {
  const AthkarHomeScreen({super.key});

  @override
  ConsumerState<AthkarHomeScreen> createState() => _AthkarHomeScreenState();
}

class _AthkarHomeScreenState extends ConsumerState<AthkarHomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(athkarLibraryProvider);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: libraryAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('جارٍ تحميل الأذكار...'),
          ),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'تعذّر تحميل الأذكار: $error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        data: (library) {
          final results = _query.trim().isEmpty
              ? const <AthkarChapter>[]
              : library.search(_query);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              TextField(
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'ابحث في الأذكار والأدعية',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              _TasbihCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TasbihScreen()),
                ),
              ),
              const SizedBox(height: 20),
              if (results.isNotEmpty) ...[
                Text('نتائج البحث (${results.length})',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...results.map((chapter) => _ChapterTile(chapter: chapter)),
              ] else
                ...library.groups.map(
                  (group) => _GroupSection(group: group),
                ),
              const SizedBox(height: 24),
              if (library.source.isNotEmpty)
                Text(
                  'المصدر: ${library.source}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group});

  final AthkarGroup group;

  @override
  Widget build(BuildContext context) {
    if (group.chapters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: group.id == 'seasonal' ||
              group.id == 'morning_evening',
          title: Text(
            group.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${group.chapters.length} باب'),
          children: group.chapters
              .map((chapter) => _ChapterTile(chapter: chapter))
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter});

  final AthkarChapter chapter;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.auto_stories_outlined),
      title: Text(chapter.title),
      subtitle: Text('${chapter.items.length} ذكر'),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AthkarChapterScreen(chapter: chapter),
        ),
      ),
    );
  }
}

class _TasbihCard extends StatelessWidget {
  const _TasbihCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.primaryContainer],
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app, color: scheme.onPrimary, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'السبحة التفاعلية',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'عدّاد يحفظ تقدّمك ويهتز عند كل تسبيحة',
                    style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
