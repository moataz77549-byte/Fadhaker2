import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/athkar_repository.dart';
import '../domain/athkar_models.dart';

class AthkarChapterScreen extends ConsumerStatefulWidget {
  const AthkarChapterScreen({super.key, required this.chapter});

  final AthkarChapter chapter;

  @override
  ConsumerState<AthkarChapterScreen> createState() =>
      _AthkarChapterScreenState();
}

class _AthkarChapterScreenState extends ConsumerState<AthkarChapterScreen> {
  late AthkarProgress _progress = AthkarProgress(
    chapterId: widget.chapter.id,
    counts: const {},
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final repository = ref.read(athkarRepositoryProvider);
    final saved = await repository.loadProgress(widget.chapter.id);
    if (!mounted) return;
    setState(() {
      _progress = saved;
      _loading = false;
    });
  }

  Future<void> _tap(AthkarItem item) async {
    if (_progress.isItemDone(item)) return;
    final next = _progress.increment(item);
    setState(() => _progress = next);
    await HapticFeedback.selectionClick();
    await ref
        .read(athkarRepositoryProvider)
        .saveCount(widget.chapter.id, item.id, next.countFor(item.id));
    if (next.isChapterDone(widget.chapter)) {
      await HapticFeedback.mediumImpact();
    }
  }

  Future<void> _reset() async {
    setState(() => _progress = _progress.reset());
    await ref.read(athkarRepositoryProvider).clearProgress(widget.chapter.id);
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final ratio = _progress.ratio(chapter);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(chapter.title),
          actions: [
            IconButton(
              tooltip: 'إعادة العد',
              icon: const Icon(Icons.restart_alt),
              onPressed: _reset,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: ratio),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                itemCount: chapter.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = chapter.items[index];
                  return _AthkarCard(
                    item: item,
                    count: _progress.countFor(item.id),
                    done: _progress.isItemDone(item),
                    onTap: () => _tap(item),
                    onCopy: () async {
                      await Clipboard.setData(ClipboardData(text: item.text));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ الذكر')),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _AthkarCard extends StatelessWidget {
  const _AthkarCard({
    required this.item,
    required this.count,
    required this.done,
    required this.onTap,
    required this.onCopy,
  });

  final AthkarItem item;
  final int count;
  final bool done;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: done ? 0 : 2,
      color: done
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
          : theme.cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.text,
                textAlign: TextAlign.justify,
                style: theme.textTheme.titleMedium?.copyWith(height: 1.9),
              ),
              if (item.note != null) ...[
                const SizedBox(height: 10),
                Text(
                  item.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Chip(
                    avatar: Icon(
                      done ? Icons.check_circle : Icons.touch_app,
                      size: 18,
                    ),
                    label: Text('$count / ${item.repeat}'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'نسخ',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
