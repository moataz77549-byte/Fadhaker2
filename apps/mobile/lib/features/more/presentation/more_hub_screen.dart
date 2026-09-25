import 'package:flutter/material.dart';

class MoreHubScreen extends StatelessWidget {
  const MoreHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <_MoreSection>[
      const _MoreSection(
        title: 'العبادة اليومية',
        items: [
          _MoreItem('الأذكار', Icons.brightness_low_rounded, '/adhkar'),
          _MoreItem('مواقيت الصلاة', Icons.mosque_rounded, '/prayer-times'),
          _MoreItem('التذكيرات', Icons.alarm_rounded, '/custom-reminders'),
          _MoreItem('السبحة', Icons.touch_app_rounded, '/tasbih'),
        ],
      ),
      const _MoreSection(
        title: 'التعلّم والمتابعة',
        items: [
          _MoreItem('الحفظ والمراجعة', Icons.school_rounded, '/learning'),
          _MoreItem('حديث اليوم', Icons.format_quote_rounded, '/daily-hadith'),
          _MoreItem('موسوعة الحديث', Icons.menu_book_outlined, '/hadith'),
          _MoreItem('أسماء الله الحسنى', Icons.auto_awesome_rounded, '/allah-names'),
          _MoreItem('متتبع الختمة', Icons.track_changes_rounded, '/khatma'),
        ],
      ),
      const _MoreSection(
        title: 'التطبيق',
        items: [
          _MoreItem('الإعدادات', Icons.settings_rounded, '/settings'),
        ],
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('المزيد', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'الأدوات والخدمات الإضافية مرتبة حسب الاستخدام.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 18),
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 6),
            child: Text(
              section.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < section.items.length; i++) ...[
                  ListTile(
                    leading: Icon(section.items[i].icon),
                    title: Text(section.items[i].title),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.of(context)
                        .pushNamed(section.items[i].route),
                  ),
                  if (i != section.items.length - 1)
                    const Divider(height: 1, indent: 56),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MoreSection {
  const _MoreSection({required this.title, required this.items});
  final String title;
  final List<_MoreItem> items;
}

class _MoreItem {
  const _MoreItem(this.title, this.icon, this.route);
  final String title;
  final IconData icon;
  final String route;
}
