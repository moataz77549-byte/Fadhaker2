/// سجل الروايات (Riwaya Registry).
///
/// كل رواية تحمل الـ metadata الخاص بها، وأهمها تخطيط الصفحات.
/// القاعدة الصارمة: لا نفترض أن كل رواية 604 صفحة — [totalPages]
/// قد يكون null بمعنى "غير معروف بعد"، وعندها يتعطّل وضع المصحف
/// المصوّر لهذه الرواية ويظهر Empty State بدل بيانات وهمية.
///
/// مصادر القيم:
/// - القائمة المضمّنة أدناه للتعريف الأساسي فقط (أسماء الروايات).
/// - عدد الصفحات وقوالب روابط الصور ومعرّف الـ mushaf في Quran Foundation
///   تُجلب من الـ Backend عبر `QuranConfigRepository` (قابلة للتغيير
///   دون تحديث التطبيق).
class Riwaya {
  const Riwaya({
    required this.id,
    required this.nameAr,
    required this.narratorAr,
    required this.totalPages,
    required this.pageImageTemplate,
    required this.qfMushafId,
    required this.textAvailable,
    this.notesAr = '',
  });

  /// معرّف ثابت: hafs | warsh | qalun | duri
  final String id;

  /// مثال: «حفص عن عاصم»
  final String nameAr;

  /// مثال: «عاصم بن أبي النجود»
  final String narratorAr;

  /// عدد صفحات المصحف المطبوع لهذه الرواية، أو null إذا لم يوثّق بعد.
  /// حفص (المصحف المدني) = 604 صفحة. غيرها: يُجلب من الـ Backend.
  final int? totalPages;

  /// قالب رابط صورة الصفحة، فيه العنصر النائب {page} برقم من 3 خانات.
  /// null = لا يوجد مصدر صور موثّق لهذه الرواية بعد.
  final String? pageImageTemplate;

  /// معرّف الـ mushaf في Quran Foundation API (يُستخدم في ?mushaf=)،
  /// أو null إذا لم يكن مدعومًا هناك.
  final int? qfMushafId;

  /// هل يتوفّر نص الآيات لهذه الرواية عبر الـ Backend حاليًا؟
  final bool textAvailable;

  final String notesAr;

  /// وضع المصحف المصوّر متاح فقط عند توثيق عدد الصفحات وقالب الصور معًا.
  bool get supportsImagePages =>
      totalPages != null && totalPages! > 0 && (pageImageTemplate?.isNotEmpty ?? false);

  /// رابط صورة صفحة معيّنة حسب القالب.
  String pageImageUrl(int page) {
    final template = pageImageTemplate;
    if (template == null || template.isEmpty) {
      throw StateError('لا يوجد قالب صور موثّق للرواية $nameAr');
    }
    return template.replaceAll('{page}', page.toString().padLeft(3, '0'));
  }

  factory Riwaya.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('Riwaya id is missing');
    return Riwaya(
      id: id,
      nameAr: json['nameAr'] as String? ?? id,
      narratorAr: json['narratorAr'] as String? ?? '',
      totalPages: (json['totalPages'] as num?)?.toInt(),
      pageImageTemplate: json['pageImageTemplate'] as String?,
      qfMushafId: (json['qfMushafId'] as num?)?.toInt(),
      textAvailable: json['textAvailable'] as bool? ?? false,
      notesAr: json['notesAr'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'narratorAr': narratorAr,
        'totalPages': totalPages,
        'pageImageTemplate': pageImageTemplate,
        'qfMushafId': qfMushafId,
        'textAvailable': textAvailable,
        'notesAr': notesAr,
      };
}

/// السجل المضمّن كاحتياطي للتعريف فقط.
/// ملاحظة: عدد الصفحات موثّق لحفص فقط (604 للمصحف المدني)؛
/// باقي الروايات totalPages = null حتى يوثّقها الـ Backend.
class RiwayaRegistry {
  const RiwayaRegistry._();

  static const hafs = Riwaya(
    id: 'hafs',
    nameAr: 'حفص عن عاصم',
    narratorAr: 'عاصم بن أبي النجود الكوفي',
    totalPages: 604,
    pageImageTemplate: null,
    qfMushafId: 1,
    textAvailable: true,
    notesAr: 'المصحف المدني — 15 سطرًا في الصفحة',
  );

  static const warsh = Riwaya(
    id: 'warsh',
    nameAr: 'ورش عن نافع',
    narratorAr: 'نافع بن عبد الرحمن المدني',
    totalPages: null,
    pageImageTemplate: null,
    qfMushafId: null,
    textAvailable: false,
    notesAr: 'عدد الصفحات يختلف باختلاف الطبعة — يُوثّق من الـ Backend',
  );

  static const qalun = Riwaya(
    id: 'qalun',
    nameAr: 'قالون عن نافع',
    narratorAr: 'نافع بن عبد الرحمن المدني',
    totalPages: null,
    pageImageTemplate: null,
    qfMushafId: null,
    textAvailable: false,
    notesAr: 'عدد الصفحات يختلف باختلاف الطبعة — يُوثّق من الـ Backend',
  );

  static const duri = Riwaya(
    id: 'duri',
    nameAr: 'الدوري عن أبي عمرو',
    narratorAr: 'أبو عمرو بن العلاء البصري',
    totalPages: null,
    pageImageTemplate: null,
    qfMushafId: null,
    textAvailable: false,
    notesAr: 'عدد الصفحات يختلف باختلاف الطبعة — يُوثّق من الـ Backend',
  );

  static const List<Riwaya> builtin = [hafs, warsh, qalun, duri];

  static Riwaya byId(String id, [List<Riwaya>? source]) {
    final list = source ?? builtin;
    return list.firstWhere(
      (r) => r.id == id,
      orElse: () => throw ArgumentError('رواية غير معروفة: $id'),
    );
  }

  /// يدمج قائمة الـ Backend فوق القائمة المضمّنة (الأولوية للـ Backend).
  static List<Riwaya> merge(List<Riwaya> backend) {
    final merged = <String, Riwaya>{for (final r in builtin) r.id: r};
    for (final r in backend) {
      merged[r.id] = r;
    }
    return merged.values.toList(growable: false);
  }

  /// يحوّل حمولة الـ Backend إلى قائمة، متجاهلًا المدخلات الفاسدة.
  static List<Riwaya> parseList(dynamic value) {
    if (value is! List) return const [];
    final out = <Riwaya>[];
    for (final item in value.whereType<Map<String, dynamic>>()) {
      try {
        out.add(Riwaya.fromJson(item));
      } on FormatException {
        continue;
      }
    }
    return out;
  }
}
