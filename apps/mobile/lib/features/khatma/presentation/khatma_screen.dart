import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/haptics.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../quran/presentation/mushaf_reader_screen.dart';
import '../data/khatma_repository.dart';

/// شاشة متتبع الختمة: خطة 30 جزءًا مبنية على تقدّم القراءة الفعلي.
///
/// - نسبة الإنجاز والجزء الحالي من آخر موضع قراءة محفوظ.
/// - إكمال الأجزاء يدوي (يعلّمها المستخدم بعد قراءتها فعلًا).
/// - زر «استئناف القراءة» يفتح المصحف عند آخر موضع.
class KhatmaScreen extends ConsumerStatefulWidget {
  const KhatmaScreen({super.key});

  @override
  ConsumerState<KhatmaScreen> createState() => _KhatmaScreenState();
}

class _KhatmaScreenState extends ConsumerState<KhatmaScreen> {
  late Future<KhatmaState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = ref.read(khatmaRepositoryProvider).load();
  }

  void _refresh(KhatmaState state) {
    setState(() => _stateFuture = Future.value(state));
  }

  Future<void> _toggleJuz(int juz, bool completed) async {
    final wasComplete = completed;
    final state =
        await ref.read(khatmaRepositoryProvider).toggleJuzComplete(juz);
    if (!mounted) return;
    if (!wasComplete && state.completedJuz.contains(juz)) {
      // إكمال جديد — اهتزاز إنجاز.
      await AppHaptics.milestone();
      if (state.isComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تقبّل الله — أتممت ختمة كاملة!'),
          ),
        );
      }
    } else {
      await AppHaptics.lightTap();
    }
    _refresh(state);
  }

  Future<void> _resumeReading(KhatmaState state) async {
    await AppHaptics.lightTap();
    if (!mounted) return;
    final page = state.savedPage ??
        KhatmaRepository.juzStartPages[state.currentJuz - 1];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MushafReaderScreen(initialPage: page),
      ),
    );
    if (!mounted) return;
    _refresh(await ref.read(khatmaRepositoryProvider).load());
  }

  Future<void> _resetPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بدء ختمة جديدة؟'),
        content: const Text(
          'سيُصفَّر إكمال الأجزاء وتبدأ خطة جديدة. '
          'لن يُمسّ موضع قراءتك المحفوظ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('بدء ختمة جديدة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final state = await ref.read(khatmaRepositoryProvider).reset();
    await AppHaptics.confirm();
    _refresh(state);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('متتبع الختمة'),
          actions: [
            IconButton(
              tooltip: 'بدء ختمة جديدة',
              icon: const Icon(Icons.restart_alt),
              onPressed: _resetPlan,
            ),
          ],
        ),
        body: FutureBuilder<KhatmaState>(
          future: _stateFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList(itemHeight: 64, itemCount: 8);
            }
            if (snapshot.hasError) {
              return FadhkurEmptyState(
                icon: Icons.error_outline,
                title: 'تعذّر تحميل الخطة',
                actionLabel: 'إعادة المحاولة',
                onAction: () => setState(() =>
                    _stateFuture = ref.read(khatmaRepositoryProvider).load()),
              );
            }
            final state = snapshot.data!;
            return _KhatmaBody(
              state: state,
              onToggleJuz: _toggleJuz,
              onResume: () => _resumeReading(state),
            );
          },
        ),
      ),
    );
  }
}

class _KhatmaBody extends StatelessWidget {
  const _KhatmaBody({
    required this.state,
    required this.onToggleJuz,
    required this.onResume,
  });

  final KhatmaState state;
  final Future<void> Function(int juz, bool completed) onToggleJuz;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          color: const Color(0xFF243B6B),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 84,
                            height: 84,
                            child: CircularProgressIndicator(
                              value: state.progress,
                              strokeWidth: 9,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF9FE2D3)),
                            ),
                          ),
                          Text(
                            '${state.progressPercent}٪',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ختمة القرآن الكريم',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            state.completedCount == 0
                                ? 'لم تكمل أي جزء بعد — ابدأ من الجزء الأول'
                                : 'أكملت ${state.completedCount} من 30 جزءًا',
                            style: const TextStyle(color: Color(0xFFB8C5D8)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'جزؤك الحالي: الجزء ${state.currentJuz}',
                            style: const TextStyle(
                              color: Color(0xFF9FE2D3),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E9E9E),
                    ),
                    onPressed: onResume,
                    icon: const Icon(Icons.menu_book),
                    label: Text(
                      state.savedPage == null
                          ? 'ابدأ القراءة من الجزء الأول'
                          : 'استئناف القراءة — صفحة ${state.savedPage}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'الأجزاء الثلاثون',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'علِّم الجزء كمكتمل بعد قراءته فعلًا.',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...List.generate(30, (index) {
          final juz = index + 1;
          final completed = state.completedJuz.contains(juz);
          final isCurrent = juz == state.currentJuz && !completed;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: completed
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : null,
            child: CheckboxListTile(
              value: completed,
              onChanged: (_) => onToggleJuz(juz, completed),
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(
                children: [
                  Text(
                    'الجزء $juz',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration:
                          completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC77955),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'الحالي',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                'يبدأ من صفحة ${KhatmaRepository.juzStartPages[juz - 1]} • '
                '${KhatmaRepository.juzPageCount(juz)} صفحة',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          );
        }),
      ],
    );
  }
}
