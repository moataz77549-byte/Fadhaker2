import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/haptics.dart';
import '../data/allah_names_data.dart';
import '../data/allah_names_repository.dart';

/// تفاصيل اسم واحد من أسماء الله الحسنى مع المشاركة والمفضلة.
class AllahNameDetailScreen extends ConsumerWidget {
  const AllahNameDetailScreen({super.key, required this.name});

  final AllahName name;

  Future<void> _share(BuildContext context) async {
    await AppHaptics.lightTap();
    await Share.share(
      'من أسماء الله الحسنى:\n\n${name.name}\n${name.meaning}\n\n— تطبيق فذكر',
      subject: 'اسم من أسماء الله الحسنى: ${name.name}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(allahNamesFavoritesProvider);
    final favNotifier = ref.read(allahNamesFavoritesProvider.notifier);
    final isFav = favorites.contains(name.number);
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الاسم ${name.number} من 99'),
          actions: [
            IconButton(
              tooltip: isFav ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
              icon: Icon(
                isFav ? Icons.star : Icons.star_border,
                color: isFav ? const Color(0xFFC77955) : null,
              ),
              onPressed: () async {
                await favNotifier.toggleFavorite(name.number);
                await AppHaptics.confirm();
              },
            ),
            IconButton(
              tooltip: 'مشاركة',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _share(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.primaryContainer.withValues(alpha: 0.55),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Text(
                    name.name,
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الاسم رقم ${name.number}',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'المعنى',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              name.meaning,
              style: const TextStyle(fontSize: 17, height: 1.9),
            ),
            const SizedBox(height: 24),
            Card(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '«إن لله تسعة وتسعين اسمًا مائة إلا واحدًا من أحصاها دخل الجنة» — متفق عليه',
                  style: TextStyle(fontSize: 13, height: 1.8),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
