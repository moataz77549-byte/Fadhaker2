import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/hadith_catalog_repository.dart';

class HadithCatalogScreen extends StatefulWidget {
  const HadithCatalogScreen({super.key});
  @override
  State<HadithCatalogScreen> createState() => _HadithCatalogScreenState();
}

class _HadithCatalogScreenState extends State<HadithCatalogScreen> {
  final _repository = HadithCatalogRepository();
  final _search = TextEditingController();
  late Future<List<CatalogHadith>> _page;
  int _offset = 0;
  @override
  void initState() { super.initState(); _page = _repository.page(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  void _load({int? offset}) => setState(() {
    _offset = offset ?? 0;
    _page = _repository.page(query: _search.text, offset: _offset);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('موسوعة الحديث')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(
        controller: _search, textInputAction: TextInputAction.search,
        onSubmitted: (_) => _load(),
        decoration: InputDecoration(labelText: 'ابحث في الأحاديث المراجعة',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward),
            onPressed: () => _load())),
      )),
      Expanded(child: FutureBuilder<List<CatalogHadith>>(
        future: _page,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              const Text('تعذّر تحميل الأحاديث. تحقق من الاتصال ثم حاول مجددًا.'),
              TextButton(onPressed: () => _load(offset: _offset),
                child: const Text('إعادة المحاولة')),
            ]));
          final items = snapshot.data!;
          if (items.isEmpty && _offset == 0) return Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              const Text('لا توجد أحاديث مراجعة متاحة حاليًا.'),
              TextButton(onPressed: () => Navigator.of(context).pushNamed('/daily-hadith'),
                child: const Text('اقرأ الأربعين النووية المحفوظة في الجهاز')),
            ]));
          return ListView(children: [
            for (final hadith in items) Card(child: ListTile(
              title: Text(hadith.title.isEmpty ? hadith.text : hadith.title,
                maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('المصدر: HadeethEnc · ${hadith.reference}', maxLines: 1),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _HadithDetail(hadith: hadith))),
            )),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              TextButton(onPressed: _offset == 0 ? null : () => _load(
                offset: (_offset - HadithCatalogRepository.pageSize).clamp(0, 3000).toInt()),
                child: const Text('السابق')),
              TextButton(onPressed: items.length < HadithCatalogRepository.pageSize
                  ? null : () => _load(offset: _offset + HadithCatalogRepository.pageSize),
                child: const Text('التالي')),
            ]),
          ]);
        },
      )),
    ]),
  );
}

class _HadithDetail extends StatefulWidget {
  const _HadithDetail({required this.hadith});
  final CatalogHadith hadith;
  @override
  State<_HadithDetail> createState() => _HadithDetailState();
}

class _HadithDetailState extends State<_HadithDetail> {
  bool _favorite = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _favorite =
          prefs.getBool('hadith.favorite.${widget.hadith.id}') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hadith;
    return Scaffold(appBar: AppBar(title: const Text('تفاصيل الحديث'), actions: [
      IconButton(tooltip: 'المفضلة', icon: Icon(_favorite ? Icons.star : Icons.star_border),
        onPressed: () async {
          final next = !_favorite;
          await (await SharedPreferences.getInstance())
              .setBool('hadith.favorite.${h.id}', next);
          if (mounted) setState(() => _favorite = next);
        }),
      IconButton(tooltip: 'مشاركة', icon: const Icon(Icons.share_outlined),
        onPressed: () => Share.share('${h.text}\n\n${h.reference}\nالمصدر: HadeethEnc.com\n${h.sourceUrl}')),
    ]), body: ListView(padding: const EdgeInsets.all(20), children: [
      if (h.title.isNotEmpty) Text(h.title,
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      Text(h.text, style: const TextStyle(fontSize: 19, height: 1.9)),
      const Divider(),
      if (h.attribution?.isNotEmpty == true) Text('الإسناد: ${h.attribution}'),
      if (h.grade?.isNotEmpty == true) Text('الدرجة: ${h.grade}'),
      Text('المرجع: ${h.reference}'),
      if (h.explanation?.isNotEmpty == true) ...[
        const SizedBox(height: 16), const Text('الشرح'), Text(h.explanation!),
      ],
      if (h.benefits?.isNotEmpty == true) ...[
        const SizedBox(height: 16), const Text('الفوائد'), Text(h.benefits!),
      ],
      const SizedBox(height: 16), Text('المصدر: HadeethEnc.com · ${h.sourceUrl}',
        style: Theme.of(context).textTheme.bodySmall),
    ]));
  }
}
