import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/haptics.dart';
import '../data/forty_nawawi.dart';
import '../data/daily_hadith_repository.dart';

/// شاشة حديث اليوم: حديث الأربعين النووية المخصّص لهذا اليوم
/// مع إمكانية تصفّح الأحاديث السابقة والقادمة ومشاركتها.
class DailyHadithScreen extends ConsumerStatefulWidget {
  const DailyHadithScreen({super.key});

  @override
  ConsumerState<DailyHadithScreen> createState() => _DailyHadithScreenState();
}

class _DailyHadithScreenState extends ConsumerState<DailyHadithScreen> {
  /// إزاحة الأيام عن اليوم: 0 = اليوم، -1 = أمس، +1 = غدًا...
  int _dayOffset = 0;

  NawawiHadith _hadithForOffset(int offset) {
    final date = DateTime.now().add(Duration(days: offset));
    return ref.read(dailyHadithRepositoryProvider).hadithForDate(date);
  }

  String _offsetLabel(int offset) {
    if (offset == 0) return 'حديث اليوم';
    if (offset == -1) return 'حديث الأمس';
    if (offset == 1) return 'حديث الغد';
    if (offset < 0) return 'قبل ${-offset} أيام';
    return 'بعد $offset أيام';
  }

  Future<void> _share(NawawiHadith hadith) async {
    await AppHaptics.lightTap();
    await Share.share(
      'حديث اليوم — ${hadith.title}\n\n'
      'قال رسول الله صلى الله عليه وسلم:\n«${hadith.text}»\n\n'
      'الراوي: ${hadith.narrator}\n'
      'الدرجة: ${hadith.grade}\n\n'
      '— تطبيق فذكر',
      subject: 'حديث اليوم: ${hadith.title}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hadith = _hadithForOffset(_dayOffset);
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('حديث اليوم'),
          actions: [
            IconButton(
              tooltip: 'مشاركة الحديث',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _share(hadith),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'الحديث السابق',
                  onPressed: () async {
                    await AppHaptics.lightTap();
                    setState(() => _dayOffset--);
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _offsetLabel(_dayOffset),
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'الحديث التالي',
                  onPressed: () async {
                    await AppHaptics.lightTap();
                    setState(() => _dayOffset++);
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'الحديث ${hadith.number} من 40',
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hadith.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '«${hadith.text}»',
                      style: const TextStyle(fontSize: 17, height: 2.0),
                      textAlign: TextAlign.justify,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _MetaRow(
                        icon: Icons.person_outline,
                        label: 'الراوي',
                        value: hadith.narrator),
                    const SizedBox(height: 6),
                    _MetaRow(
                        icon: Icons.verified_outlined,
                        label: 'الدرجة',
                        value: hadith.grade),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'يتبدّل الحديث يوميًا بالتناوب على الأحاديث الأربعين — من الأربعين النووية للإمام النووي رحمه الله.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).hintColor),
        const SizedBox(width: 8),
        Text('$label: ',
            style: TextStyle(
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, height: 1.7)),
        ),
      ],
    );
  }
}
