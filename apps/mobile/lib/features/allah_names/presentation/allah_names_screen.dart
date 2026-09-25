import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/haptics.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/allah_names_data.dart';
import '../data/allah_names_repository.dart';
import 'allah_name_detail_screen.dart';

/// شاشة أسماء الله الحسنى (99).
///
/// - بحث فوري محلي (بالاسم أو المعنى أو الرقم).
/// - تحميل تدريجي (pagination): 30 اسمًا أولًا ثم المزيد عند التمرير.
/// - مفضلة محفوظة محليًا مع تبويب مستقل.
class AllahNamesScreen extends ConsumerStatefulWidget {
  const AllahNamesScreen({super.key});

  @override
  ConsumerState<AllahNamesScreen> createState() => _AllahNamesScreenState();
}

class _AllahNamesScreenState extends ConsumerState<AllahNamesScreen>
    with SingleTickerProviderStateMixin {
  static const _pageSize = 30;

  late final TabController _tabs;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim();
        _visibleCount = _pageSize;
      });
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      setState(() => _visibleCount += _pageSize);
    }
  }

  List<AllahName> _filtered(Set<int> favorites, bool favoritesOnly) {
    var list = favoritesOnly
        ? allahNames.where((n) => favorites.contains(n.number)).toList()
        : allahNames;
    if (_query.isNotEmpty) {
      final q = _query;
      final asNumber = int.tryParse(q);
      list = list.where((n) {
        return n.name.contains(q) ||
            n.meaning.contains(q) ||
            (asNumber != null && n.number == asNumber);
      }).toList(growable: false);
    }
    return list;
  }

  Future<void> _openDetail(AllahName name) async {
    await AppHaptics.lightTap();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AllahNameDetailScreen(name: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(allahNamesFavoritesProvider);
    final favNotifier = ref.read(allahNamesFavoritesProvider.notifier);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أسماء الله الحسنى'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'كل الأسماء (99)'),
              Tab(text: 'المفضلة'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو المعنى أو الرقم',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _NamesList(
                    names: _filtered(favorites, false),
                    visibleCount: _visibleCount,
                    scrollController: _scrollController,
                    favorites: favorites,
                    onToggleFavorite: (n) async {
                      await favNotifier.toggleFavorite(n);
                      await AppHaptics.confirm();
                    },
                    onOpen: _openDetail,
                    emptyTitle: 'لا نتائج مطابقة',
                    emptySubtitle: 'جرّب كلمة أخرى أو رقمًا بين 1 و 99.',
                  ),
                  _NamesList(
                    names: _filtered(favorites, true),
                    visibleCount: _visibleCount,
                    scrollController: null,
                    favorites: favorites,
                    onToggleFavorite: (n) async {
                      await favNotifier.toggleFavorite(n);
                      await AppHaptics.confirm();
                    },
                    onOpen: _openDetail,
                    emptyTitle: 'لا توجد أسماء مفضلة بعد',
                    emptySubtitle:
                        'اضغط على النجمة بجانب أي اسم لحفظه هنا.',
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

class _NamesList extends StatelessWidget {
  const _NamesList({
    required this.names,
    required this.visibleCount,
    required this.scrollController,
    required this.favorites,
    required this.onToggleFavorite,
    required this.onOpen,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<AllahName> names;
  final int visibleCount;
  final ScrollController? scrollController;
  final Set<int> favorites;
  final ValueChanged<int> onToggleFavorite;
  final ValueChanged<AllahName> onOpen;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return FadhkurEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }
    final shown = names.take(visibleCount).toList(growable: false);
    final hasMore = shown.length < names.length;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: shown.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= shown.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }
        final name = shown[index];
        final isFav = favorites.contains(name.number);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.6),
              child: Text(
                '${name.number}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            title: Text(
              name.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Text(
              name.meaning,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            trailing: IconButton(
              tooltip: isFav ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
              icon: Icon(
                isFav ? Icons.star : Icons.star_border,
                color:
                    isFav ? const Color(0xFFC77955) : Theme.of(context).hintColor,
              ),
              onPressed: () => onToggleFavorite(name.number),
            ),
            onTap: () => onOpen(name),
          ),
        );
      },
    );
  }
}
