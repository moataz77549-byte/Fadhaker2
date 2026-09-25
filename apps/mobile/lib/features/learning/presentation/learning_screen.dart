import 'package:flutter/material.dart';

/// مركز تعلّم صادق وظيفيًا.
///
/// لا يعرض خطط حفظ تجريبية أو نسب تقدّم مصطنعة. إلى أن تتوفر خطة حفظ
/// فعلية مرتبطة ببيانات المستخدم، يوجّه إلى الأدوات العاملة بالفعل.
class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الحفظ والمراجعة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primaryContainer],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.school_rounded,
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
                        'ابدأ من أدوات تعمل فعليًا',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimary,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'لن نعرض نسبة حفظ أو موعد مراجعة قبل وجود خطة حقيقية محفوظة لك.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimary.withValues(alpha: 0.82),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _LearningAction(
            icon: Icons.menu_book_rounded,
            title: 'القراءة من المصحف',
            subtitle: 'افتح الفهرس واختر السورة أو تابع موضعك الأخير.',
            route: '/quran',
          ),
          _LearningAction(
            icon: Icons.track_changes_rounded,
            title: 'متتبع الختمة',
            subtitle: 'تقدّم حقيقي حسب الأجزاء التي تعلّمها كمكتملة.',
            route: '/khatma',
          ),
          _LearningAction(
            icon: Icons.brightness_low_rounded,
            title: 'الأذكار',
            subtitle: 'مكتبة الأذكار والعدّادات اليومية.',
            route: '/adhkar',
          ),
          _LearningAction(
            icon: Icons.record_voice_over_rounded,
            title: 'الاستماع للقراء',
            subtitle: 'اختر قارئًا وتلاوة للمراجعة السمعية.',
            route: '/reciters',
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: scheme.secondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'خطة الحفظ المتقدمة، الجلسات، وجدولة المراجعة لن تظهر للمستخدم حتى يتم ربطها بمخزن بيانات حقيقي وحساب تقدّم فعلي.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LearningAction extends StatelessWidget {
  const _LearningAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => Navigator.of(context).pushNamed(route),
      ),
    );
  }
}
