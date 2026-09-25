import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// فاصلة (علامة مرجعية) على آية معيّنة.
///
/// تُحفظ محليًا على الجهاز فقط — التطبيق لا يملك نظام حسابات،
/// لذا لا توجد مزامنة عبر الأجهزة (موثّق كقيد بنيوي).
class MushafBookmark {
  MushafBookmark({
    required this.ayahKey,
    required this.surahNumber,
    required this.verseNumber,
    this.page,
    this.surahName,
    this.riwayaId = 'hafs',
    DateTime? savedAt,
  }) : savedAt = savedAt ?? _epoch;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// مفتاح الآية بصيغة «chapter:verse».
  final String ayahKey;
  final int surahNumber;
  final int verseNumber;

  /// رقم الصفحة وقت الحفظ (قد يكون null للفواصل القديمة).
  final int? page;
  final String? surahName;
  final String riwayaId;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'ayahKey': ayahKey,
        'surahNumber': surahNumber,
        'verseNumber': verseNumber,
        'page': page,
        'surahName': surahName,
        'riwayaId': riwayaId,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory MushafBookmark.fromJson(Map<String, dynamic> json) {
    final key = '${json['ayahKey'] ?? ''}';
    final parts = key.split(':');
    return MushafBookmark(
      ayahKey: key,
      surahNumber: (json['surahNumber'] as num?)?.toInt() ?? int.tryParse(parts.first) ?? 1,
      verseNumber: (json['verseNumber'] as num?)?.toInt() ??
          (parts.length > 1 ? int.tryParse(parts.last) : null) ??
          1,
      page: (json['page'] as num?)?.toInt(),
      surahName: json['surahName'] as String?,
      riwayaId: json['riwayaId'] as String? ?? 'hafs',
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['savedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// مستودع الفواصل — حفظ محلي مع ترحيل تلقائي من التنسيق القديم
/// (قائمة مفاتيح آيات خام في 'mushaf_bookmarks').
class MushafBookmarkRepository {
  MushafBookmarkRepository({Future<SharedPreferences> Function()? prefsProvider})
      : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsProvider;

  static const _kBookmarks = 'mushaf_bookmarks.v1';
  static const _kLegacyBookmarks = 'mushaf_bookmarks';

  /// كل الفواصل مرتبةً من الأحدث للأقدم.
  Future<List<MushafBookmark>> list() async {
    final prefs = await _prefsProvider();
    await _migrateLegacy(prefs);
    return _readV1(prefs);
  }

  /// قراءة الفواصل من التنسيق الحالي دون ترحيل (تُستخدم داخليًا
  /// لتفادي استدعاء متبادل لا نهائي بين list و_migrateLegacy).
  List<MushafBookmark> _readV1(SharedPreferences prefs) {
    final raw = prefs.getString(_kBookmarks);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = decoded
          .whereType<Map>()
          .map((e) => MushafBookmark.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.ayahKey.contains(':'))
          .toList();
      items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> contains(String ayahKey) async =>
      (await list()).any((b) => b.ayahKey == ayahKey);

  /// إضافة فاصلة (تُستبدل الموجودة لنفس الآية والرواية).
  Future<void> add(MushafBookmark bookmark) async {
    final prefs = await _prefsProvider();
    await _migrateLegacy(prefs);
    final items = List<MushafBookmark>.from(await list());
    items.removeWhere(
      (b) => b.ayahKey == bookmark.ayahKey && b.riwayaId == bookmark.riwayaId,
    );
    items.add(bookmark);
    await _persist(prefs, items);
  }

  Future<void> remove(String ayahKey, {String riwayaId = 'hafs'}) async {
    final prefs = await _prefsProvider();
    final items = List<MushafBookmark>.from(await list());
    items.removeWhere((b) => b.ayahKey == ayahKey && b.riwayaId == riwayaId);
    await _persist(prefs, items);
  }

  Future<void> _persist(SharedPreferences prefs, List<MushafBookmark> items) async {
    await prefs.setString(
      _kBookmarks,
      jsonEncode(items.map((b) => b.toJson()).toList()),
    );
  }

  /// ترحيل لمرة واحدة من قائمة المفاتيح الخام القديمة.
  /// الفواصل القديمة لا تحمل رقم الصفحة — تُرحَّل بدونه بصدق.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final legacy = prefs.getStringList(_kLegacyBookmarks);
    if (legacy == null || legacy.isEmpty) return;
    final existing = _readV1(prefs);
    final existingKeys = existing.map((b) => '${b.riwayaId}:${b.ayahKey}').toSet();
    final migrated = <MushafBookmark>[
      ...existing,
      for (final key in legacy)
        if (key.contains(':') && !existingKeys.contains('hafs:$key'))
          MushafBookmark(
            ayahKey: key,
            surahNumber: int.tryParse(key.split(':').first) ?? 1,
            verseNumber: int.tryParse(key.split(':').last) ?? 1,
            riwayaId: 'hafs',
          ),
    ];
    await _persist(prefs, migrated);
    await prefs.remove(_kLegacyBookmarks);
  }
}
