import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/data/reading_progress_repository.dart';

/// حالة خطة الختمة: الأجزاء المكتملة + الجزء الحالي + نسبة الإنجاز.
class KhatmaState {
  const KhatmaState({
    required this.completedJuz,
    required this.currentJuz,
    required this.savedPage,
  });

  /// الأجزاء المكتملة (1..30) — يعلّمها المستخدم يدويًا بعد قراءتها.
  final Set<int> completedJuz;

  /// الجزء الحالي مشتق من آخر موضع قراءة محفوظ.
  final int currentJuz;

  /// آخر صفحة قراءة محفوظة (للاستئناف) — null إذا لم يبدأ بعد.
  final int? savedPage;

  int get completedCount => completedJuz.length;

  double get progress =>
      completedJuz.isEmpty ? 0.0 : completedJuz.length / 30.0;

  int get progressPercent => (progress * 100).round();

  bool get isComplete => completedJuz.length >= 30;
}

/// متتبع الختمة — مبني على [ReadingProgressRepository] الموجود.
///
/// - خطة من 30 جزءًا بصفحات بدايتها الثابتة في المصحف المدني.
/// - الجزء الحالي يُشتق تلقائيًا من آخر موضع قراءة محفوظ.
/// - إكمال الأجزاء يدوي (صادق): المستخدم يعلّم الجزء بعد قراءته فعلًا.
/// - الحفظ محلي بالكامل (SharedPreferences) — يعمل offline.
class KhatmaRepository {
  KhatmaRepository({ReadingProgressRepository? progressRepository})
      : _progress = progressRepository ?? ReadingProgressRepository();

  static const _kCompleted = 'khatma.completed_juz.v1';

  /// صفحات بداية الأجزاء الثلاثين في المصحف المدني (604 صفحات).
  /// مرجع ثابت — نفس التقسيم المعتمد في المصاحف المطبوعة.
  static const List<int> juzStartPages = [
    1, 22, 42, 62, 82, 102, 122, 142, 162, 182,
    202, 222, 242, 262, 282, 302, 322, 342, 362, 382,
    402, 422, 442, 462, 482, 502, 522, 542, 562, 582,
  ];

  final ReadingProgressRepository _progress;

  /// الجزء (1..30) الذي تنتمي إليه الصفحة.
  static int juzForPage(int page) {
    final clamped = page.clamp(1, 604);
    var juz = 1;
    for (var i = 0; i < juzStartPages.length; i++) {
      if (clamped >= juzStartPages[i]) {
        juz = i + 1;
      } else {
        break;
      }
    }
    return juz;
  }

  /// عدد صفحات الجزء.
  static int juzPageCount(int juz) {
    if (juz < 1 || juz > 30) return 0;
    final start = juzStartPages[juz - 1];
    final end = juz < 30 ? juzStartPages[juz] - 1 : 604;
    return end - start + 1;
  }

  Future<KhatmaState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kCompleted) ?? const <String>[];
    final completed = <int>{
      for (final s in stored)
        if (int.tryParse(s) case final n? when n >= 1 && n <= 30) n,
    };
    final progress = await _progress.load();
    final savedPage = progress?.page;
    return KhatmaState(
      completedJuz: completed,
      currentJuz: savedPage == null ? 1 : juzForPage(savedPage),
      savedPage: savedPage,
    );
  }

  /// يبدّل حالة إكمال جزء ويعيد الحالة المحدّثة.
  Future<KhatmaState> toggleJuzComplete(int juz) async {
    if (juz < 1 || juz > 30) return load();
    final state = await load();
    final next = {...state.completedJuz};
    if (next.contains(juz)) {
      next.remove(juz);
    } else {
      next.add(juz);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kCompleted,
        next.map((n) => '$n').toList(growable: false),
      );
    } catch (_) {}
    return KhatmaState(
      completedJuz: next,
      currentJuz: state.currentJuz,
      savedPage: state.savedPage,
    );
  }

  /// يصفّر الخطة (يبقي تقدّم القراءة نفسه — الخطة فقط تُصفَّر).
  Future<KhatmaState> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCompleted);
    } catch (_) {}
    return load();
  }
}

final khatmaRepositoryProvider = Provider<KhatmaRepository>((ref) {
  return KhatmaRepository();
});
