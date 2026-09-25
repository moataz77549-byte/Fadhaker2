import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/brand_mark.dart';
import '../../home/presentation/home_screen.dart';
import '../../library/presentation/library_hub_screen.dart';
import '../../listen/presentation/listen_hub_screen.dart';
import '../../more/presentation/more_hub_screen.dart';
import '../../quran/presentation/quran_home_screen.dart';
import '../../search/presentation/search_screen.dart';
import 'mini_audio_player_bar.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _currentIndex = 0;
  // Keep each tab's element in a stable position throughout navigation.
  // Swapping a placeholder for an InheritedWidget-dependent page while a
  // route/overlay is popping can detach dependents during disposal.
  static const _pages = <Widget>[
    HomeScreen(),
    QuranHomeScreen(),
    ListenHubScreen(),
    LibraryHubScreen(),
    MoreHubScreen(),
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'الرئيسية',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book_rounded),
      label: 'القرآن',
    ),
    NavigationDestination(
      icon: Icon(Icons.headphones_outlined),
      selectedIcon: Icon(Icons.headphones_rounded),
      label: 'الاستماع',
    ),
    NavigationDestination(
      icon: Icon(Icons.bookmarks_outlined),
      selectedIcon: Icon(Icons.bookmarks_rounded),
      label: 'مكتبتي',
    ),
    NavigationDestination(
      icon: Icon(Icons.grid_view_outlined),
      selectedIcon: Icon(Icons.grid_view_rounded),
      label: 'المزيد',
    ),
  ];

  static const _titles = <String>[
    'فذكر',
    'القرآن الكريم',
    'الاستماع',
    'مكتبتي',
    'المزيد',
  ];

  void _select(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final expandedNavigation = width >= 760;
    final scheme = Theme.of(context).colorScheme;

    final content = IndexedStack(index: _currentIndex, children: _pages);

    return Scaffold(
      extendBody: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const FadhkurBrandMark(size: 34, isRadio: true),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _titles[_currentIndex],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            tooltip: 'البحث',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: expandedNavigation
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.65,
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: scheme.tertiary,
                      ),
                    ),
                    destinations: _destinations
                        .map(
                          (item) => NavigationRailDestination(
                            icon: item.icon,
                            selectedIcon: item.selectedIcon,
                            label: Text(item.label),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: content),
                        const MiniAudioPlayerBar(),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(child: content),
                  const MiniAudioPlayerBar(),
                ],
              ),
      ),
      bottomNavigationBar: expandedNavigation
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _select,
              destinations: _destinations,
            ),
    );
  }
}
