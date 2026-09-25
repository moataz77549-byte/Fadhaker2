/// خيارات الخطوط في وضع النص.
///
/// كل خيار يشير إلى Font Family تُحمَّل ملفاته عند أول استخدام من
/// [downloadUrl] وتُخزَّن على قرص الجهاز (لا تُضمَّن في حزمة التطبيق) —
/// راجع `features/quran/README.md` قسم «الخطوط» و data/quran_font_loader.dart.
/// إن تعذّر التحميل (أو لم يوجد رابط موثّق)، يسقط العرض على خط النظام
/// دون كسر، وتظهر ملاحظة صادقة في شاشة الإعدادات.
///
/// الرواية تؤثر فعليًا على الخط: كل خيار يعلن الروايات التي يدعمها عبر
/// [supportedRiwayaIds]، والقارئ يختار تلقائيًا أول خط يدعم الرواية
/// الحالية، وورقة الإعدادات تعرض فقط الخطوط الداعمة للرواية المختارة.
/// القيمة الافتراضية ['hafs'] — الخطوط المضمّنة عثمانية برسم حفص، وأي دعم
/// لرواية أخرى يجب توثيقه صراحةً من الـ Backend (لا ادّعاء ضمني).
class QuranFontOption {
  const QuranFontOption({
    required this.id,
    required this.nameAr,
    required this.fontFamily,
    required this.lineHeight,
    required this.licenseNoteAr,
    this.downloadUrl,
    this.supportedRiwayaIds = const ['hafs'],
  });

  final String id;
  final String nameAr;

  /// اسم العائلة الذي يُسجَّل به الخط عبر FontLoader عند التحميل.
  final String fontFamily;

  /// ارتفاع السطر الموصى به لهذا الخط لمنع تداخل الحروف والتشكيل.
  /// الخطوط العثمانية ذات التشكيل الكثيف تحتاج 2.0 على الأقل.
  final double lineHeight;

  final String licenseNoteAr;

  /// رابط ملف الخط (TTF) للتحميل عند أول استخدام؛ null = لا مصدر
  /// تحميل موثّق — يُستخدم خط النظام مع ملاحظة صادقة.
  final String? downloadUrl;

  /// معرّفات الروايات التي يدعمها هذا الخط (hafs | warsh | qalun | duri).
  final List<String> supportedRiwayaIds;

  /// هل للخط مصدر تحميل موثّق؟
  bool get hasDownload => downloadUrl != null && downloadUrl!.isNotEmpty;

  bool supportsRiwaya(String riwayaId) => supportedRiwayaIds.contains(riwayaId);

  factory QuranFontOption.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('Font id is missing');
    final rawSupported = json['supportedRiwayaIds'];
    final supported = rawSupported is List
        ? rawSupported.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final downloadUrl = json['downloadUrl'] as String?;
    return QuranFontOption(
      id: id,
      nameAr: json['nameAr'] as String? ?? id,
      fontFamily: json['fontFamily'] as String? ?? id,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 2.0,
      licenseNoteAr: json['licenseNoteAr'] as String? ?? '',
      downloadUrl:
          downloadUrl == null || downloadUrl.trim().isEmpty ? null : downloadUrl.trim(),
      supportedRiwayaIds: supported.isEmpty ? const ['hafs'] : supported,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'fontFamily': fontFamily,
        'lineHeight': lineHeight,
        'licenseNoteAr': licenseNoteAr,
        'downloadUrl': downloadUrl,
        'supportedRiwayaIds': supportedRiwayaIds,
      };
}

class QuranFontRegistry {
  const QuranFontRegistry._();

  /// QPC Hafs font — خط KFGQPC العثماني (حفص) عبر QUL/Tarteel.
  /// تحقّق حي 2026-09-23: HTTP 200، font/ttf، 297,700 بايت.
  static const uthmanicHafs = QuranFontOption(
    id: 'uthmanic-hafs',
    nameAr: 'العثماني — حفص',
    fontFamily: 'UthmanicHafs',
    lineHeight: 2.1,
    licenseNoteAr:
        'QPC Hafs font (KFGQPC) عبر QUL/Tarteel — تحقّق حي 2026-09-23؛ شروط KFGQPC: استخدام ونسخ وتوزيع مجاني مع الإسناد، بلا تعديل أو بيع',
    downloadUrl: 'https://static-cdn.tarteel.ai/qul/fonts/UthmanicHafs_V22.ttf',
    supportedRiwayaIds: ['hafs'],
  );

  /// KFGQPC Uthmanic Hafs — إصدار 1.8 عبر مرآة jsDelivr.
  /// تحقّق حي 2026-09-23: HTTP 200، font/ttf، 242,368 بايت.
  static const kfgqpcHafs = QuranFontOption(
    id: 'kfgqpc-hafs',
    nameAr: 'مجمع الملك فهد — حفص',
    fontFamily: 'KFGQPCUthmanicScriptHAFS',
    lineHeight: 2.0,
    licenseNoteAr:
        'KFGQPC Uthmanic Hafs (إصدار 1.8) عبر مرآة jsDelivr — تحقّق حي 2026-09-23',
    downloadUrl:
        'https://cdn.jsdelivr.net/gh/mohammed-2-5/islamic-library-data@master/fonts/UthmanicHafs_v18.ttf',
    supportedRiwayaIds: ['hafs'],
  );

  /// لا يوجد ملف QCF نصي واحد موثّق: خطوط QCF في منظومة Quran Foundation
  /// هي خطوط glyphs ملفٌ لكل صفحة (604 ملفات لنقاط PUA) ولا تصلح خطًّا
  /// نصيًا عامًا — تُعرض بلا تحميل ويُستخدم خط النظام.
  static const qcf = QuranFontOption(
    id: 'qcf',
    nameAr: 'QCF',
    fontFamily: 'QCF',
    lineHeight: 2.0,
    licenseNoteAr:
        'خطوط QCF من Quran Foundation — لا يوجد ملف نصي واحد موثّق (QCF ملفٌ لكل صفحة)؛ يُستخدم خط النظام',
    supportedRiwayaIds: ['hafs'],
  );

  /// لم يُعثر على مصدر تحميل موثّق لخط بهذا الاسم — يُعرض بلا تحميل
  /// ويُستخدم خط النظام مع ملاحظة صادقة.
  static const uthmanicVector = QuranFontOption(
    id: 'uthmanic-vector',
    nameAr: 'العثماني المتجه (Vector)',
    fontFamily: 'UthmanicVector',
    lineHeight: 2.0,
    licenseNoteAr:
        'لم يُعثر على مصدر تحميل موثّق لهذا الخط؛ يُستخدم خط النظام',
    supportedRiwayaIds: ['hafs'],
  );

  static const List<QuranFontOption> builtin = [
    uthmanicHafs,
    kfgqpcHafs,
    qcf,
    uthmanicVector,
  ];

  static QuranFontOption byId(String id, [List<QuranFontOption>? source]) {
    final list = source ?? builtin;
    return list.firstWhere(
      (f) => f.id == id,
      orElse: () => builtin.first,
    );
  }

  /// أفضل خط لرواية معيّنة: أول خط يدعمها، وإلا أول خط في القائمة
  /// (لا كسر — يُستخدم كملاذ أخير مع خط النظام).
  static QuranFontOption bestForRiwaya(String riwayaId, [List<QuranFontOption>? source]) {
    final list = source ?? builtin;
    for (final font in list) {
      if (font.supportsRiwaya(riwayaId)) return font;
    }
    return list.isNotEmpty ? list.first : builtin.first;
  }

  static List<QuranFontOption> merge(List<QuranFontOption> backend) {
    final merged = <String, QuranFontOption>{for (final f in builtin) f.id: f};
    for (final f in backend) {
      merged[f.id] = f;
    }
    return merged.values.toList(growable: false);
  }

  static List<QuranFontOption> parseList(dynamic value) {
    if (value is! List) return const [];
    final out = <QuranFontOption>[];
    for (final item in value.whereType<Map<String, dynamic>>()) {
      try {
        out.add(QuranFontOption.fromJson(item));
      } on FormatException {
        continue;
      }
    }
    return out;
  }
}
