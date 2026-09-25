/// إصدارات المصحف المصوّر: نسخ محددة من صور صفحات المصحف قابلة للاختيار.
///
/// الفكرة: الرواية الواحدة (حفص) قد تتوفّر بأكثر من نسخة مصوّرة
/// (المصحف المدني العادي، ونسخة التجويد الملوّن)، ولكل نسخة:
/// - قالب صور صفحاتها الخاص [pageImageTemplate] مع العنصر النائب {page}،
/// - عدد صفحاتها [totalPages] — النسختان الموثّقتان حاليًا 604 صفحات فقط
///   (تخطيط المصحف المدني)، ولا يُعتمد أي مصدر بعدد صفحات مختلف،
/// - طريقة ترقيم الملفات عبر [pagePadWidth] (0 = بلا تبطين بالأصفار،
///   كما في مصادر QuranHub الحالية حيث الملفات 1.jpg … 604.jpg).
///
/// مصادر الصور والتحقق الحي موثّقة في docs/MUSHAF_SOURCES.md.
class MushafEdition {
  const MushafEdition({
    required this.id,
    required this.riwayaId,
    required this.nameAr,
    required this.pageImageTemplate,
    this.totalPages = 604,
    this.pagePadWidth = 0,
    this.notesAr = '',
  });

  final String id;
  final String riwayaId;
  final String nameAr;
  final String pageImageTemplate;
  final int totalPages;
  final int pagePadWidth;
  final String notesAr;

  /// مدعوم للعرض المصوّر فقط عندما يكون تخطيط 604 صفحات موثّقًا
  /// وقالب الصور يحمل العنصر النائب {page}.
  bool get supportsPages =>
      totalPages == 604 && pageImageTemplate.contains('{page}');

  /// رابط صورة الصفحة؛ يرمي AssertionError خارج النطاق في وضع التطوير.
  String pageImageUrl(int page) {
    assert(page >= 1 && page <= totalPages, 'page out of range: $page');
    final raw = page.clamp(1, totalPages).toString().padLeft(pagePadWidth, '0');
    return pageImageTemplate.replaceAll('{page}', raw);
  }

  factory MushafEdition.fromJson(Map<String, dynamic> json) => MushafEdition(
        id: (json['id'] ?? '').toString(),
        riwayaId: (json['riwayaId'] ?? '').toString(),
        nameAr: (json['nameAr'] ?? '').toString(),
        pageImageTemplate: (json['pageImageTemplate'] ?? '').toString(),
        totalPages: (json['totalPages'] as num?)?.toInt() ?? 604,
        pagePadWidth: (json['pagePadWidth'] as num?)?.toInt() ?? 0,
        notesAr: (json['notesAr'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'riwayaId': riwayaId,
        'nameAr': nameAr,
        'pageImageTemplate': pageImageTemplate,
        'totalPages': totalPages,
        'pagePadWidth': pagePadWidth,
        'notesAr': notesAr,
      };

  static List<MushafEdition> parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MushafEdition.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }
}

class MushafEditionRegistry {
  /// النسختان الموثّقتان للمصحف المدني (حفص — 604 صفحات).
  /// تحقّق حي 2026-09-23: الصفحات 1/100/300/500/604 لكل نسخة
  /// (HTTP 200، image/jpeg، بايتات JPEG سحرية عبر byte-range).
  static const builtin = <MushafEdition>[
    MushafEdition(
      id: 'hafs-madani',
      riwayaId: 'hafs',
      nameAr: 'المصحف المدني (عادي)',
      pageImageTemplate:
          'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/kfgqpc/hafs-wasat/{page}.jpg',
      totalPages: 604,
      pagePadWidth: 0,
      notesAr:
          'نسخة KFGQPC (المصحف المدني) عبر مستودع QuranHub — تحقّق حي 2026-09-23',
    ),
    MushafEdition(
      id: 'hafs-madani-tajweed',
      riwayaId: 'hafs',
      nameAr: 'المصحف الملوّن بالتجويد',
      pageImageTemplate:
          'https://raw.githubusercontent.com/QuranHub/quran-pages-images/main/easyquran.com/hafs-tajweed/{page}.jpg',
      totalPages: 604,
      pagePadWidth: 0,
      notesAr:
          'نسخة التجويد الملوّن (easyquran.com) عبر مستودع QuranHub — تحقّق حي 2026-09-23',
    ),
  ];

  /// دمج قيم الـ Backend فوق المضمّنة (الأولوية للـ Backend عند تطابق id).
  static List<MushafEdition> merge(List<MushafEdition> backend) {
    final merged = <MushafEdition>[...backend];
    final ids = merged.map((e) => e.id).toSet();
    for (final edition in builtin) {
      if (!ids.contains(edition.id)) merged.add(edition);
    }
    return merged;
  }

  static MushafEdition byId(String id, [List<MushafEdition>? merged]) {
    final list = merged ?? builtin;
    return list.firstWhere(
      (e) => e.id == id,
      orElse: () => throw StateError('Unknown mushaf edition: $id'),
    );
  }

  /// يحوّل حمولة الـ Backend إلى قائمة، متجاهلًا المدخلات الفاسدة.
  static List<MushafEdition> parseList(dynamic raw) => MushafEdition.parseList(raw);

  /// إصدارات رواية معيّنة (تُستخدم لبناء منتقي النسخة في الإعدادات).
  static List<MushafEdition> forRiwaya(String riwayaId,
      [List<MushafEdition>? merged]) {
    final list = merged ?? builtin;
    return list.where((e) => e.riwayaId == riwayaId).toList();
  }
}
