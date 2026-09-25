import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/haptics.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/tasbih_repository.dart';
import 'tasbih_counter_screen.dart';

/// شاشة السبحة: قائمة العدّادات المسماة.
///
/// عدّادات مسبقة (سبحان الله/الحمد لله/الله أكبر + ...) وعدّادات مخصصة
/// ينشئها المستخدم — كلها محفوظة محليًا وتعمل دون اتصال.
class TasbihScreen extends ConsumerStatefulWidget {
  const TasbihScreen({super.key});

  @override
  ConsumerState<TasbihScreen> createState() => _TasbihScreenState();
}

class _TasbihScreenState extends ConsumerState<TasbihScreen> {
  late Future<List<TasbihCounter>> _countersFuture;

  @override
  void initState() {
    super.initState();
    _countersFuture = ref.read(tasbihRepositoryProvider).loadCounters();
  }

  void _reload() {
    setState(() {
      _countersFuture = ref.read(tasbihRepositoryProvider).loadCounters();
    });
  }

  Future<void> _openCounter(TasbihCounter counter) async {
    await AppHaptics.lightTap();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TasbihCounterScreen(counterId: counter.id),
      ),
    );
    _reload();
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    int target = 33;
    final result = await showDialog<(String, int)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('عدّاد مخصص جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'اسم الذكر',
                  hintText: 'مثال: الصلاة على النبي',
                ),
              ),
              const SizedBox(height: 16),
              const Text('الهدف لكل دورة'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ...TasbihRepository.quickTargets.map(
                    (t) => ChoiceChip(
                      label: Text('$t'),
                      selected: target == t,
                      onSelected: (_) =>
                          setDialogState(() => target = t),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('بلا هدف'),
                    selected: target == 0,
                    onSelected: (_) => setDialogState(() => target = 0),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, (nameController.text.trim(), target)),
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null || result.$1.isEmpty || !mounted) return;
    await ref.read(tasbihRepositoryProvider).createCustom(
          name: result.$1,
          target: result.$2,
        );
    await AppHaptics.confirm();
    _reload();
  }

  Future<void> _deleteCustom(TasbihCounter counter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العدّاد؟'),
        content: Text('سيُحذف عدّاد «${counter.name}» نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(tasbihRepositoryProvider).deleteCustom(counter.id);
    await AppHaptics.confirm();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السبحة'),
          actions: [
            IconButton(
              tooltip: 'عدّاد مخصص جديد',
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: FutureBuilder<List<TasbihCounter>>(
          future: _countersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList(itemHeight: 84);
            }
            if (snapshot.hasError) {
              return FadhkurEmptyState(
                icon: Icons.error_outline,
                title: 'تعذّر تحميل العدّادات',
                actionLabel: 'إعادة المحاولة',
                onAction: _reload,
              );
            }
            final counters = snapshot.data ?? const <TasbihCounter>[];
            if (counters.isEmpty) {
              return FadhkurEmptyState(
                icon: Icons.touch_app_outlined,
                title: 'لا توجد عدّادات',
                subtitle: 'أنشئ عدّادك المخصص الأول للبدء.',
                actionLabel: 'عدّاد جديد',
                onAction: _showCreateDialog,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: counters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final counter = counters[index];
                return _CounterTile(
                  counter: counter,
                  onTap: () => _openCounter(counter),
                  onDelete: counter.isCustom
                      ? () => _deleteCustom(counter)
                      : null,
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateDialog,
          icon: const Icon(Icons.add),
          label: const Text('عدّاد مخصص'),
        ),
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.counter,
    required this.onTap,
    this.onDelete,
  });

  final TasbihCounter counter;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.touch_app,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      counter.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      counter.target > 0
                          ? '${counter.count} • الهدف ${counter.target}'
                          : '${counter.count} • بلا هدف',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: 13,
                      ),
                    ),
                    if (counter.target > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: counter.cycleProgress,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'حذف العدّاد',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                )
              else
                const Icon(Icons.chevron_left, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
