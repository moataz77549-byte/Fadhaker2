import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../athkar/data/athkar_repository.dart';

/// عدّاد تسبيح مسمّى: اسم العبارة + هدف + عدّ حالي.
class TasbihCounter {
  const TasbihCounter({
    required this.id,
    required this.name,
    required this.target,
    required this.count,
    required this.isCustom,
    required this.updatedAt,
  });

  /// معرّف فريد ثابت للعدّادات المسبقة، أو مولّد للمخصصة.
  final String id;

  /// اسم الذكر (مثل «سبحان الله» أو اسم مخصص).
  final String name;

  /// الهدف لكل دورة (33/100/1000...) — صفر يعني عدًّا مفتوحًا بلا هدف.
  final int target;

  /// العدّ التراكمي الحالي.
  final int count;

  /// هل أنشأه المستخدم (قابل للحذف) أم مسبق ثابت.
  final bool isCustom;

  final DateTime updatedAt;

  /// التقدّم داخل الدورة الحالية (0..1) — 0 عندما لا يوجد هدف.
  double get cycleProgress =>
      target > 0 ? (count % target) / target : 0.0;

  /// العدّ داخل الدورة الحالية.
  int get cycleCount => target > 0 ? count % target : count;

  TasbihCounter copyWith({int? count, int? target, String? name}) {
    return TasbihCounter(
      id: id,
      name: name ?? this.name,
      target: target ?? this.target,
      count: count ?? this.count,
      isCustom: isCustom,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'count': count,
        'isCustom': isCustom,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory TasbihCounter.fromJson(Map<String, dynamic> json) {
    return TasbihCounter(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      target: (json['target'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      isCustom: json['isCustom'] == true,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// مستودع السبحة الإلكترونية.
///
/// - يعمل offline بالكامل: الحفظ في SharedPreferences بصيغة JSON.
/// - عدّادات مسبقة ثابتة (العبارات الست) + عدّادات مخصصة ينشئها المستخدم.
/// - عند أول تشغيل بعد الترقية: تُرحَّل العدّادات القديمة المحفوظة في
///   SQLite (جدول `tasbih_counters` بمفتاح نص العبارة) إلى المخزن الجديد
///   دون فقدان أي تقدّم — ثم تُترك البيانات القديمة كما هي للتوافق.
class TasbihRepository {
  TasbihRepository({AthkarRepository? legacyRepository})
      : _legacy = legacyRepository ?? AthkarRepository();

  static const _kCounters = 'tasbih.counters.v2';
  static const _kMigrated = 'tasbih.migrated_v2';

  /// العبارات المسبقة: (المعرّف، الاسم، الهدف الافتراضي).
  static const List<(String, String, int)> presetCounters = [
    ('preset-subhanallah', 'سبحان الله', 33),
    ('preset-alhamdulillah', 'الحمد لله', 33),
    ('preset-allahuakbar', 'الله أكبر', 33),
    ('preset-lailaha', 'لا إله إلا الله', 100),
    ('preset-astaghfirullah', 'أستغفر الله', 100),
    ('preset-lahawla', 'لا حول ولا قوة إلا بالله', 100),
  ];

  /// أهداف جاهزة للاختيار السريع عند إنشاء عدّاد مخصص.
  static const List<int> quickTargets = [33, 100, 1000];

  final AthkarRepository _legacy;

  /// يحمّل كل العدّادات (مسبقة + مخصصة) مرتّبة: المسبقة أولًا ثم المخصصة
  /// حسب الأحدث.
  Future<List<TasbihCounter>> loadCounters() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyOnce(prefs);

    final raw = prefs.getString(_kCounters);
    final stored = <String, TasbihCounter>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final counter = TasbihCounter.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (counter.id.isNotEmpty && counter.name.isNotEmpty) {
              stored[counter.id] = counter;
            }
          }
        }
      } catch (_) {
        // مخزن تالف: نُعيد البناء من المسبقات الافتراضية.
      }
    }

    final result = <TasbihCounter>[];
    for (final (id, name, target) in presetCounters) {
      final existing = stored[id];
      result.add(
        existing ??
            TasbihCounter(
              id: id,
              name: name,
              target: target,
              count: 0,
              isCustom: false,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
      );
    }
    final customs = stored.values
        .where((c) => c.isCustom)
        .toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    result.addAll(customs);
    return result;
  }

  /// يزيد العدّاد بمقدار واحد ويعيد النسخة المحدّثة.
  Future<TasbihCounter> increment(String id) async {
    final counters = await loadCounters();
    final counter = counters.firstWhere(
      (c) => c.id == id,
      orElse: () => throw StateError('Unknown tasbih counter: $id'),
    );
    final updated = counter.copyWith(count: counter.count + 1);
    await _persistAll(counters.map((c) => c.id == id ? updated : c).toList());
    return updated;
  }

  /// يصفّر العدّاد (يبقي الهدف والاسم).
  Future<TasbihCounter> reset(String id) async {
    final counters = await loadCounters();
    final counter = counters.firstWhere(
      (c) => c.id == id,
      orElse: () => throw StateError('Unknown tasbih counter: $id'),
    );
    final updated = counter.copyWith(count: 0);
    await _persistAll(counters.map((c) => c.id == id ? updated : c).toList());
    return updated;
  }

  /// يغيّر هدف عدّاد مخصص (المسبقة لها أهداف ثابتة).
  Future<TasbihCounter> updateTarget(String id, int target) async {
    final counters = await loadCounters();
    final counter = counters.firstWhere(
      (c) => c.id == id,
      orElse: () => throw StateError('Unknown tasbih counter: $id'),
    );
    if (!counter.isCustom) return counter;
    final updated = counter.copyWith(target: target < 0 ? 0 : target);
    await _persistAll(counters.map((c) => c.id == id ? updated : c).toList());
    return updated;
  }

  /// ينشئ عدّادًا مخصصًا جديدًا.
  Future<TasbihCounter> createCustom({
    required String name,
    int target = 33,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Counter name is empty');
    final counters = await loadCounters();
    final counter = TasbihCounter(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      target: target < 0 ? 0 : target,
      count: 0,
      isCustom: true,
      updatedAt: DateTime.now(),
    );
    await _persistAll([...counters, counter]);
    return counter;
  }

  /// يحذف عدّادًا مخصصًا (المسبقة لا تُحذف).
  Future<void> deleteCustom(String id) async {
    final counters = await loadCounters();
    final remaining =
        counters.where((c) => !(c.id == id && c.isCustom)).toList();
    if (remaining.length != counters.length) {
      await _persistAll(remaining);
    }
  }

  Future<void> _persistAll(List<TasbihCounter> counters) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded =
          jsonEncode(counters.map((c) => c.toJson()).toList());
      await prefs.setString(_kCounters, encoded);
    } catch (_) {
      // الحفظ best-effort — العدّاد ميزة مساعدة وليست حرجة.
    }
  }

  /// ترحيل لمرة واحدة من مخزن SQLite القديم (مفتاحه نص العبارة)
  /// إلى المخزن الجديد (مفتاحه معرّف ثابت).
  Future<void> _migrateLegacyOnce(SharedPreferences prefs) async {
    if (prefs.getBool(_kMigrated) == true) return;
    try {
      final migrated = <TasbihCounter>[];
      for (final (id, name, target) in presetCounters) {
        final legacyCount = await _legacy.loadTasbih(name);
        if (legacyCount > 0) {
          migrated.add(TasbihCounter(
            id: id,
            name: name,
            target: target,
            count: legacyCount,
            isCustom: false,
            updatedAt: DateTime.now(),
          ));
        }
      }
      if (migrated.isNotEmpty) {
        final encoded = jsonEncode(migrated.map((c) => c.toJson()).toList());
        await prefs.setString(_kCounters, encoded);
      }
      await prefs.setBool(_kMigrated, true);
    } catch (_) {
      // الترحيل best-effort — لا يمنع عمل السبحة الجديدة.
    }
  }
}

final tasbihRepositoryProvider = Provider<TasbihRepository>((ref) {
  return TasbihRepository();
});
