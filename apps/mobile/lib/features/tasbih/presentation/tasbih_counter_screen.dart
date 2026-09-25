import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/haptics.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/tasbih_repository.dart';

/// شاشة العدّاد الواحد: دائرة لمس كبيرة للعدّ.
///
/// - اهتزاز خفيف عند كل عدّة، واهتزاز قوي عند بلوغ 33 أو 100
///   أو إتمام الهدف.
/// - يعمل offline بالكامل — الحفظ محلي في SharedPreferences.
class TasbihCounterScreen extends ConsumerStatefulWidget {
  const TasbihCounterScreen({super.key, required this.counterId});

  final String counterId;

  @override
  ConsumerState<TasbihCounterScreen> createState() =>
      _TasbihCounterScreenState();
}

class _TasbihCounterScreenState extends ConsumerState<TasbihCounterScreen> {
  late Future<TasbihCounter> _counterFuture;

  @override
  void initState() {
    super.initState();
    _counterFuture = _load();
  }

  Future<TasbihCounter> _load() async {
    final counters = await ref.read(tasbihRepositoryProvider).loadCounters();
    return counters.firstWhere(
      (c) => c.id == widget.counterId,
      orElse: () => counters.first,
    );
  }

  void _refresh(TasbihCounter counter) {
    setState(() => _counterFuture = Future.value(counter));
  }

  Future<void> _increment(TasbihCounter counter) async {
    final updated =
        await ref.read(tasbihRepositoryProvider).increment(counter.id);
    if (!mounted) return;
    final count = updated.count;
    if (count % 100 == 0 || count % 33 == 0) {
      await AppHaptics.milestone();
    } else if (updated.target > 0 && count % updated.target == 0) {
      await AppHaptics.milestone();
    } else {
      await AppHaptics.lightTap();
    }
    _refresh(updated);
  }

  Future<void> _reset(TasbihCounter counter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصفير العدّاد؟'),
        content: Text('سيُصفَّر عدّاد «${counter.name}» ويُحفظ التصفير.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تصفير'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = await ref.read(tasbihRepositoryProvider).reset(counter.id);
    await AppHaptics.milestone();
    _refresh(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السبحة'),
          actions: [
            FutureBuilder<TasbihCounter>(
              future: _counterFuture,
              builder: (context, snapshot) {
                final counter = snapshot.data;
                if (counter == null) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'تصفير',
                  onPressed: () => _reset(counter),
                  icon: const Icon(Icons.restart_alt),
                );
              },
            ),
          ],
        ),
        body: FutureBuilder<TasbihCounter>(
          future: _counterFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    SkeletonBox(width: 180, height: 22),
                    SizedBox(height: 24),
                    SkeletonBox(
                        width: 240, height: 240, borderRadius: 120),
                    SizedBox(height: 24),
                    SkeletonBox(height: 14),
                  ],
                ),
              );
            }
            final counter = snapshot.data;
            if (counter == null) {
              return const Center(child: Text('تعذّر تحميل العدّاد'));
            }
            return _CounterBody(
              counter: counter,
              onIncrement: () => _increment(counter),
            );
          },
        ),
      ),
    );
  }
}

class _CounterBody extends StatelessWidget {
  const _CounterBody({required this.counter, required this.onIncrement});

  final TasbihCounter counter;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            counter.name,
            style:
                theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            counter.target > 0
                ? 'الدورة الحالية: ${counter.cycleCount} / ${counter.target}'
                : 'العدد الإجمالي: ${counter.count}',
            style: TextStyle(color: theme.hintColor),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onIncrement,
            child: Container(
              width: 250,
              height: 250,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${counter.count}',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اضغط للتسبيح',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (counter.target > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: counter.cycleProgress,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أكملت ${(counter.count / counter.target).floor()} دورة كاملة',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ] else
            Text(
              'عدّ مفتوح بلا هدف محدد',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
