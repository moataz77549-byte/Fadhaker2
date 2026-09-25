import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مستودع مفضلة أسماء الله الحسنى — حفظ محلي فقط (SharedPreferences).
///
/// الأسماء نفسها بيانات مدمجة ثابتة في [allah_names_data.dart]؛
/// يُخزَّن هنا فقط أرقام الأسماء المفضلة (1..99).
class AllahNamesFavoritesNotifier extends StateNotifier<Set<int>> {
  AllahNamesFavoritesNotifier() : super(const {}) {
    _restore();
  }

  static const _kFavorites = 'allah_names.favorites.v1';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_kFavorites);
      if (stored == null) return;
      final numbers = <int>{
        for (final s in stored)
          if (int.tryParse(s) case final n? when n >= 1 && n <= 99) n,
      };
      if (numbers.isNotEmpty) state = numbers;
    } catch (_) {}
  }

  Future<void> toggleFavorite(int number) async {
    if (number < 1 || number > 99) return;
    final next = {...state};
    if (next.contains(number)) {
      next.remove(number);
    } else {
      next.add(number);
    }
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kFavorites,
        next.map((n) => '$n').toList(growable: false),
      );
    } catch (_) {}
  }

  bool isFavorite(int number) => state.contains(number);
}

final allahNamesFavoritesProvider =
    StateNotifierProvider<AllahNamesFavoritesNotifier, Set<int>>(
  (ref) => AllahNamesFavoritesNotifier(),
);
